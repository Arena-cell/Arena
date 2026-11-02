-- ONLY arena-staging: gtcrijikfaglqcwqozel. Never Production.
begin;
set local statement_timeout='120s';
do $$ begin
 if to_regclass('arena_private.phase2_backup_20261004') is null then raise exception 'BACKUP_REQUIRED';end if;
 if to_regclass('public.checkout_orders') is not null then raise exception 'PHASE2_ALREADY_APPLIED';end if;
 if exists(select 1 from inventory_migration_issues where resolved_at is null) then raise exception 'UNRESOLVED_INVENTORY';end if;
end $$;

-- SOURCE 202610040001_phase2_financial_schema.sql
-- Additive financial ledger. Existing Phase 1 migrations remain unchanged.

create table public.addon_types (
  code text primary key check(code ~ '^[a-z][a-z0-9_]{1,39}$'),
  name_en text not null, name_ar text not null,
  kind text not null check(kind in ('consumable','rental'))
);
insert into public.addon_types values ('water','Water','ماء','consumable'),('racket','Racket rental','تأجير مضرب','rental');
create table public.arena_addons (
  id uuid primary key default gen_random_uuid(),
  arena_id uuid not null references public.arenas(id),
  addon_code text not null references public.addon_types(code),
  enabled boolean not null default false,
  unit_amount_baisa bigint not null check(unit_amount_baisa between 0 and 5000000000),
  stock integer check(stock >= 0),
  updated_at timestamptz not null default now(),
  unique(arena_id,addon_code)
);
create table public.checkout_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  arena_id uuid not null references public.arenas(id),
  request_key uuid not null,
  request_payload jsonb not null,
  purpose text not null check(purpose in ('booking','match','participant')),
  payment_method text not null check(payment_method in ('cash','card')),
  payment_status text not null default 'unpaid' check(payment_status in ('unpaid','pending','paid','failed','cancelled','refunded','partially_refunded')),
  fulfillment_status text not null default 'pending' check(fulfillment_status in ('pending','fulfilled','refund_required','cancelled')),
  base_amount_baisa bigint not null check(base_amount_baisa >= 0),
  discount_baisa bigint not null default 0 check(discount_baisa >= 0),
  total_amount_baisa bigint not null check(total_amount_baisa >= 0),
  amount_due_baisa bigint not null check(amount_due_baisa >= 0),
  refunded_amount_baisa bigint not null default 0 check(refunded_amount_baisa >= 0 and refunded_amount_baisa <= amount_due_baisa),
  currency text not null default 'OMR' check(currency='OMR'),
  starts_at timestamptz not null, ends_at timestamptz not null check(ends_at > starts_at),
  payment_mode text check(payment_mode in ('pay_individually','host_pays_all')),
  seat_index integer check(seat_index >= 0),
  coupon_id uuid references public.reward_coupons(id),
  booking_id uuid references public.bookings(id),
  match_id uuid references public.matches(id),
  provider_session_id text unique, provider_invoice text,
  provider_creation_state text not null default 'not_started' check(provider_creation_state in ('not_started','creating','ready','uncertain')),
  provider_attempted_at timestamptz,
  failure_code text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(user_id,request_key),
  check(payment_method='card' or purpose='booking')
);
create unique index checkout_participant_once on public.checkout_orders(match_id,user_id) where purpose='participant' and fulfillment_status<>'cancelled';
create table public.booking_addons (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.checkout_orders(id),
  arena_addon_id uuid not null references public.arena_addons(id),
  addon_code text not null, name_en text not null, name_ar text not null,
  kind text not null check(kind in ('consumable','rental')),
  unit_amount_baisa bigint not null check(unit_amount_baisa >= 0),
  quantity integer not null check(quantity between 1 and 100),
  unique(order_id,arena_addon_id)
);
create table public.payment_refunds (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.checkout_orders(id),
  request_key uuid not null unique,
  original_amount_baisa bigint not null check(original_amount_baisa > 0),
  amount_baisa bigint not null check(amount_baisa > 0 and amount_baisa <= original_amount_baisa),
  reason text not null check(length(trim(reason))>0),
  status text not null default 'requested' check(status in ('requested','processing','succeeded','failed')),
  provider_reference text unique,
  requested_by uuid references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table arena_private.payment_events (
  event_key text primary key,
  order_id uuid not null references public.checkout_orders(id),
  verified_status text not null,
  received_at timestamptz not null default now()
);
alter table public.bookings add column payment_method text check(payment_method in ('cash','card','legacy_unknown'));
-- Never infer a historical payment method from confirmation or a paid flag.
update public.bookings set payment_method=case when booking_type='manual' and payment_status='unpaid' then 'cash' else 'legacy_unknown' end;
alter table public.bookings alter column payment_method set default 'cash', alter column payment_method set not null;
alter table public.bookings drop constraint if exists bookings_payment_status_check;
alter table public.bookings add constraint bookings_payment_status_check check(payment_status in ('unpaid','pending','paid','failed','cancelled','refunded','partially_refunded'));
alter table public.bookings add column checkout_order_id uuid unique references public.checkout_orders(id);
alter table public.matches add column checkout_order_id uuid unique references public.checkout_orders(id);
alter table public.matches add column payment_mode text check(payment_mode in ('pay_individually','host_pays_all'));
alter table public.matches add column total_amount_baisa bigint check(total_amount_baisa >= 0);
alter table public.match_players add column payment_order_id uuid references public.checkout_orders(id);
alter table public.match_players add column covered_by_host boolean not null default false;

alter table public.addon_types enable row level security;
alter table public.arena_addons enable row level security;
alter table public.checkout_orders enable row level security;
alter table public.booking_addons enable row level security;
alter table public.payment_refunds enable row level security;
revoke all on public.addon_types,public.arena_addons,public.checkout_orders,public.booking_addons,public.payment_refunds from public,anon,authenticated;
grant select on public.addon_types,public.arena_addons,public.checkout_orders,public.booking_addons,public.payment_refunds to authenticated;
create policy addon_types_read on public.addon_types for select to authenticated using(true);
create policy arena_addons_read on public.arena_addons for select to authenticated using(enabled or public.is_arena_operator(arena_id));
create policy checkout_orders_read on public.checkout_orders for select to authenticated using(user_id=auth.uid() or public.is_arena_operator(arena_id));
create policy booking_addons_read on public.booking_addons for select to authenticated using(exists(select 1 from public.checkout_orders o where o.id=order_id));
create policy payment_refunds_read on public.payment_refunds for select to authenticated using(exists(select 1 from public.checkout_orders o where o.id=order_id));

insert into arena_private.staging_installation(version,source_sha256) values('202610040001','388614020d02bc49bb95eda69b29358bc8ca515e80554abd5b7e9f1d010fa6cf');

-- SOURCE 202610040002_phase2_checkout.sql

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

insert into arena_private.staging_installation(version,source_sha256) values('202610040002','4811df0e9e7658cb254f2950351e150d0d0c9fb6dd57ca401ea6f2a48d21ed0e');

-- SOURCE 202610040003_phase2_payment_boundaries.sql

create function public.payment_claim_session(p_order uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o checkout_orders%rowtype;begin
 select * into strict o from checkout_orders where id=p_order for update;
 if o.payment_method<>'card' or o.fulfillment_status<>'pending' then raise exception 'ORDER_NOT_PAYABLE';end if;
 if o.provider_creation_state='not_started' then
  update checkout_orders set provider_creation_state='creating',provider_attempted_at=now(),updated_at=now() where id=o.id;
  return to_jsonb(o)||jsonb_build_object('create_allowed',true);
 end if;
 return to_jsonb(o)||jsonb_build_object('create_allowed',false);
end $$;

create function public.payment_reconcile(p_order uuid,p_session text,p_reference text,p_currency text,p_amount bigint,p_status text,p_invoice text,p_event_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o checkout_orders%rowtype;err text;begin
 select * into strict o from checkout_orders where id=p_order for update;
 if o.payment_method<>'card' or p_reference<>o.id::text or p_currency<>'OMR' or p_amount<>o.amount_due_baisa or nullif(p_session,'') is null or p_status not in('paid','unpaid','cancelled') or p_status is null then raise exception 'PROVIDER_VERIFICATION_MISMATCH';end if;
 if o.provider_session_id is not null and o.provider_session_id<>p_session then raise exception 'PROVIDER_SESSION_MISMATCH';end if;
 insert into arena_private.payment_events(event_key,order_id,verified_status) values(p_event_key,o.id,p_status) on conflict do nothing;
 update checkout_orders set provider_session_id=p_session,provider_invoice=p_invoice,provider_creation_state='ready',updated_at=now() where id=o.id;
 -- A stale unpaid/cancel event cannot reverse captured funds or refunds.
 if o.payment_status in('paid','refunded','partially_refunded') then
  select * into o from checkout_orders where id=o.id;return to_jsonb(o);
 end if;
 if p_status='paid' then
  update checkout_orders set payment_status='paid' where id=o.id;
  begin
   perform arena_private.fulfill_order(o.id);
  exception when others then
   get stacked diagnostics err=message_text;
   update checkout_orders set fulfillment_status='refund_required',failure_code=left(err,200) where id=o.id;
  end;
 elsif p_status='cancelled' then
  update checkout_orders set payment_status='cancelled',fulfillment_status='cancelled' where id=o.id;
 end if;
 select * into o from checkout_orders where id=o.id;return to_jsonb(o);
end $$;

create function public.request_payment_refund(p_order uuid,p_amount_baisa bigint,p_reason text,p_request_key uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare o checkout_orders%rowtype;r payment_refunds%rowtype;reserved bigint;begin
 if not public.is_platform_admin() then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 select * into strict o from checkout_orders where id=p_order for update;
 select * into r from payment_refunds where request_key=p_request_key;
 if found then
  if (r.order_id,r.amount_baisa,r.reason) is distinct from (p_order,p_amount_baisa,p_reason) then raise exception 'IDEMPOTENCY_PAYLOAD_MISMATCH';end if;
  return r.id;
 end if;
 if o.payment_method<>'card' or o.payment_status not in('paid','partially_refunded') then raise exception 'REFUND_NOT_ALLOWED';end if;
 select coalesce(sum(amount_baisa),0) into reserved from payment_refunds where order_id=o.id and status<>'failed';
 if p_amount_baisa is null or p_amount_baisa<=0 or reserved+p_amount_baisa>o.amount_due_baisa then raise exception 'REFUND_EXCEEDS_PAYMENT';end if;
 insert into payment_refunds(order_id,request_key,original_amount_baisa,amount_baisa,reason,requested_by) values(o.id,p_request_key,o.amount_due_baisa,p_amount_baisa,p_reason,auth.uid()) returning id into r.id;
 return r.id;
end $$;

create function public.payment_confirm_refund(p_refund uuid,p_reference text,p_amount bigint,p_succeeded boolean)
returns void language plpgsql security definer set search_path=public as $$
declare r payment_refunds%rowtype;total bigint;begin
 select * into strict r from payment_refunds where id=p_refund;
 perform 1 from checkout_orders where id=r.order_id for update;
 select * into strict r from payment_refunds where id=p_refund for update;
 if r.status='succeeded' then
  if r.provider_reference is distinct from p_reference or r.amount_baisa<>p_amount then raise exception 'REFUND_VERIFICATION_MISMATCH';end if;return;
 end if;
 if r.amount_baisa<>p_amount or nullif(p_reference,'') is null then raise exception 'REFUND_VERIFICATION_MISMATCH';end if;
 update payment_refunds set status=case when p_succeeded then 'succeeded' else 'failed' end,provider_reference=p_reference,updated_at=now() where id=r.id;
 select coalesce(sum(amount_baisa),0) into total from payment_refunds where order_id=r.order_id and status='succeeded';
 update checkout_orders set refunded_amount_baisa=total,payment_status=case when total=amount_due_baisa then 'refunded' when total>0 then 'partially_refunded' else payment_status end,updated_at=now() where id=r.order_id;
 update bookings b set payment_status=o.payment_status from checkout_orders o where o.id=r.order_id and b.id=o.booking_id;
end $$;

create function public.create_participant_checkout(p_match uuid,p_request_key uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid:=public.require_oman_user();m matches%rowtype;host_order checkout_orders%rowtype;o checkout_orders%rowtype;seat integer;prior jsonb;begin
 if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
 prior:=arena_private.begin_request(p_request_key,'participant',jsonb_build_object('match_id',p_match));
 select * into strict m from matches where id=p_match for update;
 if m.status='cancelled' or m.starts_at<=now() then raise exception 'MATCH_UNAVAILABLE';end if;
 if m.checkout_order_id is null then raise exception 'LEGACY_MATCH_USE_JOIN';end if;
 if not exists(select 1 from profiles where id=u and gender=m.gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
 if m.is_private and m.host_id<>u and not exists(select 1 from match_players where match_id=m.id and user_id=u and status in('invited','joined')) then raise exception 'INVITATION_REQUIRED';end if;
 select * into strict host_order from checkout_orders where id=m.checkout_order_id;
 if host_order.payment_status<>'paid' or host_order.fulfillment_status<>'fulfilled' then raise exception 'HOST_PAYMENT_REQUIRED';end if;
 select * into o from checkout_orders where match_id=m.id and user_id=u and fulfillment_status<>'cancelled';
 if found then return to_jsonb(o);end if;
 if m.payment_mode='host_pays_all' then
  if not exists(select 1 from match_players where match_id=m.id and user_id=u and status='joined') and (select count(*) from match_players where match_id=m.id and status='joined')>=m.max_players then raise exception 'MATCH_FULL';end if;
  insert into match_players(match_id,user_id,status,covered_by_host) values(m.id,u,'joined',true) on conflict on constraint match_players_pkey do update set status='joined',covered_by_host=true;
  return jsonb_build_object('covered_by_host',true,'fulfillment_status','fulfilled','match_id',m.id);
 end if;
 select s into seat from generate_series(1,m.max_players-1) s where not exists(select 1 from checkout_orders x where x.match_id=m.id and x.seat_index=s and x.fulfillment_status<>'cancelled') order by s limit 1;
 if seat is null then raise exception 'MATCH_FULL';end if;
 insert into checkout_orders(user_id,arena_id,request_key,request_payload,purpose,payment_method,payment_status,base_amount_baisa,total_amount_baisa,amount_due_baisa,starts_at,ends_at,payment_mode,seat_index,match_id)
 values(u,m.arena_id,p_request_key,jsonb_build_object('match_id',m.id),'participant','card','pending',host_order.base_amount_baisa,m.total_amount_baisa,arena_private.share_baisa(m.total_amount_baisa,m.max_players,seat),m.starts_at,m.ends_at,m.payment_mode,seat,m.id) returning * into o;
 if o.amount_due_baisa<100 then raise exception 'CARD_MINIMUM_100_BAISA';end if;
 update arena_private.requests set result=jsonb_build_object('id',o.id) where user_id=u and request_key=p_request_key;
 return to_jsonb(o);
end $$;

-- Preserve historical matches, but require a server-verified financial entitlement
-- for all new financial matches, including legacy invite/accept RPCs.
create function public.enforce_match_payment_entitlement()
returns trigger language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;begin
 select * into strict m from matches where id=new.match_id;
 if m.checkout_order_id is null or new.status<>'joined' then return new;end if;
 if m.payment_mode='host_pays_all' and exists(select 1 from checkout_orders where id=m.checkout_order_id and payment_status='paid' and amount_due_baisa=m.total_amount_baisa) then
  new.covered_by_host:=true;return new;
 end if;
 if not exists(select 1 from checkout_orders where id=new.payment_order_id and user_id=new.user_id and payment_status='paid' and (match_id=m.id or id=m.checkout_order_id)) then raise exception 'PARTICIPANT_PAYMENT_REQUIRED';end if;
 new.covered_by_host:=false;return new;
end $$;
create trigger phase2_match_payment before insert or update on public.match_players for each row execute function public.enforce_match_payment_entitlement();

-- Old clients cannot create unpaid public matches or bypass the add-on catalog.
create or replace function public.create_arena_match(p_arena_id uuid,p_name text,p_description text,p_rules text,p_sport text,p_starts_at timestamptz,p_ends_at timestamptz,p_max_players integer,p_is_private boolean,p_show_joined_players boolean,p_payment_method text,p_idempotency_key uuid)
returns table(match_id uuid,court_id uuid,court_number integer) language plpgsql security definer set search_path=public as $$ begin raise exception 'CARD_CHECKOUT_REQUIRED';end $$;
create or replace function public.create_arena_booking_with_coupon(p_arena_id uuid,p_starts_at timestamptz,p_ends_at timestamptz,p_water_cartons integer,p_idempotency_key uuid,p_coupon_id uuid default null)
returns table(booking_id uuid,court_id uuid,court_number integer,total_price numeric,discount_amount numeric)
language plpgsql security definer set search_path=public as $$
declare addons jsonb:='[]';a uuid;o jsonb;b bookings%rowtype;begin
 if p_water_cartons is null or p_water_cartons<0 then raise exception 'INVALID_WATER_QUANTITY';end if;
 if p_water_cartons>0 then
  select id into a from arena_addons where arena_id=p_arena_id and addon_code='water' and enabled;
  if a is null then raise exception 'ADDON_UNAVAILABLE';end if;
  addons:=jsonb_build_array(jsonb_build_object('id',a,'quantity',p_water_cartons));
 end if;
 -- Retry of an existing Phase 1 request must still return its original result.
 select * into b from bookings where user_id=auth.uid() and idempotency_key=p_idempotency_key;
 if found then
  if (b.arena_id,b.starts_at,b.ends_at,b.coupon_id) is distinct from (p_arena_id,p_starts_at,p_ends_at,p_coupon_id) then raise exception 'IDEMPOTENCY_PAYLOAD_MISMATCH';end if;
 else
  o:=public.create_checkout(jsonb_build_object('purpose','booking','payment_method','cash','arena_id',p_arena_id,'starts_at',p_starts_at,'ends_at',p_ends_at,'addons',addons,'coupon_id',p_coupon_id),p_idempotency_key);
  select * into strict b from bookings where id=(o->>'booking_id')::uuid;
 end if;
 return query select b.id,b.court_id,c.court_number,b.total_price,b.discount_amount from arena_courts c where c.id=b.court_id;
end $$;

revoke all on function public.payment_claim_session(uuid),public.payment_reconcile(uuid,text,text,text,bigint,text,text,text),public.payment_confirm_refund(uuid,text,bigint,boolean),public.enforce_match_payment_entitlement(),public.request_payment_refund(uuid,bigint,text,uuid),public.create_participant_checkout(uuid,uuid) from public,anon,authenticated;
grant execute on function public.payment_claim_session(uuid),public.payment_reconcile(uuid,text,text,text,bigint,text,text,text),public.payment_confirm_refund(uuid,text,bigint,boolean) to service_role;
grant execute on function public.request_payment_refund(uuid,bigint,text,uuid),public.create_participant_checkout(uuid,uuid) to authenticated;

insert into arena_private.staging_installation(version,source_sha256) values('202610040003','b4e727c1353c0ac23177bc0eeddb452b413332d2345fa90110d7503a75ef43b7');

-- SOURCE 202610040004_phase2_lifecycle.sql

-- Sessionless requests can be cancelled without touching a payment provider.
-- Once creation has been attempted, only verified provider state may cancel it.
create function public.cancel_unstarted_checkout(p_order uuid)
returns void language plpgsql security definer set search_path=public as $$ begin
 update checkout_orders set fulfillment_status='cancelled',payment_status='cancelled',updated_at=now()
 where id=p_order and user_id=auth.uid() and payment_method='card' and provider_creation_state='not_started' and payment_status='pending';
 if not found then raise exception 'PROVIDER_CANCELLATION_REQUIRED';end if;
end $$;
create function public.flag_cancelled_payment()
returns trigger language plpgsql security definer set search_path=public as $$ begin
 if new.status='cancelled' and old.status<>'cancelled' and new.checkout_order_id is not null then
  update checkout_orders set fulfillment_status=case when payment_status in('paid','partially_refunded') then 'refund_required' else 'cancelled' end,
   failure_code='RESERVATION_CANCELLED',updated_at=now()
  where id=new.checkout_order_id or (tg_table_name='matches' and match_id=new.id and purpose='participant');
 end if;return new;
end $$;
create trigger phase2_booking_cancel after update of status on bookings for each row execute function public.flag_cancelled_payment();
create trigger phase2_match_cancel after update of status on matches for each row execute function public.flag_cancelled_payment();

create or replace function public.respond_match_join_request(p_match_id uuid,p_user_id uuid,p_accept boolean)
returns void language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;begin
 perform public.require_oman_user();
 select * into m from matches where id=p_match_id and status<>'cancelled' and starts_at>now() for update;
 if not found or m.host_id<>auth.uid() then raise exception 'HOST_ONLY';end if;
 if p_accept then
  if not exists(select 1 from profiles where id=p_user_id and gender=m.gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
  if (select count(*) from match_players where match_id=p_match_id and status='joined')>=m.max_players then raise exception 'MATCH_FULL';end if;
 end if;
 update match_players set status=case when not p_accept then 'rejected' when m.checkout_order_id is not null and m.payment_mode='pay_individually' then 'invited' else 'joined' end,joined_at=now()
 where match_id=p_match_id and user_id=p_user_id and status='requested';
 if not found then raise exception 'JOIN_REQUEST_NOT_FOUND';end if;
end $$;
revoke all on function public.cancel_unstarted_checkout(uuid),public.flag_cancelled_payment() from public,anon,authenticated;
grant execute on function public.cancel_unstarted_checkout(uuid) to authenticated;
grant select on public.checkout_orders,public.payment_refunds to service_role;

insert into arena_private.staging_installation(version,source_sha256) values('202610040004','92042e7b316f80d0f0a0aecc47c659a250cd684ceae20ac937f5462ad2b28616');

commit;
select version,source_sha256 from arena_private.staging_installation where version like '20261004%' order by version;
