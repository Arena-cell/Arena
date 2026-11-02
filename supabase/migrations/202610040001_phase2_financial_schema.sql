-- Additive financial ledger. Existing Phase 1 migrations remain unchanged.
begin;
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
commit;
