-- Arena v2: gender-safe profiles, physical court allocation, atomic bookings,
-- rewards, water add-ons, eligible reviews, and notification foundations.
--
-- This migration is intentionally NON-DESTRUCTIVE. It does not delete the
-- current demo arenas or bookings. Review reset_demo_data_preview.sql before
-- any demo-data cleanup.

create extension if not exists btree_gist;

-- Profiles are the authoritative source for booking audience eligibility.
alter table public.profiles
  add column if not exists first_name text,
  add column if not exists last_name text,
  add column if not exists gender text;

alter table public.profiles drop constraint if exists profiles_gender_check;
alter table public.profiles
  add constraint profiles_gender_check
  check (gender is null or gender in ('men', 'women'));

-- Arenas are never mixed. Existing mixed rows must be classified by an admin
-- before the final NOT NULL constraint can be made strict.
alter table public.arenas
  add column if not exists name_ar text,
  add column if not exists name_en text,
  add column if not exists description_ar text,
  add column if not exists description_en text,
  add column if not exists area_ar text,
  add column if not exists area_en text,
  add column if not exists location_ar text,
  add column if not exists location_en text,
  add column if not exists address_ar text,
  add column if not exists address_en text,
  add column if not exists google_maps_url text,
  add column if not exists is_active boolean not null default true;

alter table public.arenas drop constraint if exists arenas_audience_gender_check;
alter table public.arenas
  add constraint arenas_audience_gender_check
  check (audience_gender in ('men', 'women')) not valid;

-- One public arena card can represent one or many independently bookable
-- physical courts. court_number determines the deterministic allocation order.
create table if not exists public.arena_courts (
  id uuid primary key default gen_random_uuid(),
  arena_id uuid not null references public.arenas(id) on delete cascade,
  court_number integer not null check (court_number > 0),
  label_ar text,
  label_en text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (arena_id, court_number)
);

alter table public.arena_courts enable row level security;
drop policy if exists "arena courts are readable" on public.arena_courts;
create policy "arena courts are readable"
on public.arena_courts for select to anon, authenticated using (true);

alter table public.bookings
  add column if not exists court_id uuid references public.arena_courts(id) on delete restrict,
  add column if not exists water_cartons integer not null default 0 check (water_cartons >= 0),
  add column if not exists water_unit_price numeric(10,3) not null default 0.500 check (water_unit_price >= 0),
  add column if not exists cancelled_by uuid references auth.users(id) on delete set null,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text,
  add column if not exists idempotency_key uuid;

alter table public.bookings
  alter column total_price type numeric(10,3)
  using round(total_price::numeric, 3);

create unique index if not exists bookings_user_idempotency_key_uidx
on public.bookings(user_id, idempotency_key)
where idempotency_key is not null;

create index if not exists bookings_court_interval_idx
on public.bookings(court_id, starts_at, ends_at)
where status <> 'cancelled';

-- Public matches reserve the same physical inventory as private arena bookings.
alter table public.matches
  add column if not exists court_id uuid references public.arena_courts(id) on delete restrict,
  add column if not exists gender text,
  add column if not exists show_joined_players boolean not null default true,
  add column if not exists status text not null default 'upcoming',
  add column if not exists idempotency_key uuid;

create unique index if not exists matches_host_idempotency_key_uidx
on public.matches(host_id, idempotency_key) where idempotency_key is not null;

alter table public.matches drop constraint if exists matches_status_check;
alter table public.matches add constraint matches_status_check
check (status in ('upcoming', 'current', 'previous', 'cancelled'));

alter table public.matches drop constraint if exists matches_gender_check;
alter table public.matches
  add constraint matches_gender_check
  check (gender is null or gender in ('men', 'women'));

-- Physical court overlap is blocked at database level. [) allows a 5-6
-- booking and a 6-7 booking to share the same court without a false conflict.
alter table public.bookings drop constraint if exists bookings_court_no_overlap;
alter table public.bookings
  add constraint bookings_court_no_overlap
  exclude using gist (
    court_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (status <> 'cancelled' and court_id is not null);

alter table public.matches drop constraint if exists matches_court_no_overlap;
alter table public.matches
  add constraint matches_court_no_overlap
  exclude using gist (
    court_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (status <> 'cancelled' and court_id is not null);

create or replace function public.enforce_cross_inventory_overlap()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.court_id is null or coalesce(new.status, 'upcoming') = 'cancelled' then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(new.arena_id::text, 0));
  if tg_table_name = 'bookings' and exists (
    select 1 from public.matches m where m.court_id = new.court_id
      and coalesce(m.status, 'upcoming') <> 'cancelled'
      and tstzrange(m.starts_at, m.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
  ) then
    raise exception 'COURT_TIME_CONFLICT';
  elsif tg_table_name = 'matches' and exists (
    select 1 from public.bookings b where b.court_id = new.court_id
      and coalesce(b.status, 'upcoming') <> 'cancelled'
      and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
  ) then
    raise exception 'COURT_TIME_CONFLICT';
  end if;
  return new;
end;
$$;

drop trigger if exists bookings_enforce_cross_inventory on public.bookings;
create trigger bookings_enforce_cross_inventory
before insert or update of arena_id, court_id, starts_at, ends_at, status on public.bookings
for each row execute function public.enforce_cross_inventory_overlap();
drop trigger if exists matches_enforce_cross_inventory on public.matches;
create trigger matches_enforce_cross_inventory
before insert or update of arena_id, court_id, starts_at, ends_at, status on public.matches
for each row execute function public.enforce_cross_inventory_overlap();

-- Keep the original trigger from treating the parent arena as a single court.
drop trigger if exists bookings_prevent_arena_time_conflict on public.bookings;
drop trigger if exists matches_prevent_arena_time_conflict on public.matches;

-- Creates missing default Court 1 rows without changing existing data.
insert into public.arena_courts (arena_id, court_number, label_ar, label_en)
select a.id, 1, 'الملعب رقم 1', 'Court 1'
from public.arenas a
where not exists (
  select 1 from public.arena_courts c where c.arena_id = a.id
)
on conflict (arena_id, court_number) do nothing;

-- Existing demo bookings are intentionally not backfilled because the owner
-- approved deleting them later. New bookings must always use the atomic RPC.

-- Returns only one-hour boxes that are FULL across all active courts. It never
-- exposes booking owners or private booking details.
create or replace function public.arena_busy_intervals(
  p_arena_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns table (starts_at timestamptz, ends_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  with slots as (
    select value as starts_at, value + interval '1 hour' as ends_at
    from generate_series(
      date_trunc('hour', p_from),
      date_trunc('hour', p_to - interval '1 second'),
      interval '1 hour'
    ) value
  ), active_courts as (
    select c.id
    from public.arena_courts c
    where c.arena_id = p_arena_id and c.is_active
  )
  select s.starts_at, s.ends_at
  from slots s
  where exists (select 1 from active_courts)
    and not exists (
      select 1
      from active_courts c
      where not exists (
        select 1
        from public.bookings b
        where b.court_id = c.id
          and coalesce(b.status, 'upcoming') <> 'cancelled'
          and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(s.starts_at, s.ends_at, '[)')
      )
      and not exists (
        select 1
        from public.matches m
        where m.court_id = c.id
          and coalesce(m.status, 'upcoming') <> 'cancelled'
          and tstzrange(m.starts_at, m.ends_at, '[)') && tstzrange(s.starts_at, s.ends_at, '[)')
      )
    );
$$;

revoke all on function public.arena_busy_intervals(uuid, timestamptz, timestamptz) from public;
grant execute on function public.arena_busy_intervals(uuid, timestamptz, timestamptz) to anon, authenticated;

-- Multi-hour searches must find one physical court free for the complete
-- interval; checking the capacity of each hour separately is not sufficient.
create or replace function public.arena_has_available_court(
  p_arena_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_ends_at > p_starts_at and exists (
    select 1 from public.arena_courts c
    where c.arena_id = p_arena_id and c.is_active
      and not exists (
        select 1 from public.bookings b
        where b.court_id = c.id
          and coalesce(b.status, 'upcoming') <> 'cancelled'
          and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)')
      )
      and not exists (
        select 1 from public.matches m
        where m.court_id = c.id
          and coalesce(m.status, 'upcoming') <> 'cancelled'
          and tstzrange(m.starts_at, m.ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)')
      )
  );
$$;

revoke all on function public.arena_has_available_court(uuid, timestamptz, timestamptz) from public;
grant execute on function public.arena_has_available_court(uuid, timestamptz, timestamptz) to authenticated;

-- Atomic allocation: lock the arena, verify profile gender, choose the lowest
-- court available for the ENTIRE requested range, calculate trusted pricing,
-- and insert once. No client-supplied price is trusted.
create or replace function public.create_arena_booking(
  p_arena_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_water_cartons integer default 0,
  p_idempotency_key uuid default gen_random_uuid()
)
returns table (booking_id uuid, court_id uuid, court_number integer, total_price numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_user_gender text;
  v_arena_gender text;
  v_hourly_price numeric(10,3);
  v_court public.arena_courts%rowtype;
  v_booking_id uuid;
  v_hours numeric;
  v_total numeric(10,3);
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_ends_at <= p_starts_at then raise exception 'INVALID_TIME_RANGE'; end if;
  if p_starts_at <= now() then raise exception 'PAST_BOOKING_NOT_ALLOWED'; end if;
  if extract(epoch from (p_ends_at - p_starts_at)) % 3600 <> 0 then
    raise exception 'WHOLE_HOURS_REQUIRED';
  end if;
  if p_water_cartons < 0 then raise exception 'INVALID_WATER_QUANTITY'; end if;

  -- One transaction-scoped lock serializes allocation for this parent arena.
  perform pg_advisory_xact_lock(hashtextextended(p_arena_id::text, 0));

  select p.gender into v_user_gender from public.profiles p where p.id = v_user_id;
  select a.audience_gender, a.price_per_hour
    into v_arena_gender, v_hourly_price
  from public.arenas a
  where a.id = p_arena_id and coalesce(a.is_active, true)
  for share;

  if v_arena_gender is null then raise exception 'ARENA_NOT_FOUND'; end if;
  if v_user_gender is null then raise exception 'PROFILE_GENDER_REQUIRED'; end if;
  if v_arena_gender <> v_user_gender then raise exception 'GENDER_NOT_ALLOWED'; end if;

  select c.* into v_court
  from public.arena_courts c
  where c.arena_id = p_arena_id
    and c.is_active
    and not exists (
      select 1 from public.bookings b
      where b.court_id = c.id
        and coalesce(b.status, 'upcoming') <> 'cancelled'
        and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)')
    )
    and not exists (
      select 1 from public.matches m
      where m.court_id = c.id
        and coalesce(m.status, 'upcoming') <> 'cancelled'
        and tstzrange(m.starts_at, m.ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)')
    )
  order by c.court_number
  limit 1
  for update skip locked;

  if v_court.id is null then raise exception 'TIME_NO_LONGER_AVAILABLE'; end if;

  v_hours := extract(epoch from (p_ends_at - p_starts_at)) / 3600;
  v_total := round((v_hourly_price * v_hours + p_water_cartons * 0.500)::numeric, 3);

  insert into public.bookings (
    user_id, arena_id, court_id, starts_at, ends_at, total_price, status,
    water_cartons, water_unit_price, idempotency_key
  ) values (
    v_user_id, p_arena_id, v_court.id, p_starts_at, p_ends_at, v_total,
    'upcoming', p_water_cartons, 0.500, p_idempotency_key
  )
  on conflict (user_id, idempotency_key) where idempotency_key is not null
  do update set idempotency_key = excluded.idempotency_key
  returning id into v_booking_id;

  return query select v_booking_id, v_court.id, v_court.court_number, v_total;
end;
$$;

revoke all on function public.create_arena_booking(uuid, timestamptz, timestamptz, integer, uuid) from public;
grant execute on function public.create_arena_booking(uuid, timestamptz, timestamptz, integer, uuid) to authenticated;

-- Public and private matches allocate the same inventory atomically and derive
-- gender from the creator profile. The host is added in the same transaction.
create or replace function public.create_arena_match(
  p_arena_id uuid,
  p_name text,
  p_description text,
  p_rules text,
  p_sport text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_max_players integer,
  p_is_private boolean,
  p_show_joined_players boolean,
  p_payment_method text,
  p_idempotency_key uuid
)
returns table (match_id uuid, court_id uuid, court_number integer)
language plpgsql security definer set search_path = public as $$
declare
  v_user_id uuid := auth.uid();
  v_gender text;
  v_arena_gender text;
  v_hourly_price numeric;
  v_court public.arena_courts%rowtype;
  v_match_id uuid;
  v_existing public.matches%rowtype;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_ends_at <= p_starts_at or p_starts_at <= now() then raise exception 'INVALID_TIME_RANGE'; end if;
  if p_max_players < 2 then raise exception 'INVALID_PLAYER_CAPACITY'; end if;
  if nullif(trim(p_name), '') is null then raise exception 'MATCH_NAME_REQUIRED'; end if;
  if p_payment_method not in ('cash', 'card') then raise exception 'INVALID_PAYMENT_METHOD'; end if;

  select * into v_existing from public.matches
  where host_id = v_user_id and idempotency_key = p_idempotency_key;
  if v_existing.id is not null then
    return query select v_existing.id, v_existing.court_id, c.court_number
    from public.arena_courts c where c.id = v_existing.court_id;
    return;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_arena_id::text, 0));
  select gender into v_gender from public.profiles where id = v_user_id;
  select audience_gender, price_per_hour into v_arena_gender, v_hourly_price
  from public.arenas where id = p_arena_id and coalesce(is_active, true) for share;
  if v_gender is null then raise exception 'PROFILE_GENDER_REQUIRED'; end if;
  if v_arena_gender is null or v_gender <> v_arena_gender then raise exception 'GENDER_NOT_ALLOWED'; end if;

  select c.* into v_court from public.arena_courts c
  where c.arena_id = p_arena_id and c.is_active
    and not exists (
      select 1 from public.bookings b where b.court_id = c.id
        and coalesce(b.status, 'upcoming') <> 'cancelled'
        and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)')
    )
    and not exists (
      select 1 from public.matches m where m.court_id = c.id
        and coalesce(m.status, 'upcoming') <> 'cancelled'
        and tstzrange(m.starts_at, m.ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)')
    )
  order by c.court_number limit 1 for update skip locked;
  if v_court.id is null then raise exception 'TIME_NO_LONGER_AVAILABLE'; end if;

  insert into public.matches(
    arena_id, court_id, host_id, name, description, rules, sport, starts_at,
    ends_at, max_players, price_per_player, gender, payment_method,
    show_joined_players, is_private, status, idempotency_key
  ) values (
    p_arena_id, v_court.id, v_user_id, trim(p_name), nullif(trim(p_description), ''),
    nullif(trim(p_rules), ''), p_sport, p_starts_at, p_ends_at, p_max_players,
    round((v_hourly_price * extract(epoch from (p_ends_at-p_starts_at)) / 3600 / p_max_players)::numeric, 3),
    v_gender, p_payment_method, p_show_joined_players, p_is_private, 'upcoming', p_idempotency_key
  ) returning id into v_match_id;

  insert into public.match_players(match_id, user_id, status)
  values (v_match_id, v_user_id, 'joined') on conflict do nothing;
  return query select v_match_id, v_court.id, v_court.court_number;
end;
$$;

revoke all on function public.create_arena_match(
  uuid,text,text,text,text,timestamptz,timestamptz,integer,boolean,boolean,text,uuid
) from public;
grant execute on function public.create_arena_match(
  uuid,text,text,text,text,timestamptz,timestamptz,integer,boolean,boolean,text,uuid
) to authenticated;

-- Booking owners cannot cancel their own bookings. Admins may cancel any;
-- stadium owners may cancel only bookings for arenas they own.
create or replace function public.cancel_arena_booking(
  p_booking_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_owner_id uuid;
begin
  select p.role into v_role from public.profiles p where p.id = auth.uid();
  select a.owner_id into v_owner_id
  from public.bookings b join public.arenas a on a.id = b.arena_id
  where b.id = p_booking_id for update;

  if v_role <> 'admin' and not (v_role = 'stadium_owner' and v_owner_id = auth.uid()) then
    raise exception 'CANCELLATION_NOT_ALLOWED';
  end if;

  update public.bookings
  set status = 'cancelled', cancelled_by = auth.uid(), cancelled_at = now(),
      cancellation_reason = nullif(trim(p_reason), '')
  where id = p_booking_id and status <> 'cancelled';
end;
$$;

revoke all on function public.cancel_arena_booking(uuid, text) from public;
grant execute on function public.cancel_arena_booking(uuid, text) to authenticated;

-- Rewards are ledger-based so every point can be audited.
create table if not exists public.point_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  booking_id uuid references public.bookings(id) on delete set null,
  match_id uuid references public.matches(id) on delete set null,
  points integer not null,
  reason text not null,
  created_at timestamptz not null default now()
);

create unique index if not exists point_transactions_completed_booking_uidx
on public.point_transactions(booking_id)
where booking_id is not null and reason = 'completed_booking';

create unique index if not exists point_transactions_completed_match_uidx
on public.point_transactions(match_id)
where match_id is not null and reason = 'completed_match';

create table if not exists public.reward_coupons (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  value_omr numeric(10,3) not null default 1.000 check (value_omr = 1.000),
  status text not null default 'available' check (status in ('available', 'used', 'expired')),
  used_booking_id uuid references public.bookings(id) on delete set null,
  created_at timestamptz not null default now(),
  used_at timestamptz
);

alter table public.bookings
  add column if not exists coupon_id uuid references public.reward_coupons(id) on delete set null,
  add column if not exists discount_amount numeric(10,3) not null default 0.000
    check (discount_amount >= 0);
create unique index if not exists bookings_coupon_once_uidx
on public.bookings(coupon_id) where coupon_id is not null;

alter table public.point_transactions enable row level security;
alter table public.reward_coupons enable row level security;
drop policy if exists "users read own point ledger" on public.point_transactions;
create policy "users read own point ledger" on public.point_transactions
for select to authenticated using (user_id = auth.uid());
drop policy if exists "users read own coupons" on public.reward_coupons;
create policy "users read own coupons" on public.reward_coupons
for select to authenticated using (user_id = auth.uid());

-- Coupon use and booking creation remain one database transaction. The whole
-- coupon is consumed even when the payable amount is below OMR 1; no balance
-- is carried forward.
create or replace function public.create_arena_booking_with_coupon(
  p_arena_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_water_cartons integer,
  p_idempotency_key uuid,
  p_coupon_id uuid default null
)
returns table (
  booking_id uuid,
  court_id uuid,
  court_number integer,
  total_price numeric,
  discount_amount numeric
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking record;
  v_coupon public.reward_coupons%rowtype;
  v_existing public.bookings%rowtype;
  v_discount numeric(10,3) := 0.000;
  v_payable numeric(10,3);
begin
  select * into v_existing from public.bookings
  where user_id = auth.uid() and idempotency_key = p_idempotency_key;
  if v_existing.id is not null then
    return query
    select v_existing.id, v_existing.court_id, c.court_number,
           v_existing.total_price, v_existing.discount_amount
    from public.arena_courts c where c.id = v_existing.court_id;
    return;
  end if;

  if p_coupon_id is not null then
    select * into v_coupon from public.reward_coupons
    where id = p_coupon_id and user_id = auth.uid() and status = 'available'
    for update;
    if v_coupon.id is null then raise exception 'COUPON_NOT_AVAILABLE'; end if;
  end if;

  select * into v_booking from public.create_arena_booking(
    p_arena_id, p_starts_at, p_ends_at, p_water_cartons, p_idempotency_key
  );
  v_payable := v_booking.total_price;

  if v_coupon.id is not null then
    v_discount := least(v_payable, v_coupon.value_omr);
    v_payable := greatest(v_payable - v_coupon.value_omr, 0.000);
    update public.reward_coupons
    set status = 'used', used_booking_id = v_booking.booking_id, used_at = now()
    where id = v_coupon.id;
    update public.bookings
    set coupon_id = v_coupon.id,
        discount_amount = v_discount,
        total_price = v_payable
    where id = v_booking.booking_id;
  end if;

  return query select v_booking.booking_id, v_booking.court_id,
    v_booking.court_number, v_payable, v_discount;
end;
$$;

revoke all on function public.create_arena_booking_with_coupon(
  uuid, timestamptz, timestamptz, integer, uuid, uuid
) from public;
grant execute on function public.create_arena_booking_with_coupon(
  uuid, timestamptz, timestamptz, integer, uuid, uuid
) to authenticated;

create or replace function public.award_completed_booking_points()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_balance integer; v_coupon_id uuid;
begin
  if new.status = 'previous' and old.status is distinct from 'previous' then
    insert into public.point_transactions(user_id, booking_id, points, reason)
    values (new.user_id, new.id, 10, 'completed_booking')
    on conflict (booking_id) where booking_id is not null and reason = 'completed_booking'
    do nothing;

    select coalesce(sum(points), 0) into v_balance
    from public.point_transactions where user_id = new.user_id;
    while v_balance >= 100 loop
      insert into public.reward_coupons(user_id) values (new.user_id)
      returning id into v_coupon_id;
      insert into public.point_transactions(user_id, booking_id, points, reason)
      values (new.user_id, new.id, -100, 'coupon_created:' || v_coupon_id::text);
      v_balance := v_balance - 100;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists bookings_award_completed_points on public.bookings;
create trigger bookings_award_completed_points
after update of status on public.bookings
for each row execute function public.award_completed_booking_points();

create or replace function public.award_completed_match_points()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_balance integer; v_coupon_id uuid;
begin
  if new.status = 'previous' and old.status is distinct from 'previous' then
    insert into public.point_transactions(user_id, match_id, points, reason)
    values (new.host_id, new.id, 10, 'completed_match')
    on conflict (match_id) where match_id is not null and reason = 'completed_match'
    do nothing;
    select coalesce(sum(points), 0) into v_balance
    from public.point_transactions where user_id = new.host_id;
    while v_balance >= 100 loop
      insert into public.reward_coupons(user_id) values (new.host_id)
      returning id into v_coupon_id;
      insert into public.point_transactions(user_id, match_id, points, reason)
      values (new.host_id, new.id, -100, 'coupon_created:' || v_coupon_id::text);
      v_balance := v_balance - 100;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists matches_award_completed_points on public.matches;
create trigger matches_award_completed_points
after update of status on public.matches
for each row execute function public.award_completed_match_points();

create or replace function public.finalize_my_completed_events()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  update public.bookings set status = 'previous'
  where user_id = auth.uid() and status in ('upcoming', 'current') and ends_at <= now();
  update public.matches set status = 'previous'
  where host_id = auth.uid() and status in ('upcoming', 'current') and ends_at <= now();
end;
$$;
revoke all on function public.finalize_my_completed_events() from public;
grant execute on function public.finalize_my_completed_events() to authenticated;

-- Replaces the legacy join function and blocks cross-gender participation.
create or replace function public.join_match(match_id uuid, target_user_id uuid default auth.uid())
returns void language plpgsql security definer set search_path = public as $$
declare capacity integer; joined_count integer; host uuid; match_gender text; player_gender text;
begin
  select max_players, host_id, gender into capacity, host, match_gender
  from public.matches where id = match_id and status <> 'cancelled' for update;
  if capacity is null then raise exception 'MATCH_NOT_FOUND'; end if;
  if target_user_id <> auth.uid() and host <> auth.uid() then raise exception 'HOST_ONLY_INVITE'; end if;
  select gender into player_gender from public.profiles where id = target_user_id;
  if player_gender is null then raise exception 'PROFILE_GENDER_REQUIRED'; end if;
  if match_gender is null or player_gender <> match_gender then raise exception 'GENDER_NOT_ALLOWED'; end if;
  select count(*) into joined_count from public.match_players
  where match_players.match_id = join_match.match_id and status = 'joined';
  if joined_count >= capacity then raise exception 'MATCH_FULL'; end if;
  insert into public.match_players(match_id, user_id, status)
  values (match_id, target_user_id, case when target_user_id = auth.uid() then 'joined' else 'invited' end)
  on conflict (match_id, user_id) do update set status = excluded.status;
end;
$$;

-- Reviews are tied to one completed booking and cannot expose profile links.
alter table public.reviews add column if not exists booking_id uuid references public.bookings(id) on delete restrict;
alter table public.reviews drop constraint if exists reviews_arena_id_user_id_key;
alter table public.reviews alter column comment drop not null;
alter table public.reviews drop constraint if exists reviews_comment_check;
alter table public.reviews add constraint reviews_comment_check
check (comment is null or char_length(comment) between 1 and 1000);
create unique index if not exists reviews_booking_id_uidx
on public.reviews(booking_id) where booking_id is not null;

create or replace function public.create_booking_review(
  p_booking_id uuid,
  p_rating smallint,
  p_comment text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_arena_id uuid;
  v_review_id uuid;
begin
  if p_rating < 1 or p_rating > 5 then raise exception 'INVALID_RATING'; end if;
  update public.bookings set status = 'previous'
  where id = p_booking_id and user_id = auth.uid()
    and status in ('upcoming', 'current') and ends_at <= now();
  select b.arena_id into v_arena_id
  from public.bookings b
  where b.id = p_booking_id and b.user_id = auth.uid()
    and b.status = 'previous' and b.ends_at <= now();
  if v_arena_id is null then raise exception 'COMPLETED_BOOKING_REQUIRED'; end if;

  insert into public.reviews(arena_id, user_id, booking_id, rating, comment)
  values (v_arena_id, auth.uid(), p_booking_id, p_rating, nullif(trim(p_comment), ''))
  returning id into v_review_id;
  return v_review_id;
end;
$$;

revoke all on function public.create_booking_review(uuid, smallint, text) from public;
grant execute on function public.create_booking_review(uuid, smallint, text) to authenticated;

-- Device tokens and richer notification types. Actual FCM/APNs delivery stays
-- server-side and requires external provider configuration.
create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios', 'web')),
  locale text not null default 'en' check (locale in ('ar', 'en')),
  updated_at timestamptz not null default now()
);

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (
  type in (
    'match_invitation', 'booking_confirmation', 'booking_cancellation',
    'booking_status', 'booking_reminder', 'player_joined', 'players_complete',
    'join_request', 'join_accepted', 'join_rejected', 'message', 'points',
    'coupon_created', 'coupon_used', 'stadium_update'
  )
);
alter table public.notifications
  add column if not exists event_key text,
  add column if not exists title_ar text,
  add column if not exists title_en text,
  add column if not exists body_ar text,
  add column if not exists body_en text;
create unique index if not exists notifications_user_event_uidx
on public.notifications(user_id, event_key) where event_key is not null;

create or replace function public.notify_booking_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_court_number integer;
begin
  select court_number into v_court_number from public.arena_courts where id = new.court_id;
  if tg_op = 'INSERT' then
    insert into public.notifications(
      user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
    ) values (
      new.user_id, 'booking_confirmation', 'Booking confirmed', 'Your Arena booking is confirmed.',
      'تم تأكيد الحجز', 'Booking confirmed',
      'تم تأكيد حجزك في الملعب رقم ' || coalesce(v_court_number::text, '1') || '.',
      'Your booking is confirmed on Court ' || coalesce(v_court_number::text, '1') || '.',
      jsonb_build_object('booking_id', new.id, 'arena_id', new.arena_id, 'court_number', v_court_number),
      'booking-confirmed:' || new.id::text
    ) on conflict (user_id, event_key) where event_key is not null do nothing;
  elsif new.status is distinct from old.status then
    insert into public.notifications(
      user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
    ) values (
      new.user_id,
      case when new.status = 'cancelled' then 'booking_cancellation' else 'booking_status' end,
      case when new.status = 'cancelled' then 'Booking cancelled' else 'Booking status updated' end,
      case when new.status = 'cancelled' then 'Your Arena booking was cancelled.' else 'Your Arena booking status changed.' end,
      case when new.status = 'cancelled' then 'تم إلغاء الحجز' else 'تم تحديث حالة الحجز' end,
      case when new.status = 'cancelled' then 'Booking cancelled' else 'Booking status updated' end,
      case when new.status = 'cancelled' then 'تم إلغاء حجزك.' else 'تغيرت حالة حجزك.' end,
      case when new.status = 'cancelled' then 'Your Arena booking was cancelled.' else 'Your Arena booking status changed.' end,
      jsonb_build_object('booking_id', new.id, 'arena_id', new.arena_id, 'status', new.status),
      'booking-status:' || new.id::text || ':' || new.status
    ) on conflict (user_id, event_key) where event_key is not null do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists bookings_create_notification on public.bookings;
create trigger bookings_create_notification
after insert or update of status on public.bookings
for each row execute function public.notify_booking_event();

create or replace function public.notify_reward_event()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications(
    user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
  ) values (
    new.user_id, 'points', 'Points updated', new.points::text || ' points',
    'تم تحديث النقاط', 'Points updated',
    'تم تحديث رصيدك بمقدار ' || new.points::text || ' نقطة.',
    'Your balance changed by ' || new.points::text || ' points.',
    jsonb_build_object('points', new.points, 'transaction_id', new.id),
    'points:' || new.id::text
  ) on conflict (user_id, event_key) where event_key is not null do nothing;
  return new;
end;
$$;

drop trigger if exists point_transactions_create_notification on public.point_transactions;
create trigger point_transactions_create_notification
after insert on public.point_transactions
for each row execute function public.notify_reward_event();

create or replace function public.notify_coupon_event()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    null;
  elsif new.status is not distinct from old.status then
    return new;
  end if;
    insert into public.notifications(
      user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
    ) values (
      new.user_id,
      case when new.status = 'used' then 'coupon_used' else 'coupon_created' end,
      case when new.status = 'used' then 'Coupon used' else 'New coupon' end,
      'OMR 1 coupon',
      case when new.status = 'used' then 'تم استخدام الكوبون' else 'كوبون جديد' end,
      case when new.status = 'used' then 'Coupon used' else 'New coupon' end,
      'كوبون بقيمة 1 ر.ع', 'OMR 1 coupon',
      jsonb_build_object('coupon_id', new.id, 'booking_id', new.used_booking_id),
      'coupon:' || new.id::text || ':' || new.status
    ) on conflict (user_id, event_key) where event_key is not null do nothing;
  return new;
end;
$$;

drop trigger if exists reward_coupons_create_notification on public.reward_coupons;
create trigger reward_coupons_create_notification
after insert or update of status on public.reward_coupons
for each row execute function public.notify_coupon_event();

create or replace function public.notify_new_direct_message()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications(
    user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
  ) values (
    new.receiver_id, 'message', 'New message', coalesce(new.content, 'Image'),
    'رسالة جديدة', 'New message', coalesce(new.content, 'صورة'), coalesce(new.content, 'Image'),
    jsonb_build_object('conversation_user_id', new.sender_id), 'message:' || new.id::text
  ) on conflict (user_id, event_key) where event_key is not null do nothing;
  return new;
end;
$$;

drop trigger if exists direct_messages_create_notification on public.direct_messages;
create trigger direct_messages_create_notification
after insert on public.direct_messages
for each row execute function public.notify_new_direct_message();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'bookings'
  ) then
    alter publication supabase_realtime add table public.bookings;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'matches'
  ) then
    alter publication supabase_realtime add table public.matches;
  end if;
end;
$$;

alter table public.device_tokens enable row level security;
drop policy if exists "users manage own device tokens" on public.device_tokens;
create policy "users manage own device tokens" on public.device_tokens
for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Group messaging lives beside the existing direct_messages table so the
-- current private-chat history remains intact.
create table if not exists public.chat_groups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80),
  image_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.chat_group_members (
  group_id uuid not null references public.chat_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.chat_groups(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  content text,
  image_url text,
  created_at timestamptz not null default now(),
  check (content is not null or image_url is not null)
);

create or replace function public.is_chat_group_member(p_group_id uuid, p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.chat_group_members m
    where m.group_id = p_group_id and m.user_id = p_user_id
  );
$$;

create or replace function public.create_group_chat(p_name text, p_member_ids uuid[])
returns uuid language plpgsql security definer set search_path = public as $$
declare v_group_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if char_length(trim(p_name)) not between 1 and 80 then raise exception 'INVALID_GROUP_NAME'; end if;
  if coalesce(array_length(p_member_ids, 1), 0) < 1 then raise exception 'GROUP_MEMBER_REQUIRED'; end if;
  insert into public.chat_groups(owner_id, name) values (auth.uid(), trim(p_name)) returning id into v_group_id;
  insert into public.chat_group_members(group_id, user_id, role) values (v_group_id, auth.uid(), 'owner');
  insert into public.chat_group_members(group_id, user_id, role)
  select v_group_id, member_id, 'member'
  from unnest(p_member_ids) member_id
  where member_id <> auth.uid()
  on conflict do nothing;
  return v_group_id;
end;
$$;

revoke all on function public.create_group_chat(text, uuid[]) from public;
grant execute on function public.create_group_chat(text, uuid[]) to authenticated;

alter table public.chat_groups enable row level security;
alter table public.chat_group_members enable row level security;
alter table public.group_messages enable row level security;
drop policy if exists "members read groups" on public.chat_groups;
create policy "members read groups" on public.chat_groups for select to authenticated
using (public.is_chat_group_member(id));
drop policy if exists "members read memberships" on public.chat_group_members;
create policy "members read memberships" on public.chat_group_members for select to authenticated
using (public.is_chat_group_member(group_id));
drop policy if exists "members read group messages" on public.group_messages;
create policy "members read group messages" on public.group_messages for select to authenticated
using (public.is_chat_group_member(group_id));
drop policy if exists "members send group messages" on public.group_messages;
create policy "members send group messages" on public.group_messages for insert to authenticated
with check (sender_id = auth.uid() and public.is_chat_group_member(group_id));

create index if not exists group_messages_group_created_idx
on public.group_messages(group_id, created_at);

create or replace function public.notify_new_group_message()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications(
    user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
  )
  select m.user_id, 'message', 'New group message', coalesce(new.content, 'Image'),
    'رسالة مجموعة جديدة', 'New group message', coalesce(new.content, 'صورة'),
    coalesce(new.content, 'Image'), jsonb_build_object('group_id', new.group_id),
    'group-message:' || new.id::text
  from public.chat_group_members m
  where m.group_id = new.group_id and m.user_id <> new.sender_id
  on conflict (user_id, event_key) where event_key is not null do nothing;
  return new;
end;
$$;

drop trigger if exists group_messages_create_notification on public.group_messages;
create trigger group_messages_create_notification
after insert on public.group_messages
for each row execute function public.notify_new_group_message();

-- Add first/last name and gender to profiles created by the existing email flow.
create or replace function public.create_profile_for_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (
    id, username, display_name, first_name, last_name, gender
  ) values (
    new.id,
    new.raw_user_meta_data ->> 'username',
    nullif(trim(concat_ws(' ', new.raw_user_meta_data ->> 'first_name', new.raw_user_meta_data ->> 'last_name')), ''),
    nullif(trim(new.raw_user_meta_data ->> 'first_name'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'last_name'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'gender'), '')
  ) on conflict (id) do update set
    first_name = coalesce(profiles.first_name, excluded.first_name),
    last_name = coalesce(profiles.last_name, excluded.last_name),
    gender = coalesce(profiles.gender, excluded.gender);
  return new;
end;
$$;
