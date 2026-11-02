-- New policy applies only to checkout orders created after this migration.
-- No historical checkout, booking, payment or refund is recalculated.
begin;

create table arena_private.finance_policy (
  singleton boolean primary key default true check(singleton),
  activated_at timestamptz not null default clock_timestamp(),
  version text not null default '20261024_v1'
);
insert into arena_private.finance_policy(singleton) values(true);
create table arena_private.finance_admins (
  user_id uuid primary key references auth.users(id), active boolean not null default true
);
revoke all on arena_private.finance_policy,arena_private.finance_admins from public,anon,authenticated;
create function public.my_finance_access() returns boolean
language sql stable security definer set search_path=public,pg_temp as $$
 select public.is_platform_admin() and exists(select 1 from arena_private.finance_admins where user_id=auth.uid() and active);
$$;
revoke all on function public.my_finance_access() from public,anon,authenticated;
grant execute on function public.my_finance_access() to authenticated;

create table public.discount_campaigns (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check(code=upper(trim(code)) and code~'^[A-Z0-9_-]{3,32}$'),
  kind text not null check(kind in('fixed','percentage')),
  value integer not null check(value>0),
  starts_at timestamptz not null,ends_at timestamptz not null check(ends_at>starts_at),
  usage_limit integer not null check(usage_limit>0),
  arena_ids uuid[] not null default '{}',
  funding_mode text check(funding_mode in('arena','owner','shared')),
  arena_funding_bps integer,owner_funding_bps integer,
  active boolean not null default false,
  created_by uuid references auth.users(id),created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(kind<>'percentage' or value<=10000),
  check(not active or (funding_mode is not null and arena_funding_bps is not null
    and owner_funding_bps is not null and arena_funding_bps between 0 and 10000
    and owner_funding_bps between 0 and 10000 and arena_funding_bps+owner_funding_bps=10000
    and (funding_mode<>'arena' or arena_funding_bps=10000)
    and (funding_mode<>'owner' or owner_funding_bps=10000)
    and (funding_mode<>'shared' or (arena_funding_bps between 1 and 9999))))
);
create table arena_private.reward_coupon_funding (
  coupon_id uuid primary key references public.reward_coupons(id),
  arena_funding_bps integer not null check(arena_funding_bps between 0 and 10000),
  owner_funding_bps integer not null check(owner_funding_bps between 0 and 10000),
  check(arena_funding_bps+owner_funding_bps=10000)
);
revoke all on arena_private.reward_coupon_funding from public,anon,authenticated;
alter table public.checkout_orders add column promotion_id uuid references public.discount_campaigns(id);

create table public.booking_financial_snapshots (
  id uuid primary key default gen_random_uuid(),
  origin_order_id uuid not null unique references public.checkout_orders(id),
  arena_id uuid not null references public.arenas(id),
  owner_id uuid references auth.users(id),policy_version text not null,
  gross_baisa bigint not null,eligible_baisa bigint not null,water_baisa bigint not null,
  commission_baisa bigint not null,internal_gateway_allocation_baisa bigint not null,
  internal_arena_allocation_baisa bigint not null,
  discount_baisa bigint not null,arena_discount_baisa bigint not null,owner_discount_baisa bigint not null,
  funding_mode text,arena_funding_bps integer,owner_funding_bps integer,
  promotion_code text,promotion_id uuid references public.discount_campaigns(id),
  owner_net_baisa bigint not null,created_at timestamptz not null default clock_timestamp(),
  check(gross_baisa>=0 and eligible_baisa>=0 and water_baisa>=0 and commission_baisa>=0),
  check(commission_baisa=internal_gateway_allocation_baisa+internal_arena_allocation_baisa),
  check(discount_baisa=arena_discount_baisa+owner_discount_baisa),
  check(arena_discount_baisa>=0 and arena_discount_baisa<=internal_arena_allocation_baisa),
  check(owner_discount_baisa>=0 and owner_net_baisa=gross_baisa-commission_baisa-owner_discount_baisa and owner_net_baisa>=0)
);
create table public.booking_financial_lines (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null references public.booking_financial_snapshots(id),
  line_key text not null,line_type text not null check(line_type in('base','addon')),
  addon_code text,name_ar text not null,name_en text not null,
  quantity integer not null check(quantity>0),
  gross_baisa bigint not null check(gross_baisa>=0),commission_baisa bigint not null check(commission_baisa>=0),
  arena_discount_baisa bigint not null check(arena_discount_baisa>=0),
  owner_discount_baisa bigint not null check(owner_discount_baisa>=0),
  paid_baisa bigint not null check(paid_baisa>=0),
  unique(snapshot_id,line_key),
  check(paid_baisa=gross_baisa-arena_discount_baisa-owner_discount_baisa),
  check(addon_code is distinct from 'water' or commission_baisa=0)
);
create function arena_private.immutable_finance_snapshot() returns trigger
language plpgsql set search_path=pg_catalog as $$begin raise exception 'IMMUTABLE_FINANCIAL_SNAPSHOT';end$$;
create trigger immutable_finance_snapshot before update or delete on public.booking_financial_snapshots
for each row execute function arena_private.immutable_finance_snapshot();
create trigger immutable_finance_line before update or delete on public.booking_financial_lines
for each row execute function arena_private.immutable_finance_snapshot();

create function arena_private.discount_distribution(p_gross bigint,p_eligible bigint,p_discount bigint,p_arena_bps integer,p_owner_bps integer)
returns jsonb language plpgsql immutable set search_path=pg_catalog as $$
declare commission bigint:=(p_eligible*800+5000)/10000;
 gateway bigint:=(p_eligible*250+5000)/10000;arena_part bigint;owner_part bigint;
begin
 if p_discount is null or p_discount<0 or p_gross is null or p_gross<0 or p_eligible is null or p_eligible<0 or p_eligible>p_gross then raise exception 'INVALID_DISCOUNT_DISTRIBUTION';end if;
 if p_discount=0 then return jsonb_build_object('arena',0,'owner',0);end if;
 if p_arena_bps is null or p_owner_bps is null or p_arena_bps not between 0 and 10000 or p_owner_bps not between 0 and 10000 or p_arena_bps+p_owner_bps<>10000 then raise exception 'DISCOUNT_FUNDING_REQUIRED';end if;
 arena_part:=(p_discount*p_arena_bps+5000)/10000;owner_part:=p_discount-arena_part;
 if arena_part>commission-gateway then raise exception 'DISCOUNT_EXCEEDS_ARENA_SHARE';end if;
 if owner_part>p_gross-commission then raise exception 'DISCOUNT_EXCEEDS_OWNER_SHARE';end if;
 return jsonb_build_object('arena',arena_part,'owner',owner_part);
end$$;

create function public.admin_save_discount(p_id uuid,p_definition jsonb) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid:=coalesce(p_id,gen_random_uuid());ids uuid[];begin
 if not public.is_platform_admin() then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 select coalesce(array_agg(value::uuid),'{}') into ids from jsonb_array_elements_text(coalesce(p_definition->'arena_ids','[]'));
 if exists(select 1 from unnest(ids) x where not exists(select 1 from arenas where id=x)) then raise exception 'INVALID_ARENA_SCOPE';end if;
 insert into discount_campaigns(id,code,kind,value,starts_at,ends_at,usage_limit,arena_ids,funding_mode,arena_funding_bps,owner_funding_bps,active,created_by)
 values(v_id,upper(trim(p_definition->>'code')),p_definition->>'kind',(p_definition->>'value')::integer,
 (p_definition->>'starts_at')::timestamptz,(p_definition->>'ends_at')::timestamptz,(p_definition->>'usage_limit')::integer,ids,
 p_definition->>'funding_mode',(p_definition->>'arena_funding_bps')::integer,(p_definition->>'owner_funding_bps')::integer,coalesce((p_definition->>'active')::boolean,false),auth.uid())
 on conflict(id) do update set code=excluded.code,kind=excluded.kind,value=excluded.value,starts_at=excluded.starts_at,ends_at=excluded.ends_at,
 usage_limit=excluded.usage_limit,arena_ids=excluded.arena_ids,funding_mode=excluded.funding_mode,
 arena_funding_bps=excluded.arena_funding_bps,owner_funding_bps=excluded.owner_funding_bps,active=excluded.active,updated_at=clock_timestamp();
 return v_id;
end$$;
create function public.admin_set_reward_coupon_funding(p_coupon uuid,p_arena_bps integer,p_owner_bps integer) returns void
language plpgsql security definer set search_path=public,pg_temp as $$begin
 if not public.is_platform_admin() then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 insert into arena_private.reward_coupon_funding values(p_coupon,p_arena_bps,p_owner_bps)
 on conflict(coupon_id) do update set arena_funding_bps=excluded.arena_funding_bps,owner_funding_bps=excluded.owner_funding_bps;
end$$;

create function public.checkout_quote_with_discount(p_arena uuid,p_start timestamptz,p_end timestamptz,p_addons jsonb,p_coupon uuid,p_promo_code text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare q jsonb;c discount_campaigns%rowtype;gross bigint;water bigint;eligible bigint;d bigint;ab integer;ob integer;funding jsonb;begin
 q:=public.checkout_quote(p_arena,p_start,p_end,p_addons,p_coupon);
 gross:=(q->>'total_amount_baisa')::bigint+(q->>'discount_baisa')::bigint;
 select coalesce(sum((x->>'unit_amount_baisa')::bigint*(x->>'quantity')::integer),0) into water from jsonb_array_elements(q->'addons') x where x->>'code'='water';
 eligible:=gross-water;d:=(q->>'discount_baisa')::bigint;
 if nullif(trim(p_promo_code),'') is not null then
  if p_coupon is not null then raise exception 'MULTIPLE_DISCOUNTS_NOT_ALLOWED';end if;
  select * into c from discount_campaigns where code=upper(trim(p_promo_code)) for update;
  if not found or not c.active or clock_timestamp()<c.starts_at or clock_timestamp()>=c.ends_at
    or (cardinality(c.arena_ids)>0 and not(p_arena=any(c.arena_ids))) then raise exception 'PROMOTION_NOT_AVAILABLE';end if;
  if (select count(*) from checkout_orders where promotion_id=c.id and fulfillment_status in('pending','fulfilled','refund_required'))>=c.usage_limit then raise exception 'PROMOTION_USAGE_LIMIT';end if;
  d:=least(gross,case when c.kind='fixed' then c.value::bigint else (gross*c.value+5000)/10000 end);
  ab:=c.arena_funding_bps;ob:=c.owner_funding_bps;
 elsif d>0 then
  select arena_funding_bps,owner_funding_bps into ab,ob from arena_private.reward_coupon_funding where coupon_id=p_coupon for share;
 end if;
 funding:=arena_private.discount_distribution(gross,eligible,d,ab,ob);
 return q||jsonb_build_object('total_amount_baisa',gross-d,'discount_baisa',d,
   'promotion_id',c.id,'promotion_code',c.code);
end$$;

-- Retain the existing checkout/payment/inventory implementation; change only
-- its source of discounted quote. Abort if the reviewed anchor has drifted.
do $$declare src text;anchor text:=$anchor$q:=public.checkout_quote((p_request->>'arena_id')::uuid,(p_request->>'starts_at')::timestamptz,(p_request->>'ends_at')::timestamptz,coalesce(p_request->'addons','[]'),(p_request->>'coupon_id')::uuid);$anchor$;
 replacement text:=$anchor$q:=public.checkout_quote_with_discount((p_request->>'arena_id')::uuid,(p_request->>'starts_at')::timestamptz,(p_request->>'ends_at')::timestamptz,coalesce(p_request->'addons','[]'),(p_request->>'coupon_id')::uuid,p_request->>'promo_code');$anchor$;
begin
 select pg_get_functiondef('public.create_checkout(jsonb,uuid)'::regprocedure) into src;
 if position(anchor in src)=0 or position(anchor in substr(src,position(anchor in src)+length(anchor)))>0 then raise exception 'CHECKOUT_SOURCE_DRIFT_REVIEW_REQUIRED';end if;
 execute replace(src,anchor,replacement);
end$$;

create function arena_private.bind_checkout_promotion() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare c discount_campaigns%rowtype;begin
 -- Never accept a client-supplied financial association.
 new.promotion_id:=null;
 if nullif(trim(new.request_payload->>'promo_code'),'') is not null then
  if new.purpose<>'booking' then raise exception 'PROMO_ORDINARY_BOOKING_ONLY';end if;
  select * into strict c from discount_campaigns where code=upper(trim(new.request_payload->>'promo_code')) for update;
  if not c.active or clock_timestamp()<c.starts_at or clock_timestamp()>=c.ends_at then raise exception 'PROMOTION_NOT_AVAILABLE';end if;
  if (select count(*) from checkout_orders where promotion_id=c.id and fulfillment_status in('pending','fulfilled','refund_required'))>=c.usage_limit then raise exception 'PROMOTION_USAGE_LIMIT';end if;
  new.promotion_id:=c.id;
 end if;
 return new;
end$$;
create trigger bind_checkout_promotion before insert on public.checkout_orders
for each row execute function arena_private.bind_checkout_promotion();

create function arena_private.capture_booking_finance() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare o checkout_orders%rowtype;pol arena_private.finance_policy%rowtype;c discount_campaigns%rowtype;
 gross bigint;water bigint;eligible bigint;commission bigint;gateway bigint;ad bigint;od bigint;ab integer;ob integer;
 owner_user uuid;sid uuid;mode text;funding jsonb;r record;
 elig_cum bigint:=0;prev_com bigint:=0;line_com bigint;
 owner_cum bigint:=0;arena_cum bigint:=0;prev_ad bigint:=0;prev_od bigint:=0;
 line_ad bigint;line_od bigint;
begin
 select * into strict o from checkout_orders where id=new.id;
 select * into strict pol from arena_private.finance_policy where singleton;
 -- This INSERT-only trigger is installed at activation. Existing orders never
 -- fire it; client/backdated timestamps cannot exempt a newly inserted order.
 if o.purpose='participant' then return null;end if;
 if exists(select 1 from booking_financial_snapshots where origin_order_id=o.id) then return null;end if;
 gross:=o.base_amount_baisa+(select coalesce(sum(unit_amount_baisa*quantity),0) from booking_addons where order_id=o.id);
 select coalesce(sum(unit_amount_baisa*quantity),0) into water from booking_addons where order_id=o.id and addon_code='water';
 eligible:=gross-water;commission:=(eligible*800+5000)/10000;gateway:=(eligible*250+5000)/10000;
 if o.promotion_id is not null then
  select * into strict c from discount_campaigns where id=o.promotion_id for share;
  ab:=c.arena_funding_bps;ob:=c.owner_funding_bps;mode:=c.funding_mode;
 elsif o.discount_baisa>0 then
  select arena_funding_bps,owner_funding_bps into ab,ob from arena_private.reward_coupon_funding where coupon_id=o.coupon_id for share;
  mode:=case when ab=10000 then 'arena' when ob=10000 then 'owner' else 'shared' end;
 end if;
 funding:=arena_private.discount_distribution(gross,eligible,o.discount_baisa,ab,ob);ad:=(funding->>'arena')::bigint;od:=(funding->>'owner')::bigint;
 if o.total_amount_baisa<>gross-o.discount_baisa then raise exception 'FINANCIAL_SNAPSHOT_TOTAL_MISMATCH';end if;
 select owner_id into owner_user from arenas where id=o.arena_id;
 insert into booking_financial_snapshots(origin_order_id,arena_id,owner_id,policy_version,gross_baisa,eligible_baisa,water_baisa,
 commission_baisa,internal_gateway_allocation_baisa,internal_arena_allocation_baisa,discount_baisa,arena_discount_baisa,owner_discount_baisa,
 funding_mode,arena_funding_bps,owner_funding_bps,promotion_code,promotion_id,owner_net_baisa)
 values(o.id,o.arena_id,owner_user,pol.version,gross,eligible,water,commission,gateway,commission-gateway,o.discount_baisa,ad,od,
 mode,ab,ob,c.code,c.id,gross-commission-od) returning id into sid;
 for r in select 'base'::text key,'base'::text kind,null::text code,'حجز الملعب'::text ar,'Arena booking'::text en,1 qty,o.base_amount_baisa amount
  union all select id::text,'addon',addon_code,name_ar,name_en,quantity,unit_amount_baisa*quantity from booking_addons where order_id=o.id
  order by kind desc,key loop
  if r.kind='base' or r.code<>'water' then elig_cum:=elig_cum+r.amount;end if;
  line_com:=(elig_cum*800+5000)/10000-prev_com;prev_com:=prev_com+line_com;
  arena_cum:=arena_cum+line_com;owner_cum:=owner_cum+r.amount-line_com;
  line_ad:=case when commission=0 then 0 else (ad*arena_cum+commission/2)/commission end-prev_ad;
  line_od:=case when gross-commission=0 then 0 else (od*owner_cum+(gross-commission)/2)/(gross-commission) end-prev_od;
  prev_ad:=prev_ad+line_ad;prev_od:=prev_od+line_od;
  insert into booking_financial_lines(snapshot_id,line_key,line_type,addon_code,name_ar,name_en,quantity,gross_baisa,commission_baisa,arena_discount_baisa,owner_discount_baisa,paid_baisa)
  values(sid,r.key,r.kind,r.code,r.ar,r.en,r.qty,r.amount,line_com,line_ad,line_od,r.amount-line_ad-line_od);
 end loop;
 return null;
end$$;
-- Deferred: add-on snapshots are inserted after their order by create_checkout.
create constraint trigger capture_booking_finance after insert on public.checkout_orders
deferrable initially deferred for each row execute function arena_private.capture_booking_finance();

alter table public.discount_campaigns enable row level security;
alter table public.booking_financial_snapshots enable row level security;
alter table public.booking_financial_lines enable row level security;
revoke all on public.discount_campaigns,public.booking_financial_snapshots,public.booking_financial_lines from public,anon,authenticated;
grant select on public.discount_campaigns,public.booking_financial_snapshots,public.booking_financial_lines to authenticated;
create policy admin_discount_read on public.discount_campaigns for select to authenticated using(public.is_platform_admin());
create policy admin_finance_snapshot_read on public.booking_financial_snapshots for select to authenticated using(public.is_platform_admin());
create policy admin_finance_lines_read on public.booking_financial_lines for select to authenticated using(public.is_platform_admin());
revoke all on function public.admin_save_discount(uuid,jsonb),public.admin_set_reward_coupon_funding(uuid,integer,integer),
 public.checkout_quote_with_discount(uuid,timestamptz,timestamptz,jsonb,uuid,text) from public,anon,authenticated;
grant execute on function public.admin_save_discount(uuid,jsonb),public.admin_set_reward_coupon_funding(uuid,integer,integer),
 public.checkout_quote_with_discount(uuid,timestamptz,timestamptz,jsonb,uuid,text) to authenticated;
revoke all on all functions in schema arena_private from public,anon,authenticated;
commit;
