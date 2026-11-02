-- New policy boundaries preserving pricing/provider contracts.
begin;
create or replace function arena_private.fulfill_order(p_id uuid)
returns void language plpgsql set search_path=public as $$
declare o checkout_orders%rowtype;c uuid;bid uuid;mid uuid;g text;b record;capacity integer;begin
 select * into strict o from checkout_orders where id=p_id for update;
 if o.entitlement_revoked_at is not null or o.cancellation_requested_at is not null then raise exception 'ENTITLEMENT_REVOKED';end if;
 if o.fulfillment_status='fulfilled' then return;end if;
 if o.payment_method='card' and o.payment_status<>'paid' then raise exception 'PAYMENT_NOT_VERIFIED';end if;
 if o.fulfillment_status<>'pending' then raise exception 'ORDER_NOT_FULFILLABLE';end if;
 perform pg_advisory_xact_lock(hashtextextended(o.arena_id::text,0));
 if o.purpose='participant' then
  perform 1 from matches where id=o.match_id and status<>'cancelled' and starts_at>now() for update;
  if not found then raise exception 'MATCH_UNAVAILABLE';end if;
  if exists(select 1 from checkout_orders where match_id=o.match_id and id<>o.id and seat_index=o.seat_index and fulfillment_status='fulfilled' and entitlement_revoked_at is null) then raise exception 'SEAT_UNAVAILABLE';end if;
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

create or replace function public.create_participant_checkout(p_match uuid,p_request_key uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid:=public.require_oman_user();m matches%rowtype;host_order checkout_orders%rowtype;o checkout_orders%rowtype;seat integer;prior jsonb;begin
 if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
 prior:=arena_private.begin_request(p_request_key,'participant',jsonb_build_object('match_id',p_match));
 if prior is not null then select * into strict o from checkout_orders where id=(prior->>'id')::uuid and user_id=u;return to_jsonb(o);end if;
 perform arena_private.lock_match(p_match);
 perform arena_private.decide_match(p_match);
 select * into strict m from matches where id=p_match for update;
 if m.status='cancelled' or m.starts_at<=now() then raise exception 'MATCH_UNAVAILABLE';end if;
 if m.checkout_order_id is null then raise exception 'LEGACY_MATCH_USE_JOIN';end if;
 if not exists(select 1 from profiles where id=u and gender=m.gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
 if m.is_private and m.host_id<>u and not exists(select 1 from match_players where match_id=m.id and user_id=u and status in('invited','joined')) then raise exception 'INVITATION_REQUIRED';end if;
 select * into strict host_order from checkout_orders where id=m.checkout_order_id;
 if not ((host_order.payment_status='paid' and host_order.fulfillment_status='fulfilled') or (m.payment_mode='pay_individually' and host_order.entitlement_revoked_at is not null and host_order.cancellation_policy_reason='MATCH_WITHDRAWAL_FULL_REFUND' and host_order.payment_status in('paid','partially_refunded','refunded'))) then raise exception 'HOST_PAYMENT_REQUIRED';end if;
 select * into o from checkout_orders where match_id=m.id and user_id=u and fulfillment_status<>'cancelled' and entitlement_revoked_at is null;
 if found then
  if o.fulfillment_status='fulfilled' and o.payment_status='paid' then perform public.join_match(p_match,u);end if;
  return to_jsonb(o);
 end if;
 if m.payment_mode='host_pays_all' then
  if not exists(select 1 from match_players where match_id=m.id and user_id=u and status='joined') and (select count(*) from match_players where match_id=m.id and status='joined')>=m.max_players then raise exception 'MATCH_FULL';end if;
  insert into match_players(match_id,user_id,status,covered_by_host) values(m.id,u,'joined',true) on conflict on constraint match_players_pkey do update set status='joined',covered_by_host=true;
  return jsonb_build_object('covered_by_host',true,'fulfillment_status','fulfilled','match_id',m.id);
 end if;
 select s into seat from generate_series(0,m.max_players-1) s where not exists(select 1 from checkout_orders x where x.match_id=m.id and x.seat_index=s and x.fulfillment_status<>'cancelled' and x.entitlement_revoked_at is null) order by s limit 1;
 if seat is null then raise exception 'MATCH_FULL';end if;
 insert into checkout_orders(user_id,arena_id,request_key,request_payload,purpose,payment_method,payment_status,base_amount_baisa,total_amount_baisa,amount_due_baisa,starts_at,ends_at,payment_mode,seat_index,match_id)
 values(u,m.arena_id,p_request_key,jsonb_build_object('match_id',m.id),'participant','card','pending',host_order.base_amount_baisa,m.total_amount_baisa,arena_private.share_baisa(m.total_amount_baisa,m.max_players,seat),m.starts_at,m.ends_at,m.payment_mode,seat,m.id) returning * into o;
 if o.amount_due_baisa<100 then raise exception 'CARD_MINIMUM_100_BAISA';end if;
 update arena_private.requests set result=jsonb_build_object('id',o.id) where user_id=u and request_key=p_request_key;
 return to_jsonb(o);
end $$;

create or replace function public.enforce_match_payment_entitlement()
returns trigger language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;begin
 select * into strict m from matches where id=new.match_id;
 if m.checkout_order_id is null or new.status<>'joined' then return new;end if;
 if m.payment_mode='host_pays_all' and exists(select 1 from checkout_orders where id=m.checkout_order_id and payment_status='paid' and amount_due_baisa=m.total_amount_baisa) then
  new.covered_by_host:=true;return new;
 end if;
 if not exists(select 1 from checkout_orders where id=new.payment_order_id and user_id=new.user_id and payment_status='paid' and entitlement_revoked_at is null and not exists(select 1 from payment_refunds r where r.order_id=checkout_orders.id and r.status<>'failed') and (match_id=m.id or id=m.checkout_order_id)) then raise exception 'PARTICIPANT_PAYMENT_REQUIRED';end if;
 new.covered_by_host:=false;return new;
end $$;

create or replace function arena_private.decide_match(p_match uuid) returns text
language plpgsql set search_path=public as $$
declare m matches%rowtype;n bigint;outcome text;o record;begin
 perform arena_private.lock_match(p_match);
 select * into strict m from matches where id=p_match;
 if m.decision_outcome<>'pending' then return m.decision_outcome;end if;
 if m.decision_at>clock_timestamp() then return 'pending';end if;
 if m.status='cancelled' then return 'cancelled';end if;
 -- The host row is created during fulfillment before its order is finalized.
 if m.checkout_order_id is not null and not exists(select 1 from checkout_orders
   where id=m.checkout_order_id and ((fulfillment_status='fulfilled' and payment_status='paid') or (m.payment_mode='pay_individually' and entitlement_revoked_at is not null and cancellation_policy_reason='MATCH_WITHDRAWAL_FULL_REFUND' and payment_status in('paid','partially_refunded','refunded')))) then return 'pending';end if;
 n:=arena_private.eligible_match_players(m.id);
 outcome:=case when n*5>=m.max_players::bigint*4 then 'confirmed' else 'cancelled' end;
 insert into arena_private.match_decisions(match_id,outcome,joined_count,max_players,decision_at)
 values(m.id,outcome,n,m.max_players,m.decision_at);
 update matches set decision_outcome=outcome,decided_at=clock_timestamp(),decision_joined_count=n,
  status=outcome,cancellation_reason=case when outcome='cancelled' then 'MINIMUM_PARTICIPATION_NOT_REACHED' end where id=m.id;
 if outcome='cancelled' then
  for o in select id from checkout_orders where id=m.checkout_order_id or match_id=m.id order by id loop
   perform arena_private.require_cancelled_match_refund(o.id);
  end loop;
 end if;
 return outcome;
end $$;

create or replace function arena_private.addon_available(p_addon uuid,p_start timestamptz,p_end timestamptz)
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
  where b.arena_addon_id=a.id and o.fulfillment_status in('fulfilled','refund_required') and b.released_at is null
  and o.starts_at<p_end and o.ends_at>p_start
  and (exists(select 1 from bookings x where x.id=o.booking_id and x.status<>'cancelled')
       or exists(select 1 from matches x where x.id=o.match_id and x.status<>'cancelled'))
 ), points as (select p_start as t union select starts_at from rentals where starts_at>=p_start)
 select coalesce(max((select coalesce(sum(r.quantity),0) from rentals r where r.starts_at<=p.t and r.ends_at>p.t)),0)::integer into used from points p;
 return greatest(0,least(100,a.stock-used));
end $$;

create or replace function public.admin_set_arena_addon(p_arena uuid,p_code text,p_enabled boolean,p_unit_baisa bigint,p_stock integer)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;v_peak integer;begin
 if not public.is_platform_admin() then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_arena::text,0));
 if p_stock is null and exists(select 1 from addon_types where code=p_code and kind='rental') then raise exception 'RENTAL_STOCK_REQUIRED';end if;
 if exists(select 1 from addon_types where code=p_code and kind='rental') then
  with rentals as (
   select o.starts_at,o.ends_at,b.quantity from booking_addons b join checkout_orders o on o.id=b.order_id
   join arena_addons a on a.id=b.arena_addon_id where a.arena_id=p_arena and a.addon_code=p_code and o.fulfillment_status in('fulfilled','refund_required') and b.released_at is null and o.ends_at>now()
   and (exists(select 1 from bookings x where x.id=o.booking_id and x.status<>'cancelled') or exists(select 1 from matches x where x.id=o.match_id and x.status<>'cancelled'))
  ) select coalesce(max((select sum(r.quantity) from rentals r where r.starts_at<=p.starts_at and r.ends_at>p.starts_at)),0)::integer into v_peak from rentals p;
  if p_stock<v_peak then raise exception 'STOCK_BELOW_RESERVED_QUANTITY';end if;
 end if;
 insert into arena_addons(arena_id,addon_code,enabled,unit_amount_baisa,stock) values(p_arena,p_code,p_enabled,p_unit_baisa,p_stock)
 on conflict(arena_id,addon_code) do update set enabled=excluded.enabled,unit_amount_baisa=excluded.unit_amount_baisa,stock=excluded.stock,updated_at=now() returning id into v_id;
 return v_id;
end $$;

create or replace function public.match_payment_summary(p_match uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare m matches%rowtype;covered boolean;seat integer;begin
 if not public.can_view_match(p_match,auth.uid()) then raise exception 'MATCH_NOT_FOUND';end if;
 select * into strict m from matches where id=p_match;
 if m.checkout_order_id is null then return jsonb_build_object('legacy',true);end if;
 covered:=m.payment_mode='host_pays_all' and exists(select 1 from checkout_orders where id=m.checkout_order_id and payment_status='paid' and fulfillment_status='fulfilled' and amount_due_baisa=m.total_amount_baisa);
 select s into seat from generate_series(0,m.max_players-1)s where not exists(select 1 from checkout_orders o where o.match_id=m.id and o.seat_index=s and o.fulfillment_status<>'cancelled' and o.entitlement_revoked_at is null) order by s limit 1;
 return jsonb_build_object('payment_mode',m.payment_mode,'covered_by_host',covered,'total_amount_baisa',m.total_amount_baisa,'next_share_baisa',case when covered then 0 when seat is not null then arena_private.share_baisa(m.total_amount_baisa,m.max_players,seat) else null end);
end $$;
commit;
