begin;
create function arena_private.share_baisa(p_total bigint,p_capacity integer,p_seat integer)
returns bigint language plpgsql immutable as $$ begin
 if p_total<0 or p_capacity<2 or p_seat<0 or p_seat>=p_capacity then raise exception 'INVALID_SHARE';end if;
 return p_total/p_capacity + case when p_seat<p_total%p_capacity then 1 else 0 end;
end $$;

create function arena_private.addon_available(p_addon uuid,p_start timestamptz,p_end timestamptz)
returns integer language plpgsql stable set search_path=public as $$
declare a arena_addons%rowtype;k text;used integer;begin
 select * into strict a from arena_addons where id=p_addon;
 select kind into k from addon_types where code=a.addon_code;
 if not a.enabled then return 0;end if;
 if a.stock is null then return 100;end if;
 if k='consumable' then return least(a.stock,100);end if;
 -- Compute peak, not the sum of rentals that overlap different portions.
 with rentals as (
  select o.starts_at,o.ends_at,b.quantity from booking_addons b join checkout_orders o on o.id=b.order_id
  where b.arena_addon_id=a.id and o.fulfillment_status='fulfilled'
  and o.starts_at<p_end and o.ends_at>p_start
  and (exists(select 1 from bookings x where x.id=o.booking_id and x.status<>'cancelled')
       or exists(select 1 from matches x where x.id=o.match_id and x.status<>'cancelled'))
 ), points as (select p_start as t union select starts_at from rentals where starts_at>=p_start)
 select coalesce(max((select coalesce(sum(r.quantity),0) from rentals r where r.starts_at<=p.t and r.ends_at>p.t)),0)::integer into used from points p;
 return greatest(0,least(100,a.stock-used));
end $$;

create function public.admin_set_arena_addon(p_arena uuid,p_code text,p_enabled boolean,p_unit_baisa bigint,p_stock integer)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;v_peak integer;begin
 if not public.is_platform_admin() then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_arena::text,0));
 if p_stock is null and exists(select 1 from addon_types where code=p_code and kind='rental') then raise exception 'RENTAL_STOCK_REQUIRED';end if;
 if exists(select 1 from addon_types where code=p_code and kind='rental') then
  with rentals as (
   select o.starts_at,o.ends_at,b.quantity from booking_addons b join checkout_orders o on o.id=b.order_id
   join arena_addons a on a.id=b.arena_addon_id where a.arena_id=p_arena and a.addon_code=p_code and o.fulfillment_status='fulfilled' and o.ends_at>now()
   and (exists(select 1 from bookings x where x.id=o.booking_id and x.status<>'cancelled') or exists(select 1 from matches x where x.id=o.match_id and x.status<>'cancelled'))
  ) select coalesce(max((select sum(r.quantity) from rentals r where r.starts_at<=p.starts_at and r.ends_at>p.starts_at)),0)::integer into v_peak from rentals p;
  if p_stock<v_peak then raise exception 'STOCK_BELOW_RESERVED_QUANTITY';end if;
 end if;
 insert into arena_addons(arena_id,addon_code,enabled,unit_amount_baisa,stock) values(p_arena,p_code,p_enabled,p_unit_baisa,p_stock)
 on conflict(arena_id,addon_code) do update set enabled=excluded.enabled,unit_amount_baisa=excluded.unit_amount_baisa,stock=excluded.stock,updated_at=now() returning id into v_id;
 return v_id;
end $$;

create function public.checkout_quote(p_arena uuid,p_start timestamptz,p_end timestamptz,p_addons jsonb default '[]',p_coupon uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid:=public.require_oman_user();base bigint;total bigint;discount bigint:=0;items jsonb:='[]';catalog jsonb;item jsonb;a record;qty integer;available integer;begin
 if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
 if not exists(select 1 from profiles p join arenas ar on ar.id=p_arena where p.id=u and p.gender=ar.audience_gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
 if not public.arena_has_available_court(p_arena,p_start,p_end) then raise exception 'SLOT_UNAVAILABLE';end if;
 if jsonb_typeof(p_addons)<>'array' or jsonb_array_length(p_addons)>100 then raise exception 'INVALID_ADDONS';end if;
 if (select count(*) from jsonb_array_elements(p_addons))<>(select count(distinct x->>'id') from jsonb_array_elements(p_addons) x) then raise exception 'DUPLICATE_ADDON';end if;
 select round(price_per_hour*1000*extract(epoch from(p_end-p_start))/3600)::bigint into base from arenas where id=p_arena;
 if base is null or base<0 then raise exception 'INVALID_ARENA_PRICE';end if;
 total:=base;
 for item in select value from jsonb_array_elements(p_addons) loop
  qty:=(item->>'quantity')::integer;
  if qty is null or qty<1 or qty>100 then raise exception 'INVALID_ADDON_QUANTITY';end if;
  select aa.*,t.name_en,t.name_ar,t.kind into a from arena_addons aa join addon_types t on t.code=aa.addon_code where aa.id=(item->>'id')::uuid and aa.arena_id=p_arena and aa.enabled;
  if not found then raise exception 'ADDON_UNAVAILABLE';end if;
  available:=arena_private.addon_available(a.id,p_start,p_end);
  if qty>available then raise exception 'ADDON_STOCK_UNAVAILABLE';end if;
  total:=total+a.unit_amount_baisa*qty;
  items:=items||jsonb_build_object('id',a.id,'code',a.addon_code,'name_en',a.name_en,'name_ar',a.name_ar,'kind',a.kind,'unit_amount_baisa',a.unit_amount_baisa,'quantity',qty);
 end loop;
 if p_coupon is not null then
  select least(total,round(value_omr*1000)::bigint) into discount from reward_coupons where id=p_coupon and user_id=u and status='available';
  if not found then raise exception 'COUPON_NOT_AVAILABLE';end if;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',aa.id,'code',aa.addon_code,'name_en',t.name_en,'name_ar',t.name_ar,'kind',t.kind,'unit_amount_baisa',aa.unit_amount_baisa,'available_quantity',arena_private.addon_available(aa.id,p_start,p_end)) order by aa.addon_code),'[]') into catalog
 from arena_addons aa join addon_types t on t.code=aa.addon_code where aa.arena_id=p_arena and aa.enabled and arena_private.addon_available(aa.id,p_start,p_end)>0;
 return jsonb_build_object('base_amount_baisa',base,'discount_baisa',discount,'total_amount_baisa',total-discount,'currency','OMR','addons',items,'catalog',catalog);
end $$;

create function arena_private.fulfill_order(p_id uuid)
returns void language plpgsql set search_path=public as $$
declare o checkout_orders%rowtype;c uuid;bid uuid;mid uuid;g text;b record;capacity integer;begin
 select * into strict o from checkout_orders where id=p_id for update;
 if o.fulfillment_status='fulfilled' then return;end if;
 if o.payment_method='card' and o.payment_status<>'paid' then raise exception 'PAYMENT_NOT_VERIFIED';end if;
 if o.fulfillment_status<>'pending' then raise exception 'ORDER_NOT_FULFILLABLE';end if;
 perform pg_advisory_xact_lock(hashtextextended(o.arena_id::text,0));
 if o.purpose='participant' then
  perform 1 from matches where id=o.match_id and status<>'cancelled' and starts_at>now() for update;
  if not found then raise exception 'MATCH_UNAVAILABLE';end if;
  if exists(select 1 from checkout_orders where match_id=o.match_id and id<>o.id and seat_index=o.seat_index and fulfillment_status='fulfilled') then raise exception 'SEAT_UNAVAILABLE';end if;
  select max_players into capacity from matches where id=o.match_id;
  if (select count(*) from match_players where match_id=o.match_id and status='joined')>=capacity then raise exception 'MATCH_FULL';end if;
  insert into match_players(match_id,user_id,status,payment_order_id) values(o.match_id,o.user_id,'joined',o.id)
  on conflict on constraint match_players_pkey do update set status='joined',payment_order_id=o.id;
 else
  c:=arena_private.allocate_court(o.arena_id,o.starts_at,o.ends_at);
  for b in select * from booking_addons where order_id=o.id order by arena_addon_id loop
   if arena_private.addon_available(b.arena_addon_id,o.starts_at,o.ends_at)<b.quantity then raise exception 'ADDON_STOCK_UNAVAILABLE';end if;
   if b.kind='consumable' then update arena_addons set stock=stock-b.quantity where id=b.arena_addon_id and stock is not null;end if;
  end loop;
  if o.coupon_id is not null then
   perform 1 from reward_coupons where id=o.coupon_id and user_id=o.user_id and status='available' for update;
   if not found then raise exception 'COUPON_NOT_AVAILABLE';end if;
  end if;
  if o.purpose='booking' then
   insert into bookings(user_id,arena_id,court_id,starts_at,ends_at,total_price,status,water_cartons,water_unit_price,idempotency_key,coupon_id,discount_amount,payment_method,payment_status,checkout_order_id)
   values(o.user_id,o.arena_id,c,o.starts_at,o.ends_at,o.total_amount_baisa/1000.0,'upcoming',0,0,o.request_key,o.coupon_id,o.discount_baisa/1000.0,o.payment_method,o.payment_status,o.id) returning id into bid;
   if o.coupon_id is not null then update reward_coupons set status='used',used_booking_id=bid,used_at=now() where id=o.coupon_id;end if;
  else
   select gender into g from profiles where id=o.user_id;
   capacity:=(o.request_payload->>'capacity')::integer;
   insert into matches(arena_id,court_id,host_id,name,description,rules,sport,starts_at,ends_at,max_players,price_per_player,gender,payment_method,show_joined_players,is_private,status,idempotency_key,checkout_order_id,payment_mode,total_amount_baisa)
   values(o.arena_id,c,o.user_id,o.request_payload->>'name',o.request_payload->>'description',o.request_payload->>'rules',o.request_payload->>'sport',o.starts_at,o.ends_at,capacity,arena_private.share_baisa(o.total_amount_baisa,capacity,0)/1000.0,g,'card',coalesce((o.request_payload->>'show_joined_players')::boolean,true),coalesce((o.request_payload->>'is_private')::boolean,false),'upcoming',o.request_key,o.id,o.payment_mode,o.total_amount_baisa) returning id into mid;
   insert into match_players(match_id,user_id,status,payment_order_id,covered_by_host) values(mid,o.user_id,'joined',o.id,o.payment_mode='host_pays_all');
  end if;
 end if;
 update checkout_orders set fulfillment_status='fulfilled',booking_id=coalesce(bid,booking_id),match_id=coalesce(mid,match_id),updated_at=now() where id=o.id;
end $$;

create function public.create_checkout(p_request jsonb,p_request_key uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid:=public.require_oman_user();prior jsonb;o checkout_orders%rowtype;q jsonb;item jsonb;purpose text:=p_request->>'purpose';method text:=p_request->>'payment_method';mode text:=p_request->>'payment_mode';capacity integer;due bigint;begin
 prior:=arena_private.begin_request(p_request_key,'checkout',p_request);
 if prior is not null then select * into strict o from checkout_orders where id=(prior->>'id')::uuid;return to_jsonb(o);end if;
 if purpose is null or purpose not in('booking','match') or method is null or method not in('cash','card') then raise exception 'INVALID_CHECKOUT';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_request->>'arena_id',0));
 q:=public.checkout_quote((p_request->>'arena_id')::uuid,(p_request->>'starts_at')::timestamptz,(p_request->>'ends_at')::timestamptz,coalesce(p_request->'addons','[]'),(p_request->>'coupon_id')::uuid);
 -- Client expected total is only a stale-quote check, never the price source.
 if p_request ? 'expected_total_baisa' and (p_request->>'expected_total_baisa')::bigint<>(q->>'total_amount_baisa')::bigint then raise exception 'PRICE_CHANGED';end if;
 due:=(q->>'total_amount_baisa')::bigint;
 if purpose='match' then
  capacity:=(p_request->>'capacity')::integer;
  if method<>'card' or mode is null or mode not in('pay_individually','host_pays_all') or capacity is null or capacity not between 2 and 100 or nullif(trim(p_request->>'name'),'') is null or p_request->>'coupon_id' is not null then raise exception 'INVALID_MATCH_PAYMENT';end if;
  if mode='pay_individually' then
   if due/capacity<100 then raise exception 'CARD_MINIMUM_100_BAISA_PER_PLAYER';end if;
   due:=arena_private.share_baisa(due,capacity,0);
  end if;
 end if;
 if method='card' and due<100 then raise exception 'CARD_MINIMUM_100_BAISA';end if;
 insert into checkout_orders(user_id,arena_id,request_key,request_payload,purpose,payment_method,payment_status,base_amount_baisa,discount_baisa,total_amount_baisa,amount_due_baisa,starts_at,ends_at,payment_mode,seat_index,coupon_id)
 values(u,(p_request->>'arena_id')::uuid,p_request_key,p_request,purpose,method,case when method='card' then 'pending' else 'unpaid' end,(q->>'base_amount_baisa')::bigint,(q->>'discount_baisa')::bigint,(q->>'total_amount_baisa')::bigint,due,(p_request->>'starts_at')::timestamptz,(p_request->>'ends_at')::timestamptz,case when purpose='match' then mode end,case when purpose='match' then 0 end,(p_request->>'coupon_id')::uuid) returning * into o;
 for item in select value from jsonb_array_elements(q->'addons') loop
  insert into booking_addons(order_id,arena_addon_id,addon_code,name_en,name_ar,kind,unit_amount_baisa,quantity) values(o.id,(item->>'id')::uuid,item->>'code',item->>'name_en',item->>'name_ar',item->>'kind',(item->>'unit_amount_baisa')::bigint,(item->>'quantity')::integer);
 end loop;
 if method='cash' then perform arena_private.fulfill_order(o.id);end if;
 update arena_private.requests set result=jsonb_build_object('id',o.id) where user_id=u and request_key=p_request_key;
 select * into o from checkout_orders where id=o.id;return to_jsonb(o);
end $$;

revoke all on function public.checkout_quote(uuid,timestamptz,timestamptz,jsonb,uuid),public.create_checkout(jsonb,uuid),public.admin_set_arena_addon(uuid,text,boolean,bigint,integer) from public,anon,authenticated;
grant execute on function public.checkout_quote(uuid,timestamptz,timestamptz,jsonb,uuid),public.create_checkout(jsonb,uuid),public.admin_set_arena_addon(uuid,text,boolean,bigint,integer) to authenticated;
revoke all on all functions in schema arena_private from public,anon,authenticated;
commit;
