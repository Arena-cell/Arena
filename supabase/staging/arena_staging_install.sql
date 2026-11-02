-- REVIEW BEFORE EXECUTION. Target: arena-staging / gtcrijikfaglqcwqozel ONLY.
-- Do not run against Production mbgqnlbuslrgamkzdqpd.
-- Baseline plus existing Phase 1 migrations in order, one atomic transaction.
-- No mock auth/storage schemas, no users, no copied Production data.
begin;
set local statement_timeout='120s';
do $$ begin
 if exists(select 1 from information_schema.tables where table_schema='public' and table_type='BASE TABLE')
    or exists(select 1 from auth.users) then
   raise exception 'STAGING_INSTALL_REQUIRES_EMPTY_PROJECT';
 end if;
end $$;
create extension if not exists pgcrypto with schema extensions;
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  display_name text,
  avatar_url text,
  bio text check (char_length(bio) <= 300),
  city text,
  favorite_sports text[] not null default '{}',
  latitude double precision,
  longitude double precision,
  onboarding_complete boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_format check (username is null or username ~ '^[a-z][a-z0-9_]{3,}$')
);
alter table profiles add column role text not null default 'player';

-- BASELINE SOURCE: supabase/production_schema.sql
-- Production data model for PlayOn. Run once in Supabase SQL Editor.
create table if not exists public.arenas (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete set null,
  name text not null,
  description text,
  location text not null,
  latitude double precision,
  longitude double precision,
  image_urls text[] not null default '{}',
  sports text[] not null default '{}',
  audience_gender text not null default 'men' check (audience_gender in ('men','women')),
  price_per_hour numeric(10,2) not null check (price_per_hour >= 0),
  rating numeric(2,1) check (rating between 0 and 5),
  opening_time time,
  closing_time time,
  created_at timestamptz not null default now()
);

create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  arena_id uuid not null references public.arenas(id) on delete restrict,
  host_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text,
  sport text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null check (ends_at > starts_at),
  max_players integer not null check (max_players > 1),
  price_per_player numeric(10,2) not null check (price_per_player >= 0),
  rules text,
  is_private boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.match_players (
  match_id uuid not null references public.matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'joined' check (status in ('invited','joined')),
  joined_at timestamptz not null default now(),
  primary key (match_id, user_id)
);

create table if not exists public.favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  arena_id uuid not null references public.arenas(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, arena_id)
);

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  arena_id uuid not null references public.arenas(id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null check (ends_at > starts_at),
  total_price numeric(10,2) not null check (total_price >= 0),
  created_at timestamptz not null default now()
);

create index if not exists matches_starts_at_idx on public.matches(starts_at);
create index if not exists bookings_user_id_idx on public.bookings(user_id);

-- Prices in this product are displayed and charged to two decimal places.
alter table public.arenas
  alter column price_per_hour type numeric(10,2)
  using round(price_per_hour::numeric, 2);
alter table public.matches
  alter column price_per_player type numeric(10,2)
  using round(price_per_player::numeric, 2);
alter table public.bookings
  alter column total_price type numeric(10,2)
  using round(total_price::numeric, 2);

alter table public.arenas enable row level security;
alter table public.matches enable row level security;
alter table public.match_players enable row level security;
alter table public.favorites enable row level security;
alter table public.bookings enable row level security;

create policy "arenas are readable" on public.arenas for select to authenticated using (true);
drop policy if exists "owners create stadiums" on public.arenas;
drop policy if exists "owners update stadiums" on public.arenas;
drop policy if exists "verified owners create stadiums" on public.arenas;
drop policy if exists "verified owners update stadiums" on public.arenas;
create policy "verified owners create stadiums" on public.arenas for insert to authenticated with check (
  owner_id = auth.uid() and exists (select 1 from public.profiles where id = auth.uid() and role in ('stadium_owner', 'admin'))
);
create policy "verified owners update stadiums" on public.arenas for update to authenticated using (
  owner_id = auth.uid() and exists (select 1 from public.profiles where id = auth.uid() and role in ('stadium_owner', 'admin'))
) with check (owner_id = auth.uid());
create policy "matches are readable" on public.matches for select to authenticated using (true);
create policy "match players are readable" on public.match_players for select to authenticated using (true);
create policy "host creates matches" on public.matches for insert to authenticated with check (host_id = auth.uid());
create policy "players manage own membership" on public.match_players for insert to authenticated with check (user_id = auth.uid());
create policy "players remove own membership" on public.match_players for delete to authenticated using (user_id = auth.uid());
create policy "users manage own favorites" on public.favorites for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "users read own bookings" on public.bookings for select to authenticated using (user_id = auth.uid());
create policy "users create own bookings" on public.bookings for insert to authenticated with check (user_id = auth.uid());

-- Enforces capacity and lets a host invite an existing profile.
create or replace function public.join_match(match_id uuid, target_user_id uuid default auth.uid())
returns void language plpgsql security definer set search_path = public as $$
declare capacity integer; joined_count integer; host uuid;
begin
  select max_players, host_id into capacity, host from matches where id = match_id for update;
  if capacity is null then raise exception 'Match not found'; end if;
  if target_user_id <> auth.uid() and host <> auth.uid() then raise exception 'Only the host can invite players'; end if;
  select count(*) into joined_count from match_players where match_id = join_match.match_id and status = 'joined';
  if joined_count >= capacity then raise exception 'Match is full'; end if;
  insert into match_players(match_id, user_id, status)
  values (match_id, target_user_id, case when target_user_id = auth.uid() then 'joined' else 'invited' end)
  on conflict (match_id, user_id) do update set status = excluded.status;
end $$;
grant execute on function public.join_match(uuid, uuid) to authenticated;

-- Uses the device location saved in profiles; results stay database-side and paged.
create or replace function public.nearby_arenas(
  user_lat double precision,
  user_lng double precision,
  page_size integer default 20,
  page_offset integer default 0
) returns setof public.arenas language sql stable as $$
  select a.* from public.arenas a
  where a.latitude is not null and a.longitude is not null
  order by 6371 * acos(least(1, cos(radians(user_lat)) * cos(radians(a.latitude)) * cos(radians(a.longitude) - radians(user_lng)) + sin(radians(user_lat)) * sin(radians(a.latitude))))
  limit page_size offset page_offset;
$$;
grant execute on function public.nearby_arenas(double precision, double precision, integer, integer) to authenticated;

-- Identity and profile contract. This trigger is the single source of truth for
-- ensuring every authenticated user has exactly one profile row.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  display_name text,
  avatar_url text,
  bio text check (char_length(bio) <= 300),
  city text,
  favorite_sports text[] not null default '{}',
  latitude double precision,
  longitude double precision,
  onboarding_complete boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_format check (username is null or username ~ '^[a-z][a-z0-9_]{3,}$')
);
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists bio text;
alter table public.profiles add column if not exists city text;
alter table public.profiles add column if not exists favorite_sports text[] not null default '{}';
alter table public.profiles add column if not exists latitude double precision;
alter table public.profiles add column if not exists longitude double precision;
alter table public.profiles add column if not exists onboarding_complete boolean not null default false;
alter table public.profiles add column if not exists role text not null default 'player'
  check (role in ('player', 'stadium_owner', 'admin'));
alter table public.profiles enable row level security;
create policy "profiles readable" on public.profiles for select to authenticated using (true);
create policy "users insert own profile" on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "users update own profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

create or replace function public.create_profile_for_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name)
  values (new.id, new.raw_user_meta_data ->> 'username',
          nullif(trim(concat_ws(' ', new.raw_user_meta_data ->> 'first_name', new.raw_user_meta_data ->> 'last_name')), ''))
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.create_profile_for_new_user();
insert into public.profiles (id, username, display_name)
select id, raw_user_meta_data ->> 'username',
       nullif(trim(concat_ws(' ', raw_user_meta_data ->> 'first_name', raw_user_meta_data ->> 'last_name')), '')
from auth.users on conflict (id) do nothing;

-- Reviews, persistent booking states, notifications and protected storage.
alter table public.arenas add column if not exists review_count integer not null default 0 check (review_count >= 0);
alter table public.bookings add column if not exists status text not null default 'upcoming'
  check (status in ('upcoming', 'current', 'previous', 'cancelled'));
create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  arena_id uuid not null references public.arenas(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text not null check (char_length(comment) between 1 and 1000),
  created_at timestamptz not null default now(),
  unique (arena_id, user_id)
);
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('match_invitation','booking_confirmation','booking_cancellation','match_reminder','stadium_update')),
  title text not null,
  body text,
  data jsonb not null default '{}',
  read_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.reviews enable row level security;
alter table public.notifications enable row level security;
create policy "reviews readable" on public.reviews for select to authenticated using (true);
create policy "users create own reviews" on public.reviews for insert to authenticated with check (user_id = auth.uid());
create policy "users update own reviews" on public.reviews for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "users delete own reviews" on public.reviews for delete to authenticated using (user_id = auth.uid());
create policy "users read own notifications" on public.notifications for select to authenticated using (user_id = auth.uid());
create index if not exists arenas_name_idx on public.arenas (name);
create index if not exists reviews_arena_id_idx on public.reviews (arena_id);
create index if not exists notifications_user_created_idx on public.notifications (user_id, created_at desc);
create index if not exists bookings_user_status_starts_idx on public.bookings (user_id, status, starts_at desc);

create or replace function public.refresh_arena_rating() returns trigger language plpgsql security definer set search_path = public as $$
begin
  update arenas set rating = stats.rating, review_count = stats.count
  from (select round(avg(rating)::numeric, 1) as rating, count(*)::integer as count from reviews where arena_id = coalesce(new.arena_id, old.arena_id)) stats
  where arenas.id = coalesce(new.arena_id, old.arena_id);
  return coalesce(new, old);
end;
$$;
drop trigger if exists reviews_refresh_arena_rating on public.reviews;
create trigger reviews_refresh_arena_rating after insert or update or delete on public.reviews
for each row execute procedure public.refresh_arena_rating();

create or replace function public.leave_match(match_id uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  delete from match_players where match_players.match_id = leave_match.match_id and user_id = auth.uid();
  if not found then raise exception 'You have not joined this match'; end if;
end;
$$;
grant execute on function public.leave_match(uuid) to authenticated;

insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true) on conflict (id) do nothing;
create policy "avatar uploads are owned" on storage.objects for insert to authenticated with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars are publicly readable" on storage.objects for select using (bucket_id = 'avatars');
create policy "avatar updates are owned" on storage.objects for update to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

insert into storage.buckets (id, name, public) values ('stadium-images', 'stadium-images', true) on conflict (id) do nothing;
create policy "stadium images are publicly readable" on storage.objects for select using (bucket_id = 'stadium-images');
create policy "owners upload stadium images" on storage.objects for insert to authenticated with check (bucket_id = 'stadium-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "owners update stadium images" on storage.objects for update to authenticated using (bucket_id = 'stadium-images' and (storage.foldername(name))[1] = auth.uid()::text);


-- BASELINE SOURCE: supabase/setup_messaging.sql
-- Run this once in Supabase Dashboard > SQL Editor. It creates private 1:1 messaging.
create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  content text,
  image_url text,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  check (content is not null or image_url is not null)
);
create table if not exists public.friend_requests (
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  primary key (sender_id, receiver_id), check (sender_id <> receiver_id)
);
create table if not exists public.user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id), check (blocker_id <> blocked_id)
);
alter table public.direct_messages enable row level security;
alter table public.friend_requests enable row level security;
alter table public.user_blocks enable row level security;
create policy "message participants only" on public.direct_messages for all using (auth.uid() in (sender_id, receiver_id)) with check (auth.uid() = sender_id);
create policy "friend request participants" on public.friend_requests for all using (auth.uid() in (sender_id, receiver_id)) with check (auth.uid() = sender_id);
create policy "own block list" on public.user_blocks for all using (auth.uid() = blocker_id) with check (auth.uid() = blocker_id);


-- BASELINE SOURCE: supabase/setup_profiles.sql
-- Run in Supabase Dashboard > SQL Editor. It protects usernames even when
-- two people try to register the same username at the same time.
alter table public.profiles
  add column if not exists display_name text;
alter table public.profiles
  add column if not exists avatar_url text;
alter table public.profiles
  add column if not exists bio text,
  add column if not exists city text,
  add column if not exists favorite_sports text[] not null default '{}',
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists onboarding_complete boolean not null default false;

create unique index if not exists profiles_username_unique
  on public.profiles (username);

alter table public.profiles
  drop constraint if exists profiles_username_format;
alter table public.profiles
  add constraint profiles_username_format
  check (username ~ '^[a-z][a-z0-9_]{3,}$');

-- Existing rows are kept. Rename duplicate/invalid existing usernames before
-- adding this constraint if the commands report conflicting data.


-- BASELINE SOURCE: supabase/public_games_chat_images_and_arena_classification.sql
-- Public games, real chat image uploads, and arena classifications.
-- Run once in Supabase SQL Editor.

alter table public.matches
  add column if not exists is_private boolean not null default false;

alter table public.arenas
  add column if not exists audience_gender text not null default 'men'
    check (audience_gender in ('men', 'women'));

comment on column public.arenas.sports is
  'Admin-managed sport types, for example {football} or {padel}.';
comment on column public.arenas.audience_gender is
  'Admin-managed audience: men or women only.';

drop policy if exists "arenas are readable" on public.arenas;
drop policy if exists "public arenas are readable" on public.arenas;
create policy "public arenas are readable"
on public.arenas for select to anon, authenticated using (true);

drop policy if exists "matches are readable" on public.matches;
drop policy if exists "public matches are readable" on public.matches;
drop policy if exists "member matches are readable" on public.matches;
create policy "public matches are readable"
on public.matches for select to anon using (not is_private);
create policy "member matches are readable"
on public.matches for select to authenticated using (
  not is_private
  or host_id = auth.uid()
  or exists (
    select 1 from public.match_players mp
    where mp.match_id = matches.id and mp.user_id = auth.uid()
  )
);

drop policy if exists "match players are readable" on public.match_players;
drop policy if exists "public match players are readable" on public.match_players;
create policy "public match players are readable"
on public.match_players for select to anon, authenticated using (true);

insert into storage.buckets (id, name, public)
values ('chat-images', 'chat-images', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "chat images publicly readable" on storage.objects;
drop policy if exists "users upload own chat images" on storage.objects;
create policy "chat images publicly readable"
on storage.objects for select
using (bucket_id = 'chat-images');
create policy "users upload own chat images"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'chat-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);


-- BASELINE SOURCE: supabase/booking_conflicts_and_match_options.sql
-- Run once in the shared PlayOn Supabase SQL Editor.
-- Prevents overlapping customer bookings and public matches for one arena.
create extension if not exists btree_gist;

alter table public.bookings
  add column if not exists status text not null default 'upcoming';

alter table public.matches
  add column if not exists gender text not null default 'men'
    check (gender in ('men', 'women')),
  add column if not exists payment_method text not null default 'cash'
    check (payment_method in ('cash', 'card')),
  add column if not exists show_joined_players boolean not null default true;

create or replace function public.prevent_arena_time_conflict()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name = 'bookings' and coalesce(new.status, 'upcoming') = 'cancelled' then
    return new;
  end if;

  if tg_table_name = 'bookings' then
    if exists (
      select 1 from public.bookings b
      where b.arena_id = new.arena_id
        and b.id is distinct from new.id
        and coalesce(b.status, 'upcoming') <> 'cancelled'
        and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) or exists (
      select 1 from public.matches m
      where m.arena_id = new.arena_id
        and tstzrange(m.starts_at, m.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) then
      raise exception 'This stadium is already booked for the selected time.';
    end if;
  else
    if exists (
      select 1 from public.matches m
      where m.arena_id = new.arena_id
        and m.id is distinct from new.id
        and tstzrange(m.starts_at, m.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) or exists (
      select 1 from public.bookings b
      where b.arena_id = new.arena_id
        and coalesce(b.status, 'upcoming') <> 'cancelled'
        and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) then
      raise exception 'This stadium is already booked for the selected time.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists bookings_prevent_arena_time_conflict on public.bookings;
create trigger bookings_prevent_arena_time_conflict
before insert or update of arena_id, starts_at, ends_at, status on public.bookings
for each row execute function public.prevent_arena_time_conflict();

drop trigger if exists matches_prevent_arena_time_conflict on public.matches;
create trigger matches_prevent_arena_time_conflict
before insert or update of arena_id, starts_at, ends_at on public.matches
for each row execute function public.prevent_arena_time_conflict();


-- BASELINE SOURCE: supabase/fix_reservation_creation_and_maps.sql
-- Run once in Supabase SQL Editor.
-- Fixes match creation on databases where the shared conflict trigger tries
-- to access bookings.status while processing a matches row.

alter table public.arenas
  add column if not exists google_maps_url text;

create or replace function public.prevent_arena_time_conflict()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name = 'bookings' then
    if coalesce(new.status, 'upcoming') = 'cancelled' then
      return new;
    end if;

    if exists (
      select 1 from public.bookings b
      where b.arena_id = new.arena_id
        and b.id is distinct from new.id
        and coalesce(b.status, 'upcoming') <> 'cancelled'
        and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) or exists (
      select 1 from public.matches m
      where m.arena_id = new.arena_id
        and tstzrange(m.starts_at, m.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) then
      raise exception 'This stadium is already booked for the selected time.';
    end if;
  elsif tg_table_name = 'matches' then
    if exists (
      select 1 from public.matches m
      where m.arena_id = new.arena_id
        and m.id is distinct from new.id
        and tstzrange(m.starts_at, m.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) or exists (
      select 1 from public.bookings b
      where b.arena_id = new.arena_id
        and coalesce(b.status, 'upcoming') <> 'cancelled'
        and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) then
      raise exception 'This stadium is already booked for the selected time.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists bookings_prevent_arena_time_conflict on public.bookings;
create trigger bookings_prevent_arena_time_conflict
before insert or update of arena_id, starts_at, ends_at, status on public.bookings
for each row execute function public.prevent_arena_time_conflict();

drop trigger if exists matches_prevent_arena_time_conflict on public.matches;
create trigger matches_prevent_arena_time_conflict
before insert or update of arena_id, starts_at, ends_at on public.matches
for each row execute function public.prevent_arena_time_conflict();


-- BASELINE SOURCE: ../arena_owner/supabase/owner_operations.sql
-- Run after the existing PlayOn production_schema.sql. This migration is the
-- authorization boundary for the separate Owner App.
create table if not exists public.owner_stadium_assignments (
  stadium_id uuid not null references public.arenas(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner' check (role in ('owner', 'staff')),
  created_at timestamptz not null default now(),
  primary key (stadium_id, user_id)
);
create table if not exists public.blocked_slots (
  id uuid primary key default gen_random_uuid(),
  arena_id uuid not null references public.arenas(id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null check (ends_at > starts_at),
  reason text not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.bookings alter column user_id drop not null;
alter table public.bookings add column if not exists booking_type text not null default 'online' check (booking_type in ('online','manual'));
alter table public.bookings add column if not exists customer_name text;
alter table public.bookings add column if not exists customer_phone text;
alter table public.bookings add column if not exists notes text;
alter table public.bookings add column if not exists payment_status text not null default 'unpaid' check (payment_status in ('unpaid','paid','refunded'));
alter table public.bookings add column if not exists cancelled_at timestamptz;
alter table public.bookings add column if not exists cancellation_reason text;
alter table public.bookings drop constraint if exists bookings_status_check;
alter table public.bookings add constraint bookings_status_check check (status in ('pending','confirmed','cancelled','completed','upcoming','current','previous'));
alter table public.owner_stadium_assignments enable row level security;
alter table public.blocked_slots enable row level security;
create or replace function public.is_arena_operator(arena uuid) returns boolean language sql stable security definer set search_path=public as $$
  select exists (select 1 from owner_stadium_assignments where stadium_id=arena and user_id=auth.uid())
    or exists (select 1 from profiles where id=auth.uid() and role='admin');
$$;
create policy "operators read own assignments" on public.owner_stadium_assignments for select to authenticated using (user_id=auth.uid());
create policy "operators read own arenas" on public.arenas for select to authenticated using (is_arena_operator(id));
create policy "operators read own bookings" on public.bookings for select to authenticated using (is_arena_operator(arena_id));
create policy "operators read own blocks" on public.blocked_slots for select to authenticated using (is_arena_operator(arena_id));
create or replace function public.owner_create_manual_booking(p_arena uuid,p_start timestamptz,p_end timestamptz,p_name text,p_phone text,p_notes text default null) returns uuid language plpgsql security definer set search_path=public as $$
declare id uuid;
begin
 if not is_arena_operator(p_arena) then raise exception 'Not authorized'; end if;
 if p_end<=p_start then raise exception 'End must be after start'; end if;
 perform 1 from bookings where arena_id=p_arena and status not in ('cancelled') and starts_at<p_end and ends_at>p_start;
 if found then raise exception 'This time is already booked'; end if;
 perform 1 from blocked_slots where arena_id=p_arena and starts_at<p_end and ends_at>p_start;
 if found then raise exception 'This time is blocked'; end if;
 insert into bookings(arena_id,starts_at,ends_at,total_price,status,booking_type,customer_name,customer_phone,notes) values(p_arena,p_start,p_end,0,'confirmed','manual',p_name,p_phone,p_notes) returning id into id;
 return id;
end $$;
create or replace function public.owner_block_slot(p_arena uuid,p_start timestamptz,p_end timestamptz,p_reason text) returns uuid language plpgsql security definer set search_path=public as $$
declare id uuid;
begin
 if not is_arena_operator(p_arena) then raise exception 'Not authorized'; end if;
 if exists(select 1 from bookings where arena_id=p_arena and status not in ('cancelled') and starts_at<p_end and ends_at>p_start) then raise exception 'A booking already occupies this time'; end if;
 insert into blocked_slots(arena_id,starts_at,ends_at,reason,created_by) values(p_arena,p_start,p_end,p_reason,auth.uid()) returning id into id; return id;
end $$;
create or replace function public.owner_cancel_booking(p_booking uuid,p_reason text) returns void language plpgsql security definer set search_path=public as $$
begin update bookings set status='cancelled',cancelled_at=now(),cancellation_reason=p_reason where id=p_booking and is_arena_operator(arena_id); if not found then raise exception 'Not authorized or booking not found'; end if; end $$;
grant execute on function public.owner_create_manual_booking(uuid,timestamptz,timestamptz,text,text,text) to authenticated;
grant execute on function public.owner_block_slot(uuid,timestamptz,timestamptz,text) to authenticated;
grant execute on function public.owner_cancel_booking(uuid,text) to authenticated;


-- BASELINE SOURCE: ../playon_admin/supabase/staff_username_auth.sql
-- Run in Supabase SQL Editor after creating the Auth user with the internal
-- email format: <username>@staff.playon.internal and confirming the user.
create table if not exists public.staff_login_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  account_type text not null check (account_type in ('admin', 'owner')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint staff_login_accounts_username_format check (username ~ '^[a-z][a-z0-9_]{3,31}$')
);
create unique index if not exists staff_login_accounts_username_unique on public.staff_login_accounts (lower(username));
alter table public.staff_login_accounts enable row level security;
drop policy if exists "staff read own login account" on public.staff_login_accounts;
create policy "staff read own login account" on public.staff_login_accounts for select to authenticated using (user_id = auth.uid());
create or replace function public.normalize_staff_username() returns trigger language plpgsql set search_path = public as $$
begin new.username := lower(trim(new.username)); new.updated_at := now(); return new; end; $$;
drop trigger if exists normalize_staff_username_trigger on public.staff_login_accounts;
create trigger normalize_staff_username_trigger before insert or update of username on public.staff_login_accounts for each row execute function public.normalize_staff_username();

-- Admin seed after the Auth user is created and confirmed:
-- insert into public.staff_login_accounts (user_id, username, account_type)
-- select id, 'playon_admin', 'admin' from auth.users where email = 'playon_admin@staff.playon.internal'
-- on conflict (user_id) do update set username=excluded.username, account_type=excluded.account_type, active=true;
-- insert into public.admin_users (user_id, active)
-- select id, true from auth.users where email = 'playon_admin@staff.playon.internal'
-- on conflict (user_id) do update set active=true;


-- BASELINE SOURCE: ../playon_admin/supabase/admin_dashboard.sql
-- Run after the shared PlayOn and owner-operation migrations.
create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  active boolean not null default true, created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;
create or replace function public.is_platform_admin() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.admin_users where user_id=auth.uid() and active);
$$;
create policy "admins read own authorization" on public.admin_users for select to authenticated using (user_id=auth.uid());
drop policy if exists "admins manage arenas" on public.arenas;
create policy "admins manage arenas" on public.arenas for all to authenticated using (is_platform_admin()) with check (is_platform_admin());
drop policy if exists "admins manage assignments" on public.owner_stadium_assignments;
create policy "admins manage assignments" on public.owner_stadium_assignments for all to authenticated using (is_platform_admin()) with check (is_platform_admin());
drop policy if exists "admins read bookings" on public.bookings;
create policy "admins read bookings" on public.bookings for select to authenticated using (is_platform_admin());
drop policy if exists "admins read profiles" on public.profiles;
create policy "admins read profiles" on public.profiles for select to authenticated using (is_platform_admin());

-- Arena lifecycle and images are controlled only by platform administrators.
alter table public.arenas add column if not exists is_active boolean not null default true;
insert into storage.buckets (id, name, public)
values ('stadium-images', 'stadium-images', true)
on conflict (id) do update set public = true;
drop policy if exists "admins manage stadium image objects" on storage.objects;
create or replace function public.can_manage_stadium_image(p_object_name text)
returns boolean language plpgsql stable security definer set search_path=public,storage as $$
declare v_parts text[]; v_arena_id uuid;
begin
  if public.is_platform_admin() then return true; end if;
  v_parts := storage.foldername(p_object_name);
  if coalesce(array_length(v_parts, 1), 0) < 2 then return false; end if;
  begin v_arena_id := v_parts[2]::uuid;
  exception when invalid_text_representation then return false;
  end;
  return public.is_stadium_owner_of(v_arena_id);
end;
$$;
create policy "admins manage stadium image objects" on storage.objects for all to authenticated
  using (bucket_id = 'stadium-images' and public.can_manage_stadium_image(name))
  with check (bucket_id = 'stadium-images' and public.can_manage_stadium_image(name));

-- Admins need the staff directory to count owners and build assignment lists.
drop policy if exists "admins read staff login accounts" on public.staff_login_accounts;
create policy "admins read staff login accounts" on public.staff_login_accounts
  for select to authenticated using (public.is_platform_admin());
create or replace function public.admin_delete_arena(p_arena uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not is_platform_admin() then raise exception 'Not authorized'; end if;
  if exists (select 1 from public.bookings where arena_id = p_arena) then
    raise exception 'Arena has booking history; deactivate it instead.';
  end if;
  delete from public.arenas where id = p_arena;
  if not found then raise exception 'Arena not found'; end if;
end $$;
grant execute on function public.admin_delete_arena(uuid) to authenticated;
revoke all on function public.admin_delete_arena(uuid) from public, anon, authenticated;


-- BASELINE SOURCE: supabase/arena_v2_booking_system.sql
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
  add column if not exists court_count integer not null default 1,
  add column if not exists is_active boolean not null default true;

alter table public.arenas drop constraint if exists arenas_court_count_check;
alter table public.arenas add constraint arenas_court_count_check
check (court_count between 1 and 50);

alter table public.arenas drop constraint if exists arenas_audience_gender_check;
-- The legacy schema used `mixed` as a default even though new Arena records
-- must be explicitly classified as men or women by an admin.
alter table public.arenas alter column audience_gender drop default;
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

-- Keeps the physical units synchronized with the count selected by an admin
-- or stadium owner. Reducing the count is rejected while a removed unit still
-- has an active future booking or match.
create or replace function public.sync_arena_courts_from_count()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.court_count < old.court_count and exists (
    select 1 from public.arena_courts c
    where c.arena_id = new.id and c.court_number > new.court_count
      and (
        exists (
          select 1 from public.bookings b where b.court_id = c.id
            and coalesce(b.status, 'upcoming') <> 'cancelled' and b.ends_at > now()
        ) or exists (
          select 1 from public.matches m where m.court_id = c.id
            and coalesce(m.status, 'upcoming') <> 'cancelled' and m.ends_at > now()
        )
      )
  ) then
    raise exception 'COURT_COUNT_HAS_ACTIVE_BOOKINGS';
  end if;

  insert into public.arena_courts(arena_id, court_number, label_ar, label_en, is_active)
  select new.id, n, 'الملعب رقم ' || n, 'Court ' || n, true
  from generate_series(1, new.court_count) n
  on conflict (arena_id, court_number) do update set is_active = true;

  update public.arena_courts set is_active = false
  where arena_id = new.id and court_number > new.court_count;
  return new;
end;
$$;

drop trigger if exists arenas_sync_court_count on public.arenas;
create trigger arenas_sync_court_count
after insert or update of court_count on public.arenas
for each row execute function public.sync_arena_courts_from_count();

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
select a.id, n, 'الملعب رقم ' || n, 'Court ' || n
from public.arenas a
cross join lateral generate_series(1, a.court_count) n
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
create or replace function public.arena_accepts_time_range(
  p_arena_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  v_open time;
  v_close time;
  v_start_local timestamp := p_starts_at at time zone 'Asia/Muscat';
  v_end_local timestamp := p_ends_at at time zone 'Asia/Muscat';
  v_window_start timestamp;
  v_window_end timestamp;
begin
  if p_ends_at <= p_starts_at or
     p_ends_at - p_starts_at > interval '12 hours' then
    return false;
  end if;
  select opening_time, closing_time into v_open, v_close
  from public.arenas where id = p_arena_id and coalesce(is_active, true);
  if not found then return false; end if;
  if v_open is null or v_close is null or v_open = v_close then return true; end if;
  if v_open < v_close then
    v_window_start := v_start_local::date + v_open;
    v_window_end := v_start_local::date + v_close;
  elsif v_start_local::time >= v_open then
    v_window_start := v_start_local::date + v_open;
    v_window_end := (v_start_local::date + 1) + v_close;
  else
    v_window_start := (v_start_local::date - 1) + v_open;
    v_window_end := v_start_local::date + v_close;
  end if;
  return v_start_local >= v_window_start and v_end_local <= v_window_end;
end;
$$;
revoke all on function public.arena_accepts_time_range(uuid, timestamptz, timestamptz) from public;

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
  select public.arena_accepts_time_range(p_arena_id, p_starts_at, p_ends_at)
  and exists (
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
  if not public.arena_accepts_time_range(p_arena_id, p_starts_at, p_ends_at) then
    raise exception 'ARENA_CLOSED_FOR_RANGE';
  end if;
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
  if not public.arena_accepts_time_range(p_arena_id, p_starts_at, p_ends_at) then
    raise exception 'ARENA_CLOSED_FOR_RANGE';
  end if;
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

-- Private matches require a host decision. Public matches keep the existing
-- one-tap join behavior. The status constraint is extended without changing
-- any existing rows.
alter table public.match_players drop constraint if exists match_players_status_check;
alter table public.match_players add constraint match_players_status_check
check (status in ('invited', 'requested', 'joined', 'rejected'));

create or replace function public.request_match_join(p_match_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_match public.matches%rowtype; v_player_gender text;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_match from public.matches
  where id = p_match_id and status <> 'cancelled' for update;
  if v_match.id is null then raise exception 'MATCH_NOT_FOUND'; end if;
  if v_match.host_id = auth.uid() then return 'joined'; end if;
  select gender into v_player_gender from public.profiles where id = auth.uid();
  if v_player_gender is null then raise exception 'PROFILE_GENDER_REQUIRED'; end if;
  if v_match.gender is null or v_match.gender <> v_player_gender then
    raise exception 'GENDER_NOT_ALLOWED';
  end if;
  if exists (
    select 1 from public.match_players
    where match_id = p_match_id and user_id = auth.uid() and status = 'invited'
  ) then
    perform public.join_match(p_match_id, auth.uid());
    return 'joined';
  end if;
  if not v_match.is_private then
    perform public.join_match(p_match_id, auth.uid());
    return 'joined';
  end if;
  insert into public.match_players(match_id, user_id, status)
  values (p_match_id, auth.uid(), 'requested')
  on conflict (match_id, user_id) do update set status = 'requested';
  return 'requested';
end;
$$;
revoke all on function public.request_match_join(uuid) from public;
grant execute on function public.request_match_join(uuid) to authenticated;

create or replace function public.respond_match_join_request(
  p_match_id uuid,
  p_user_id uuid,
  p_accept boolean
)
returns void language plpgsql security definer set search_path = public as $$
declare v_host uuid; v_capacity integer; v_joined integer;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select host_id, max_players into v_host, v_capacity
  from public.matches where id = p_match_id and status <> 'cancelled' for update;
  if v_host is null then raise exception 'MATCH_NOT_FOUND'; end if;
  if v_host <> auth.uid() then raise exception 'HOST_ONLY'; end if;
  if not exists (
    select 1 from public.match_players
    where match_id = p_match_id and user_id = p_user_id and status = 'requested'
  ) then raise exception 'JOIN_REQUEST_NOT_FOUND'; end if;
  if p_accept then
    select count(*) into v_joined from public.match_players
    where match_id = p_match_id and status = 'joined';
    if v_joined >= v_capacity then raise exception 'MATCH_FULL'; end if;
  end if;
  update public.match_players
  set status = case when p_accept then 'joined' else 'rejected' end,
      joined_at = case when p_accept then now() else joined_at end
  where match_id = p_match_id and user_id = p_user_id;
end;
$$;
revoke all on function public.respond_match_join_request(uuid, uuid, boolean) from public;
grant execute on function public.respond_match_join_request(uuid, uuid, boolean) to authenticated;

create or replace function public.can_view_match(
  p_match_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.matches m
    where m.id = p_match_id and (
      not m.is_private or m.host_id = p_user_id or exists (
        select 1 from public.match_players mp
        where mp.match_id = m.id and mp.user_id = p_user_id
          and mp.status in ('invited', 'requested', 'joined')
      )
    )
  );
$$;

create or replace function public.can_view_match_players(
  p_match_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.matches m
    where m.id = p_match_id and (
      m.host_id = p_user_id or
      exists (
        select 1 from public.match_players own
        where own.match_id = m.id and own.user_id = p_user_id
          and own.status in ('invited', 'requested', 'joined')
      ) or (not m.is_private and coalesce(m.show_joined_players, true))
    )
  );
$$;

drop policy if exists "matches are readable" on public.matches;
drop policy if exists "visible matches are readable" on public.matches;
create policy "visible matches are readable" on public.matches
for select to anon, authenticated using (public.can_view_match(id));

drop policy if exists "match players are readable" on public.match_players;
drop policy if exists "visible match players are readable" on public.match_players;
create policy "visible match players are readable" on public.match_players
for select to anon, authenticated using (public.can_view_match_players(match_id));

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

create table if not exists public.notification_push_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications(id) on delete cascade,
  device_token_id uuid not null references public.device_tokens(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'sent', 'failed')),
  provider_message_id text,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (notification_id, device_token_id)
);

alter table public.notification_push_deliveries
  drop constraint if exists notification_push_deliveries_status_check;
alter table public.notification_push_deliveries
  add constraint notification_push_deliveries_status_check
  check (status in ('pending', 'sending', 'sent', 'failed'));

-- Atomically claims a notification/token pair before the Edge Function calls
-- FCM. A concurrent webhook invocation receives no row and therefore cannot
-- deliver the same notification twice. Only explicit provider failures may be
-- claimed again; an indeterminate network interruption remains `sending` and
-- requires administrative review rather than risking a duplicate push.
create or replace function public.claim_notification_push_delivery(
  p_notification_id uuid,
  p_device_token_id uuid
)
returns table(delivery_id uuid, delivery_attempt_count integer)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  insert into public.notification_push_deliveries as delivery(
    notification_id, device_token_id, status, attempt_count, updated_at
  ) values (
    p_notification_id, p_device_token_id, 'sending', 1, now()
  )
  on conflict (notification_id, device_token_id) do update
  set status = 'sending',
      attempt_count = delivery.attempt_count + 1,
      last_error_code = null,
      updated_at = now()
  where delivery.status in ('pending', 'failed')
  returning delivery.id, delivery.attempt_count;
end;
$$;
revoke all on function public.claim_notification_push_delivery(uuid, uuid) from public;
grant execute on function public.claim_notification_push_delivery(uuid, uuid) to service_role;

-- A fixed-window rate limiter used by the assistant Edge Function. The RPC
-- never exposes another user's counters and accepts no user id parameter.
create table if not exists public.arena_assistant_rate_limits (
  user_id uuid not null references auth.users(id) on delete cascade,
  window_start timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0),
  primary key (user_id, window_start)
);

create or replace function public.consume_arena_assistant_rate_limit(
  p_max_requests integer default 12
)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_window timestamptz := date_trunc('minute', now()); v_count integer;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_max_requests < 1 or p_max_requests > 60 then
    raise exception 'INVALID_RATE_LIMIT';
  end if;
  insert into public.arena_assistant_rate_limits(user_id, window_start, request_count)
  values (auth.uid(), v_window, 1)
  on conflict (user_id, window_start) do update
  set request_count = public.arena_assistant_rate_limits.request_count + 1
  returning request_count into v_count;
  return v_count <= p_max_requests;
end;
$$;
revoke all on function public.consume_arena_assistant_rate_limit(integer) from public;
grant execute on function public.consume_arena_assistant_rate_limit(integer) to authenticated;

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (
  type in (
    'match_invitation', 'booking_confirmation', 'booking_cancellation',
    'booking_status', 'booking_reminder', 'match_reminder', 'player_joined', 'players_complete',
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

-- Supabase Cron can call this function every five minutes. Unique event keys
-- make the operation safe to retry without sending the same reminder twice.
create or replace function public.enqueue_due_event_reminders()
returns integer language plpgsql security definer set search_path = public as $$
declare v_inserted integer := 0; v_rows integer := 0;
begin
  insert into public.notifications(
    user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
  )
  select b.user_id, 'booking_reminder', 'Booking reminder',
    'Your Arena booking starts in about one hour.',
    'تذكير بالحجز', 'Booking reminder',
    'يبدأ حجزك في أرينا خلال ساعة تقريبًا.',
    'Your Arena booking starts in about one hour.',
    jsonb_build_object('booking_id', b.id, 'arena_id', b.arena_id),
    'booking-reminder:' || b.id::text
  from public.bookings b
  where b.status in ('upcoming', 'current')
    and b.starts_at > now() + interval '55 minutes'
    and b.starts_at <= now() + interval '65 minutes'
  on conflict (user_id, event_key) where event_key is not null do nothing;
  get diagnostics v_rows = row_count;
  v_inserted := v_inserted + v_rows;

  insert into public.notifications(
    user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
  )
  select recipients.user_id, 'match_reminder', 'Game reminder',
    'Your Arena game starts in about one hour.',
    'تذكير بالمباراة', 'Game reminder',
    'تبدأ مباراتك في أرينا خلال ساعة تقريبًا.',
    'Your Arena game starts in about one hour.',
    jsonb_build_object('match_id', recipients.match_id, 'arena_id', recipients.arena_id),
    'match-reminder:' || recipients.match_id::text || ':' || recipients.user_id::text
  from (
    select m.id as match_id, m.arena_id, m.host_id as user_id
    from public.matches m
    where m.status in ('upcoming', 'current')
      and m.starts_at > now() + interval '55 minutes'
      and m.starts_at <= now() + interval '65 minutes'
    union
    select m.id, m.arena_id, mp.user_id
    from public.matches m
    join public.match_players mp on mp.match_id = m.id and mp.status = 'joined'
    where m.status in ('upcoming', 'current')
      and m.starts_at > now() + interval '55 minutes'
      and m.starts_at <= now() + interval '65 minutes'
  ) recipients
  on conflict (user_id, event_key) where event_key is not null do nothing;
  get diagnostics v_rows = row_count;
  return v_inserted + v_rows;
end;
$$;
revoke all on function public.enqueue_due_event_reminders() from public;
grant execute on function public.enqueue_due_event_reminders() to service_role;

-- Notify only users who have a future active booking at the updated arena.
-- Rating refreshes are excluded so a review does not look like a venue update.
create or replace function public.notify_arena_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (to_jsonb(new) - 'rating' - 'review_count') is not distinct from
     (to_jsonb(old) - 'rating' - 'review_count') then
    return new;
  end if;
  insert into public.notifications(
    user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
  )
  select distinct b.user_id, 'stadium_update', 'Arena details updated',
    'Details for an arena in your upcoming bookings changed.',
    'تم تحديث بيانات الملعب', 'Arena details updated',
    'تغيّرت بيانات ملعب ضمن حجوزاتك القادمة.',
    'Details for an arena in your upcoming bookings changed.',
    jsonb_build_object('arena_id', new.id, 'booking_id', b.id),
    'stadium-update:' || b.id::text || ':' || txid_current()::text
  from public.bookings b
  where b.arena_id = new.id and b.status <> 'cancelled' and b.ends_at > now()
  on conflict (user_id, event_key) where event_key is not null do nothing;
  return new;
end;
$$;

drop trigger if exists arenas_create_update_notification on public.arenas;
create trigger arenas_create_update_notification
after update on public.arenas
for each row execute function public.notify_arena_update();

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

create or replace function public.notify_match_player_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_match public.matches%rowtype; v_joined integer; v_status_changed boolean;
begin
  select * into v_match from public.matches where id = new.match_id;
  if v_match.id is null then return new; end if;

  if tg_op = 'INSERT' then
    v_status_changed := true;
  else
    v_status_changed := new.status is distinct from old.status;
  end if;

  if new.status = 'invited' and v_status_changed then
    insert into public.notifications(
      user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
    ) values (
      new.user_id, 'match_invitation', 'Game invitation', 'You were invited to a game.',
      'دعوة إلى مباراة', 'Game invitation', 'تمت دعوتك للانضمام إلى مباراة.',
      'You were invited to join a game.', jsonb_build_object('match_id', new.match_id),
      'match-invitation:' || new.match_id::text || ':' || new.user_id::text
    ) on conflict (user_id, event_key) where event_key is not null do nothing;
  elsif new.status = 'requested' and v_status_changed then
    insert into public.notifications(
      user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
    ) values (
      v_match.host_id, 'join_request', 'Join request', 'A player requested to join your game.',
      'طلب انضمام', 'Join request', 'طلب لاعب الانضمام إلى مباراتك.',
      'A player requested to join your game.',
      jsonb_build_object('match_id', new.match_id, 'requester_id', new.user_id),
      'join-request:' || new.match_id::text || ':' || new.user_id::text
    ) on conflict (user_id, event_key) where event_key is not null do nothing;
  elsif new.status = 'rejected' and v_status_changed then
    insert into public.notifications(
      user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
    ) values (
      new.user_id, 'join_rejected', 'Join request declined', 'Your join request was declined.',
      'تم رفض طلب الانضمام', 'Join request declined', 'تم رفض طلب انضمامك.',
      'Your join request was declined.', jsonb_build_object('match_id', new.match_id),
      'join-rejected:' || new.match_id::text || ':' || new.user_id::text
    ) on conflict (user_id, event_key) where event_key is not null do nothing;
  elsif new.status = 'joined' and v_status_changed and
        new.user_id <> v_match.host_id then
    insert into public.notifications(
      user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
    ) values (
      v_match.host_id, 'player_joined', 'Player joined', 'A player joined your game.',
      'انضم لاعب', 'Player joined', 'انضم لاعب إلى مباراتك.',
      'A player joined your game.', jsonb_build_object('match_id', new.match_id, 'player_id', new.user_id),
      'player-joined:' || new.match_id::text || ':' || new.user_id::text
    ) on conflict (user_id, event_key) where event_key is not null do nothing;

    if tg_op = 'UPDATE' then
      if old.status = 'requested' then
        insert into public.notifications(
          user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
        ) values (
          new.user_id, 'join_accepted', 'Join request accepted', 'You joined the game.',
          'تم قبول طلب الانضمام', 'Join request accepted', 'تم قبولك في المباراة.',
          'You joined the game.', jsonb_build_object('match_id', new.match_id),
          'join-accepted:' || new.match_id::text || ':' || new.user_id::text
        ) on conflict (user_id, event_key) where event_key is not null do nothing;
      end if;
    end if;
  end if;

  if new.status = 'joined' then
    select count(*) into v_joined from public.match_players
    where match_id = new.match_id and status = 'joined';
    if v_joined >= v_match.max_players then
      insert into public.notifications(
        user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
      )
      select mp.user_id, 'players_complete', 'Game is full', 'All player spots are filled.',
        'اكتمل عدد اللاعبين', 'Game is full', 'اكتمل عدد اللاعبين في المباراة.',
        'All player spots are filled.', jsonb_build_object('match_id', new.match_id),
        'players-complete:' || new.match_id::text
      from public.match_players mp
      where mp.match_id = new.match_id and mp.status = 'joined'
      on conflict (user_id, event_key) where event_key is not null do nothing;
    end if;
  end if;
  return new;
end;
$$;

-- Shared authorization contract for the React admin/stadium-owner portal.
create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.owner_stadium_assignments (
  stadium_id uuid not null references public.arenas(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'owner' check (role in ('owner', 'manager')),
  created_at timestamptz not null default now(),
  primary key (stadium_id, user_id)
);

create or replace function public.is_platform_admin_user(p_user_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.admin_users a
    where a.user_id = p_user_id and a.active
  ) or exists (
    select 1 from public.profiles p
    where p.id = p_user_id and p.role = 'admin'
  );
$$;

create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_platform_admin_user(auth.uid());
$$;

create or replace function public.is_stadium_owner_of(
  p_arena_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.arenas a
    where a.id = p_arena_id and a.owner_id = p_user_id
  ) or exists (
    select 1 from public.owner_stadium_assignments assignment
    where assignment.stadium_id = p_arena_id and assignment.user_id = p_user_id
  );
$$;

-- Staff access is added after the shared role helpers exist. Public users keep
-- the stricter private-match/direct-link rules defined above.
create or replace function public.can_view_match(
  p_match_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.matches m
    where m.id = p_match_id and (
      (
        not m.is_private and (
          p_user_id is null or exists (
            select 1 from public.profiles viewer
            where viewer.id = p_user_id and viewer.gender = m.gender
          )
        )
      ) or m.host_id = p_user_id or
      public.is_platform_admin_user(p_user_id) or
      public.is_stadium_owner_of(m.arena_id, p_user_id) or exists (
        select 1 from public.match_players mp
        where mp.match_id = m.id and mp.user_id = p_user_id
          and mp.status in ('invited', 'requested', 'joined')
      )
    )
  );
$$;

create or replace function public.can_view_match_players(
  p_match_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.matches m
    where m.id = p_match_id and (
      public.is_platform_admin_user(p_user_id) or
      public.is_stadium_owner_of(m.arena_id, p_user_id) or
      m.host_id = p_user_id or exists (
        select 1 from public.match_players own
        where own.match_id = m.id and own.user_id = p_user_id
          and own.status in ('invited', 'requested', 'joined')
      ) or (not m.is_private and coalesce(m.show_joined_players, true))
    )
  );
$$;

create or replace function public.can_view_match_player_row(
  p_match_id uuid,
  p_row_user_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.matches m
    where m.id = p_match_id and (
      public.is_platform_admin_user(p_user_id) or
      public.is_stadium_owner_of(m.arena_id, p_user_id) or
      m.host_id = p_user_id or p_row_user_id = p_user_id or
      (
        not m.is_private and coalesce(m.show_joined_players, true) and (
          p_user_id is null or exists (
            select 1 from public.profiles viewer
            where viewer.id = p_user_id and viewer.gender = m.gender
          )
        )
      )
    )
  );
$$;

drop policy if exists "visible match players are readable" on public.match_players;
create policy "visible match players are readable" on public.match_players
for select to anon, authenticated
using (public.can_view_match_player_row(match_id, user_id));

alter table public.admin_users enable row level security;
alter table public.owner_stadium_assignments enable row level security;

drop policy if exists "admins read own authorization" on public.admin_users;
create policy "admins read own authorization" on public.admin_users
for select to authenticated using (user_id = auth.uid());

drop policy if exists "staff read visible assignments" on public.owner_stadium_assignments;
create policy "staff read visible assignments" on public.owner_stadium_assignments
for select to authenticated using (
  public.is_platform_admin() or user_id = auth.uid()
);
drop policy if exists "admins manage assignments" on public.owner_stadium_assignments;
create policy "admins manage assignments" on public.owner_stadium_assignments
for all to authenticated using (public.is_platform_admin())
with check (public.is_platform_admin());

drop policy if exists "admins manage arenas" on public.arenas;
create policy "admins manage arenas" on public.arenas
for all to authenticated using (public.is_platform_admin())
with check (public.is_platform_admin());
drop policy if exists "owners update assigned arenas" on public.arenas;
create policy "owners update assigned arenas" on public.arenas
for update to authenticated using (public.is_stadium_owner_of(id))
with check (public.is_stadium_owner_of(id));

drop policy if exists "staff read assigned bookings" on public.bookings;
create policy "staff read assigned bookings" on public.bookings
for select to authenticated using (
  public.is_platform_admin() or public.is_stadium_owner_of(arena_id)
);

drop policy if exists "admins read all profiles" on public.profiles;
create policy "admins read all profiles" on public.profiles
for select to authenticated using (public.is_platform_admin());

drop policy if exists "admins read point ledger" on public.point_transactions;
create policy "admins read point ledger" on public.point_transactions
for select to authenticated using (public.is_platform_admin());
drop policy if exists "admins read reward coupons" on public.reward_coupons;
create policy "admins read reward coupons" on public.reward_coupons
for select to authenticated using (public.is_platform_admin());
drop policy if exists "admins read notification events" on public.notifications;
create policy "admins read notification events" on public.notifications
for select to authenticated using (public.is_platform_admin());
drop policy if exists "admins read push deliveries" on public.notification_push_deliveries;
create policy "admins read push deliveries" on public.notification_push_deliveries
for select to authenticated using (public.is_platform_admin());

alter table public.reviews
  add column if not exists moderation_status text not null default 'visible',
  add column if not exists moderation_reason text,
  add column if not exists moderated_by uuid references auth.users(id) on delete set null,
  add column if not exists moderated_at timestamptz;
alter table public.reviews drop constraint if exists reviews_moderation_status_check;
alter table public.reviews add constraint reviews_moderation_status_check
check (moderation_status in ('visible', 'hidden'));

drop policy if exists "reviews readable" on public.reviews;
drop policy if exists "visible reviews are readable" on public.reviews;
create policy "visible reviews are readable" on public.reviews
for select to anon, authenticated using (
  moderation_status = 'visible' or user_id = auth.uid() or
  public.is_platform_admin() or public.is_stadium_owner_of(arena_id)
);

create or replace function public.moderate_arena_review(
  p_review_id uuid,
  p_hide boolean,
  p_reason text default null
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'ADMIN_ONLY'; end if;
  if p_hide and nullif(trim(p_reason), '') is null then
    raise exception 'MODERATION_REASON_REQUIRED';
  end if;
  update public.reviews
  set moderation_status = case when p_hide then 'hidden' else 'visible' end,
      moderation_reason = case when p_hide then trim(p_reason) else null end,
      moderated_by = auth.uid(), moderated_at = now()
  where id = p_review_id;
  if not found then raise exception 'REVIEW_NOT_FOUND'; end if;
end;
$$;
revoke all on function public.moderate_arena_review(uuid, boolean, text) from public;
grant execute on function public.moderate_arena_review(uuid, boolean, text) to authenticated;

create or replace function public.refresh_arena_rating()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_arena_id uuid;
begin
  if tg_op = 'DELETE' then
    v_arena_id := old.arena_id;
  else
    v_arena_id := new.arena_id;
  end if;
  update public.arenas set rating = stats.rating, review_count = stats.count
  from (
    select coalesce(round(avg(rating)::numeric, 1), 0) as rating,
      count(*)::integer as count
    from public.reviews
    where arena_id = v_arena_id
      and moderation_status = 'visible'
  ) stats
  where arenas.id = v_arena_id;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.cancel_arena_booking(
  p_booking_id uuid,
  p_reason text
)
returns void language plpgsql security definer set search_path = public as $$
declare v_arena_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if nullif(trim(p_reason), '') is null then
    raise exception 'CANCELLATION_REASON_REQUIRED';
  end if;
  select arena_id into v_arena_id from public.bookings
  where id = p_booking_id for update;
  if v_arena_id is null then raise exception 'BOOKING_NOT_FOUND'; end if;
  if not public.is_platform_admin() and
     not public.is_stadium_owner_of(v_arena_id) then
    raise exception 'CANCELLATION_NOT_ALLOWED';
  end if;
  update public.bookings
  set status = 'cancelled', cancelled_by = auth.uid(), cancelled_at = now(),
      cancellation_reason = trim(p_reason)
  where id = p_booking_id and status <> 'cancelled';
end;
$$;

drop trigger if exists match_players_create_notification on public.match_players;
create trigger match_players_create_notification
after insert or update of status on public.match_players
for each row execute function public.notify_match_player_event();

alter table public.notification_push_deliveries enable row level security;
alter table public.arena_assistant_rate_limits enable row level security;

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


-- EXISTING MIGRATION: 202609290001_phase1_security_profile.sql
-- PHASE 1 / 1. Requires the existing Arena v2 schema. Apply after preflight.
-- No existing users, profiles, bookings or matches are deleted.
revoke create on schema public from public,anon,authenticated;
create schema if not exists arena_private;
revoke all on schema arena_private from public, anon, authenticated;
create extension if not exists pgcrypto with schema extensions;

-- Do not promote legacy profiles.role values: that column was client writable.
create or replace function public.is_platform_admin_user(p_user_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from admin_users where user_id=p_user_id and active)
    and not exists(select 1 from staff_login_accounts where user_id=p_user_id and not active);
$$;
create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select public.is_platform_admin_user(auth.uid());
$$;
create or replace function public.is_stadium_owner_of(p_arena_id uuid,p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
  select (exists(select 1 from arenas where id=p_arena_id and owner_id=p_user_id)
    or exists(select 1 from owner_stadium_assignments where stadium_id=p_arena_id and user_id=p_user_id))
    and not exists(select 1 from staff_login_accounts where user_id=p_user_id and not active);
$$;
create or replace function public.is_arena_operator(arena uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.is_platform_admin() or public.is_stadium_owner_of(arena);
$$;
create or replace function public.my_staff_access()
returns text language sql stable security definer set search_path=public as $$
  select case when public.is_platform_admin() then 'admin'
    when exists(select 1 from arenas where public.is_stadium_owner_of(id)) then 'stadium_owner'
    else null end;
$$;

alter table public.profiles add column if not exists date_of_birth date;
alter table public.profiles add column if not exists profile_version integer not null default 0;
-- Duplicate normalized usernames abort rather than silently renaming accounts.
do $$ begin
  if exists(select lower(trim(username)) from profiles where username is not null
      group by lower(trim(username)) having count(*)>1) then
    raise exception 'PHASE1_PREFLIGHT_DUPLICATE_USERNAMES: resolve reviewed duplicates first';
  end if;
end $$;
create unique index if not exists profiles_username_canonical_uidx
  on public.profiles(lower(trim(username))) where username is not null;

create table arena_private.pin_secret (
  singleton boolean primary key default true check(singleton), secret bytea not null
);
insert into arena_private.pin_secret values(true,extensions.gen_random_bytes(32));
create table arena_private.profile_credentials (
  user_id uuid primary key references auth.users(id) on delete cascade,
  pin_hash text not null, updated_at timestamptz not null default now()
);
revoke all on all tables in schema arena_private from public,anon,authenticated;

create or replace function public.require_oman_user()
returns uuid language plpgsql stable security definer set search_path=public as $$
declare v_id uuid:=auth.uid();
begin
  if v_id is null or not exists(select 1 from auth.users where id=v_id
      and phone ~ '^\+?968[0-9]{8}$' and phone_confirmed_at is not null) then
    raise exception 'VERIFIED_OMAN_PHONE_REQUIRED' using errcode='42501';
  end if;
  return v_id;
end $$;

create or replace function public.my_profile_complete()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from profiles p join auth.users u on u.id=p.id
    join arena_private.profile_credentials c on c.user_id=p.id
    where p.id=auth.uid() and u.phone ~ '^\+?968[0-9]{8}$'
      and u.phone_confirmed_at is not null and p.profile_version=1
      and p.onboarding_complete and nullif(trim(p.display_name),'') is not null
      and p.username ~ '^[a-z][a-z0-9_]{3,31}$' and p.date_of_birth is not null
      and p.gender in ('men','women'));
$$;

create or replace function public.complete_my_profile(
  p_display_name text,p_username text,p_date_of_birth date,p_pin text,p_gender text
) returns void language plpgsql security definer set search_path=public,extensions as $$
declare v_id uuid:=public.require_oman_user(); v_username text:=lower(trim(p_username)); v_secret bytea;
begin
  if char_length(trim(p_display_name)) not between 1 and 100 or p_display_name is null
    or v_username is null or v_username !~ '^[a-z][a-z0-9_]{3,31}$'
    or p_date_of_birth is null or p_date_of_birth>(now() at time zone 'Asia/Muscat')::date
    or p_date_of_birth<((now() at time zone 'Asia/Muscat')::date-interval '120 years')::date
    or p_pin is null or p_pin !~ '^[0-9]{4}$' or p_gender is null or p_gender not in ('men','women') then
    raise exception 'INVALID_PROFILE';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('profile:'||v_id::text,0));
  if public.my_profile_complete() then raise exception 'PROFILE_ALREADY_COMPLETE'; end if;
  select secret into v_secret from arena_private.pin_secret where singleton;
  -- Pepper is private; bcrypt is salted. No PIN verification/auth alternative is exposed.
  insert into arena_private.profile_credentials(user_id,pin_hash)
    values(v_id,crypt(encode(hmac(convert_to(p_pin,'UTF8'),v_secret,'sha256'),'hex'),gen_salt('bf',12)))
    on conflict(user_id) do update set pin_hash=excluded.pin_hash,updated_at=now();
  insert into profiles(id,display_name,username,date_of_birth,gender,first_name,last_name,onboarding_complete,profile_version)
    values(v_id,trim(p_display_name),v_username,p_date_of_birth,p_gender,trim(p_display_name),'',true,1)
    on conflict(id) do update set display_name=excluded.display_name,username=excluded.username,
      date_of_birth=excluded.date_of_birth,gender=excluded.gender,first_name=excluded.first_name,
      last_name=excluded.last_name,onboarding_complete=true,profile_version=1;
end $$;

-- Metadata cannot assign privileges or assert profile completion at signup.
create or replace function public.create_profile_for_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id,role,onboarding_complete) values(new.id,'player',false)
    on conflict(id) do nothing;
  return new;
end $$;

-- Opt-in Auth hook: configured in Dashboard. Admin-provisioned staff use Admin API.
create or replace function public.before_user_created_oman(event jsonb)
returns jsonb language plpgsql set search_path=public as $$
begin
  if coalesce(event->'user'->>'phone','') !~ '^\+?968[0-9]{8}$' then
    return jsonb_build_object('error',jsonb_build_object('http_code',403,'message','Oman phone signup only'));
  end if;
  return '{}'::jsonb;
end $$;
revoke all on function public.before_user_created_oman(jsonb) from public,anon,authenticated;
grant execute on function public.before_user_created_oman(jsonb) to supabase_auth_admin;
grant usage on schema public to supabase_auth_admin;

-- Replace ALL old policies on these tables, including permissive legacy ones.
do $$ declare r record; begin
  for r in select tablename,policyname from pg_policies where schemaname='public'
    and tablename in ('profiles','bookings','matches','match_players','reviews','arena_courts',
      'arenas','admin_users','owner_stadium_assignments','staff_login_accounts') loop
    execute format('drop policy %I on public.%I',r.policyname,r.tablename);
  end loop;
end $$;
revoke insert,update,delete,truncate,references,trigger on public.profiles from public,anon,authenticated;
-- Table REVOKE alone does not remove any legacy column-level grants.
do $$ declare r record;begin
  for r in select column_name from information_schema.columns where table_schema='public' and table_name='profiles' loop
    execute format('revoke insert(%I),update(%I),references(%I) on public.profiles from public,anon,authenticated',r.column_name,r.column_name,r.column_name);
  end loop;
end $$;
grant select on public.profiles to authenticated;
grant update(username,display_name,first_name,last_name,bio,city,avatar_url,gender,latitude,longitude,favorite_sports)
  on public.profiles to authenticated;
create policy phase1_profile_read on profiles for select to authenticated
  using(id=auth.uid() or public.is_platform_admin());
create policy phase1_profile_update on profiles for update to authenticated
  using(id=auth.uid()) with check(id=auth.uid());
create or replace function public.validate_profile_public_edit()
returns trigger language plpgsql set search_path=public as $$
begin
  if current_user in ('anon','authenticated') and
    (new.role,new.profile_version,new.onboarding_complete,new.date_of_birth,new.id)
      is distinct from (old.role,old.profile_version,old.onboarding_complete,old.date_of_birth,old.id) then
    raise exception 'PROTECTED_PROFILE_FIELDS' using errcode='42501';
  end if;
  if new.username is distinct from old.username then
    new.username:=lower(trim(new.username));
    if new.username is null or new.username !~ '^[a-z][a-z0-9_]{3,31}$' then raise exception 'INVALID_USERNAME'; end if;
  end if;
  if new.profile_version=1 and (nullif(trim(new.display_name),'') is null or new.gender is null) then
    raise exception 'INVALID_PROFILE';
  end if;
  return new;
end $$;
create trigger phase1_validate_profile before update on profiles for each row execute function validate_profile_public_edit();
-- Deliberate public projection; DOB, coordinates, role and credentials are omitted.
create view public.public_profiles as select id,username,display_name,first_name,last_name,avatar_url from public.profiles;
revoke all on public.public_profiles from public,anon;
grant select on public.public_profiles to authenticated;

revoke all on public.bookings,public.matches,public.match_players,public.reviews,public.arena_courts
  from public,anon,authenticated;
grant select on public.bookings,public.matches,public.match_players,public.reviews,public.arena_courts to authenticated;
grant select on public.matches,public.match_players,public.reviews,public.arena_courts to anon;
create policy phase1_bookings_read on bookings for select to authenticated
  using(user_id=auth.uid() or public.is_arena_operator(arena_id));
create policy phase1_matches_read on matches for select to anon,authenticated
  using(public.can_view_match(id));
create policy phase1_players_read on match_players for select to anon,authenticated
  using(public.can_view_match_player_row(match_id,user_id));
create policy phase1_reviews_read on reviews for select to anon,authenticated
  using(moderation_status='visible' or user_id=auth.uid() or public.is_arena_operator(arena_id));
create policy phase1_courts_read on arena_courts for select to anon,authenticated using(true);

revoke all on public.admin_users,public.owner_stadium_assignments from public,anon,authenticated;
grant select on public.admin_users,public.owner_stadium_assignments to authenticated;
grant insert,update,delete on public.owner_stadium_assignments to authenticated;
create policy phase1_admin_read on admin_users for select to authenticated using(user_id=auth.uid());
create policy phase1_assignments on owner_stadium_assignments for all to authenticated
  using(user_id=auth.uid() or public.is_platform_admin()) with check(public.is_platform_admin());
-- DELETE needs its own restrictive policy; FOR ALL using(user_id) would allow self-delete.
create policy phase1_assignments_write on owner_stadium_assignments as restrictive for delete to authenticated
  using(public.is_platform_admin());
create policy phase1_assignments_update on owner_stadium_assignments as restrictive for update to authenticated
  using(public.is_platform_admin()) with check(public.is_platform_admin());
revoke all on public.arenas from public,anon,authenticated;
grant select on public.arenas to anon,authenticated;
grant insert,update on public.arenas to authenticated;
create policy phase1_arenas_read on arenas for select to anon,authenticated
  using(is_active or public.is_arena_operator(id));
create policy phase1_arenas_insert on arenas for insert to authenticated with check(public.is_platform_admin());
create policy phase1_arenas_update on arenas for update to authenticated
  using(public.is_arena_operator(id)) with check(public.is_arena_operator(id));
create or replace function public.protect_arena_managed_fields()
returns trigger language plpgsql set search_path=public as $$
begin
  if current_user in ('anon','authenticated') then
    if (new.rating,new.review_count) is distinct from (old.rating,old.review_count) then raise exception 'SERVER_MANAGED_RATING'; end if;
    if new.owner_id is distinct from old.owner_id and not public.is_platform_admin() then raise exception 'ADMIN_ONLY_OWNER_ASSIGNMENT'; end if;
  end if;
  return new;
end $$;
create trigger phase1_protect_arena before update on arenas for each row execute function protect_arena_managed_fields();

do $$ begin if to_regclass('public.staff_login_accounts') is not null then
  revoke all on public.staff_login_accounts from public,anon,authenticated;
  grant select on public.staff_login_accounts to authenticated;
  create policy phase1_staff_read on public.staff_login_accounts for select to authenticated
    using(user_id=auth.uid() or public.is_platform_admin());
end if; end $$;
revoke all on function public.require_oman_user(),public.complete_my_profile(text,text,date,text,text),
  public.my_profile_complete(),public.my_staff_access() from public,anon,authenticated;
grant execute on function public.complete_my_profile(text,text,date,text,text),public.my_profile_complete(),public.my_staff_access() to authenticated;


-- EXISTING MIGRATION: 202609290002_phase1_inventory.sql
-- PHASE 1 / 2. One inventory for bookings, matches, manual bookings and blocks.
create extension if not exists btree_gist;
lock table public.arenas,public.arena_courts,public.bookings,public.matches in access exclusive mode;
create table if not exists public.blocked_slots(
  id uuid primary key default gen_random_uuid(),arena_id uuid not null references arenas(id),
  starts_at timestamptz not null,ends_at timestamptz not null check(ends_at>starts_at),
  reason text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now()
);
alter table blocked_slots add column if not exists court_id uuid references arena_courts(id);
alter table blocked_slots add column if not exists cancelled_at timestamptz;
lock table public.blocked_slots in access exclusive mode;
alter table bookings alter column user_id drop not null;
alter table bookings add column if not exists booking_type text not null default 'online';
alter table bookings add column if not exists customer_name text;
alter table bookings add column if not exists customer_phone text;
alter table bookings add column if not exists notes text;
alter table bookings drop constraint if exists bookings_status_check;
alter table bookings add constraint bookings_status_check check(status in('pending','confirmed','completed','upcoming','current','previous','cancelled'));
create table public.court_reservations(
  id uuid primary key default gen_random_uuid(),arena_id uuid not null references arenas(id),
  court_id uuid not null references arena_courts(id),source_type text not null check(source_type in('booking','match','block')),
  source_id uuid not null,starts_at timestamptz not null,ends_at timestamptz not null check(ends_at>starts_at),
  unique(source_type,source_id,court_id),
  constraint court_reservations_no_overlap exclude using gist(court_id with =,tstzrange(starts_at,ends_at,'[)') with &&)
);
create index court_reservations_arena_time_idx on court_reservations(arena_id,starts_at,ends_at);
create table public.inventory_migration_issues(
  source_type text not null,source_id uuid not null,arena_id uuid not null references arenas(id),
  starts_at timestamptz not null,ends_at timestamptz not null,reason text not null,
  created_at timestamptz not null default now(),resolved_at timestamptz,
  primary key(source_type,source_id)
);
create index inventory_issues_open_idx on inventory_migration_issues(arena_id,starts_at,ends_at) where resolved_at is null;
-- Unresolved legacy conflicts block the arena conservatively for ONLY their interval.
-- Operators must review them; no data is discarded and no extra courts are invented.
drop trigger if exists bookings_enforce_cross_inventory on bookings;
drop trigger if exists matches_enforce_cross_inventory on matches;
drop trigger if exists bookings_prevent_arena_time_conflict on bookings;
drop trigger if exists matches_prevent_arena_time_conflict on matches;
do $$ declare r record;c record;v_court uuid;v_ok boolean; begin
  for r in select 'booking'::text kind,id,arena_id,court_id,starts_at,ends_at from bookings where status<>'cancelled'
    union all select 'match',id,arena_id,court_id,starts_at,ends_at from matches where status<>'cancelled'
    order by starts_at,id loop
    select ac.id into v_court from arena_courts ac where ac.arena_id=r.arena_id
      and (ac.id=r.court_id or (r.court_id is null and ac.is_active))
      and not exists(select 1 from court_reservations x where x.court_id=ac.id and x.starts_at<r.ends_at and x.ends_at>r.starts_at)
      order by ac.court_number limit 1;
    if v_court is null then
      insert into inventory_migration_issues values(r.kind,r.id,r.arena_id,r.starts_at,r.ends_at,'NO_NON_OVERLAPPING_COURT',now(),null);
    else
      insert into court_reservations(arena_id,court_id,source_type,source_id,starts_at,ends_at)
        values(r.arena_id,v_court,r.kind,r.id,r.starts_at,r.ends_at);
      if r.kind='booking' then update bookings set court_id=v_court where id=r.id and court_id is null;
      else update matches set court_id=v_court where id=r.id and court_id is null; end if;
    end if;
  end loop;
  for r in select * from blocked_slots where cancelled_at is null order by starts_at,id loop
    v_ok:=false;
    begin
      for c in select id from arena_courts where arena_id=r.arena_id and ((r.court_id is null and is_active) or id=r.court_id) loop
        insert into court_reservations(arena_id,court_id,source_type,source_id,starts_at,ends_at)
          values(r.arena_id,c.id,'block',r.id,r.starts_at,r.ends_at);
        v_ok:=true;
      end loop;
      if not v_ok then raise exception 'NO_COURTS'; end if;
    exception when exclusion_violation or raise_exception then
      insert into inventory_migration_issues values('block',r.id,r.arena_id,r.starts_at,r.ends_at,'BLOCK_REQUIRES_REVIEW',now(),null);
    end;
  end loop;
end $$;

create or replace function public.arena_accepts_time_range(p_arena_id uuid,p_starts_at timestamptz,p_ends_at timestamptz)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare a arenas%rowtype;s timestamp:=p_starts_at at time zone 'Asia/Muscat';e timestamp:=p_ends_at at time zone 'Asia/Muscat';ws timestamp;we timestamp;
begin
  if p_starts_at is null or p_ends_at is null or p_ends_at<=p_starts_at or p_ends_at-p_starts_at>interval '12 hours' then return false; end if;
  select * into a from arenas where id=p_arena_id and is_active;
  if not found or a.opening_time is null or a.closing_time is null then return false; end if;
  if a.opening_time=a.closing_time then return true; end if;
  ws:=s::date+a.opening_time;we:=s::date+a.closing_time;
  if a.closing_time<a.opening_time then
    if s::time<a.closing_time then ws:=ws-interval '1 day';else we:=we+interval '1 day';end if;
  end if;
  return s>=ws and e<=we;
end $$;

create or replace function public.arena_has_available_court(p_arena_id uuid,p_starts_at timestamptz,p_ends_at timestamptz)
returns boolean language sql stable security definer set search_path=public as $$
  select p_starts_at>now() and public.arena_accepts_time_range(p_arena_id,p_starts_at,p_ends_at)
    and not exists(select 1 from inventory_migration_issues i where i.arena_id=p_arena_id and i.resolved_at is null and i.starts_at<p_ends_at and i.ends_at>p_starts_at)
    and exists(select 1 from arena_courts c where c.arena_id=p_arena_id and c.is_active
      and not exists(select 1 from court_reservations r where r.court_id=c.id and r.starts_at<p_ends_at and r.ends_at>p_starts_at));
$$;

create function public.arena_availability(p_arena_id uuid,p_from date,p_to date)
returns table(starts_at timestamptz,ends_at timestamptz,available boolean)
language plpgsql stable security definer set search_path=public as $$
begin
  if p_to<=p_from or p_to-p_from>32 then raise exception 'INVALID_AVAILABILITY_WINDOW';end if;
  return query select s,s+interval '30 minutes',public.arena_has_available_court(p_arena_id,s,s+interval '30 minutes')
    from generate_series(p_from::timestamp at time zone 'Asia/Muscat',p_to::timestamp at time zone 'Asia/Muscat'-interval '30 minutes',interval '30 minutes') s;
end $$;
-- Compatibility: raw occupied intervals, without destructive hour rounding.
-- Updated apps use arena_availability + whole-range arena_has_available_court.
create or replace function public.arena_busy_intervals(p_arena_id uuid,p_from timestamptz,p_to timestamptz)
returns table(starts_at timestamptz,ends_at timestamptz)
language sql stable security definer set search_path=public as $$
  select s,s+interval '30 minutes' from generate_series(p_from,least(p_to,p_from+interval '32 days')-interval '30 minutes',interval '30 minutes') s
  where not public.arena_has_available_court(p_arena_id,s,s+interval '30 minutes');
$$;

create function arena_private.allocate_court(p_arena uuid,p_start timestamptz,p_end timestamptz)
returns uuid language plpgsql set search_path=public as $$
declare v_id uuid;begin
  perform pg_advisory_xact_lock(hashtextextended(p_arena::text,0));
  perform 1 from arenas where id=p_arena for share;
  if not public.arena_has_available_court(p_arena,p_start,p_end) then raise exception 'TIME_NO_LONGER_AVAILABLE';end if;
  select c.id into v_id from arena_courts c where c.arena_id=p_arena and c.is_active
    and not exists(select 1 from court_reservations r where r.court_id=c.id and r.starts_at<p_end and r.ends_at>p_start)
    order by c.court_number limit 1 for update;
  return v_id;
end $$;

create function public.sync_court_inventory()
returns trigger language plpgsql security definer set search_path=public as $$
declare kind text;v_active boolean;c record;v_found boolean:=false;begin
  kind:=case tg_table_name when 'bookings' then 'booking' when 'matches' then 'match' else 'block' end;
  if tg_op='DELETE' then
    perform pg_advisory_xact_lock(hashtextextended(old.arena_id::text,0));
    delete from court_reservations where source_type=kind and source_id=old.id;
    update inventory_migration_issues set resolved_at=now() where source_type=kind and source_id=old.id;
    return old;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(new.arena_id::text,0));
  if kind='block' then v_active:=new.cancelled_at is null;else v_active:=new.status<>'cancelled';end if;
  delete from court_reservations where source_type=kind and source_id=new.id;
  if v_active then
    if kind<>'block' and new.court_id is null then raise exception 'COURT_REQUIRED';end if;
    for c in select * from arena_courts where arena_id=new.arena_id and ((kind='block' and new.court_id is null and is_active) or id=new.court_id) loop
      insert into court_reservations(arena_id,court_id,source_type,source_id,starts_at,ends_at)
        values(new.arena_id,c.id,kind,new.id,new.starts_at,new.ends_at);
      v_found:=true;
    end loop;
    if not v_found then raise exception 'INVALID_COURT';end if;
  end if;
  update inventory_migration_issues set resolved_at=now() where source_type=kind and source_id=new.id and resolved_at is null;
  return new;
end $$;
create trigger phase1_booking_inventory after insert or update of arena_id,court_id,starts_at,ends_at,status on bookings for each row execute function sync_court_inventory();
create trigger phase1_match_inventory after insert or update of arena_id,court_id,starts_at,ends_at,status on matches for each row execute function sync_court_inventory();
create trigger phase1_block_inventory after insert or update of arena_id,court_id,starts_at,ends_at,cancelled_at on blocked_slots for each row execute function sync_court_inventory();
create trigger phase1_booking_inventory_delete after delete on bookings for each row execute function sync_court_inventory();
create trigger phase1_match_inventory_delete after delete on matches for each row execute function sync_court_inventory();
create trigger phase1_block_inventory_delete after delete on blocked_slots for each row execute function sync_court_inventory();

create table arena_private.requests(
  user_id uuid not null,request_key uuid not null,operation text not null,payload jsonb not null,result jsonb,
  primary key(user_id,request_key)
);
create function arena_private.begin_request(p_key uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql set search_path=public as $$
declare r arena_private.requests%rowtype;begin
  if auth.uid() is null or p_key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':'||p_key::text,0));
  select * into r from arena_private.requests where user_id=auth.uid() and request_key=p_key;
  if found then
    if r.operation<>p_operation or r.payload<>p_payload then raise exception 'IDEMPOTENCY_PAYLOAD_MISMATCH';end if;
    return r.result;
  end if;
  insert into arena_private.requests values(auth.uid(),p_key,p_operation,p_payload,null);
  return null;
end $$;

create or replace function public.create_arena_booking_with_coupon(
  p_arena_id uuid,p_starts_at timestamptz,p_ends_at timestamptz,p_water_cartons integer,p_idempotency_key uuid,p_coupon_id uuid default null
) returns table(booking_id uuid,court_id uuid,court_number integer,total_price numeric,discount_amount numeric)
language plpgsql security definer set search_path=public as $$
declare v_user uuid:=public.require_oman_user();v_court uuid;v_number integer;v_price numeric;v_total numeric;v_discount numeric:=0;v_id uuid;v_coupon reward_coupons%rowtype;v_result jsonb;v_old bookings%rowtype;
begin
  if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
  v_result:=arena_private.begin_request(p_idempotency_key,'booking',jsonb_build_array(p_arena_id,p_starts_at,p_ends_at,p_water_cartons,p_coupon_id));
  if v_result is not null then return query select * from jsonb_to_record(v_result) as x(booking_id uuid,court_id uuid,court_number integer,total_price numeric,discount_amount numeric);return;end if;
  -- Backwards-compatible retry for an operation committed before this migration.
  select * into v_old from bookings b where b.user_id=v_user and b.idempotency_key=p_idempotency_key;
  if found then
    if (v_old.arena_id,v_old.starts_at,v_old.ends_at,v_old.water_cartons,v_old.coupon_id) is distinct from (p_arena_id,p_starts_at,p_ends_at,p_water_cartons,p_coupon_id) then raise exception 'IDEMPOTENCY_PAYLOAD_MISMATCH';end if;
    return query select v_old.id,v_old.court_id,c.court_number,v_old.total_price,v_old.discount_amount from arena_courts c where c.id=v_old.court_id;return;
  end if;
  if p_water_cartons is null or p_water_cartons<0 then raise exception 'INVALID_WATER_QUANTITY';end if;
  if not exists(select 1 from profiles p join arenas a on a.id=p_arena_id where p.id=v_user and p.gender=a.audience_gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
  v_court:=arena_private.allocate_court(p_arena_id,p_starts_at,p_ends_at);
  select a.price_per_hour,c.court_number into v_price,v_number from arenas a join arena_courts c on c.arena_id=a.id where c.id=v_court;
  v_total:=round(v_price*extract(epoch from(p_ends_at-p_starts_at))/3600+p_water_cartons*0.500,3);
  if p_coupon_id is not null then
    select * into v_coupon from reward_coupons where id=p_coupon_id and user_id=v_user and status='available' for update;
    if not found then raise exception 'COUPON_NOT_AVAILABLE';end if;
    v_discount:=least(v_total,v_coupon.value_omr);v_total:=v_total-v_discount;
  end if;
  insert into bookings(user_id,arena_id,court_id,starts_at,ends_at,total_price,status,water_cartons,water_unit_price,idempotency_key,coupon_id,discount_amount)
    values(v_user,p_arena_id,v_court,p_starts_at,p_ends_at,v_total,'upcoming',p_water_cartons,0.500,p_idempotency_key,p_coupon_id,v_discount) returning id into v_id;
  if p_coupon_id is not null then update reward_coupons set status='used',used_booking_id=v_id,used_at=now() where id=p_coupon_id;end if;
  v_result:=jsonb_build_object('booking_id',v_id,'court_id',v_court,'court_number',v_number,'total_price',v_total,'discount_amount',v_discount);
  update arena_private.requests set result=v_result where user_id=v_user and request_key=p_idempotency_key;
  return query select v_id,v_court,v_number,v_total,v_discount;
end $$;
create or replace function public.create_arena_booking(p_arena_id uuid,p_starts_at timestamptz,p_ends_at timestamptz,p_water_cartons integer default 0,p_idempotency_key uuid default gen_random_uuid())
returns table(booking_id uuid,court_id uuid,court_number integer,total_price numeric)
language sql security definer set search_path=public as $$
  select booking_id,court_id,court_number,total_price from public.create_arena_booking_with_coupon(p_arena_id,p_starts_at,p_ends_at,p_water_cartons,p_idempotency_key,null);
$$;

create or replace function public.create_arena_match(p_arena_id uuid,p_name text,p_description text,p_rules text,p_sport text,p_starts_at timestamptz,p_ends_at timestamptz,p_max_players integer,p_is_private boolean,p_show_joined_players boolean,p_payment_method text,p_idempotency_key uuid)
returns table(match_id uuid,court_id uuid,court_number integer)
language plpgsql security definer set search_path=public as $$
declare v_user uuid:=public.require_oman_user();v_court uuid;v_number integer;v_id uuid;v_gender text;v_price numeric;v_result jsonb;
begin
  if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
  v_result:=arena_private.begin_request(p_idempotency_key,'match',jsonb_build_array(p_arena_id,p_name,p_description,p_rules,p_sport,p_starts_at,p_ends_at,p_max_players,p_is_private,p_show_joined_players,p_payment_method));
  if v_result is not null then return query select * from jsonb_to_record(v_result) as x(match_id uuid,court_id uuid,court_number integer);return;end if;
  if nullif(trim(p_name),'') is null or p_max_players is null or p_max_players<2 or p_payment_method is null or p_payment_method not in('cash','card') then raise exception 'INVALID_MATCH';end if;
  select gender into v_gender from profiles where id=v_user;
  if not exists(select 1 from arenas where id=p_arena_id and audience_gender=v_gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
  v_court:=arena_private.allocate_court(p_arena_id,p_starts_at,p_ends_at);
  select a.price_per_hour,c.court_number into v_price,v_number from arenas a join arena_courts c on c.arena_id=a.id where c.id=v_court;
  insert into matches(arena_id,court_id,host_id,name,description,rules,sport,starts_at,ends_at,max_players,price_per_player,gender,payment_method,show_joined_players,is_private,status,idempotency_key)
    values(p_arena_id,v_court,v_user,trim(p_name),p_description,p_rules,p_sport,p_starts_at,p_ends_at,p_max_players,round(v_price*extract(epoch from(p_ends_at-p_starts_at))/3600/p_max_players,3),v_gender,p_payment_method,p_show_joined_players,p_is_private,'upcoming',p_idempotency_key) returning id into v_id;
  insert into match_players(match_id,user_id,status) values(v_id,v_user,'joined');
  v_result:=jsonb_build_object('match_id',v_id,'court_id',v_court,'court_number',v_number);
  update arena_private.requests set result=v_result where user_id=v_user and request_key=p_idempotency_key;
  return query select v_id,v_court,v_number;
end $$;

create function public.owner_reserve(p_arena uuid,p_start timestamptz,p_end timestamptz,p_name text,p_phone text,p_notes text,p_block boolean,p_request_key uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_court uuid;v_id uuid;v_result jsonb;begin
  if not public.is_arena_operator(p_arena) then raise exception 'NOT_AUTHORIZED' using errcode='42501';end if;
  v_result:=arena_private.begin_request(p_request_key,'owner_reserve',jsonb_build_array(p_arena,p_start,p_end,p_name,p_phone,p_notes,p_block));
  if v_result is not null then return (v_result->>'id')::uuid;end if;
  v_court:=arena_private.allocate_court(p_arena,p_start,p_end);
  if p_block then
    if nullif(trim(p_notes),'') is null then raise exception 'REASON_REQUIRED';end if;
    insert into blocked_slots(arena_id,court_id,starts_at,ends_at,reason,created_by) values(p_arena,v_court,p_start,p_end,p_notes,auth.uid()) returning id into v_id;
  else
    if nullif(trim(p_name),'') is null then raise exception 'CUSTOMER_NAME_REQUIRED';end if;
    insert into bookings(arena_id,court_id,starts_at,ends_at,total_price,status,booking_type,customer_name,customer_phone,notes,idempotency_key)
      select p_arena,v_court,p_start,p_end,round(price_per_hour*extract(epoch from(p_end-p_start))/3600,3),'confirmed','manual',p_name,p_phone,p_notes,p_request_key from arenas where id=p_arena returning id into v_id;
  end if;
  update arena_private.requests set result=jsonb_build_object('id',v_id) where user_id=auth.uid() and request_key=p_request_key;
  return v_id;
end $$;
create or replace function public.owner_create_manual_booking(p_arena uuid,p_start timestamptz,p_end timestamptz,p_name text,p_phone text,p_notes text default null)
returns uuid language sql security definer set search_path=public as $$ select public.owner_reserve(p_arena,p_start,p_end,p_name,p_phone,p_notes,false,gen_random_uuid()); $$;
-- Old owner "block time" meant the entire arena. Keep that meaning safely.
create or replace function public.owner_block_slot(p_arena uuid,p_start timestamptz,p_end timestamptz,p_reason text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;begin
  if not public.is_arena_operator(p_arena) then raise exception 'NOT_AUTHORIZED';end if;
  perform pg_advisory_xact_lock(hashtextextended(p_arena::text,0));
  if p_start<=now() or not public.arena_accepts_time_range(p_arena,p_start,p_end) then raise exception 'INVALID_TIME_RANGE';end if;
  if exists(select 1 from inventory_migration_issues where arena_id=p_arena and resolved_at is null and starts_at<p_end and ends_at>p_start) then raise exception 'INVENTORY_REQUIRES_REVIEW';end if;
  insert into blocked_slots(arena_id,starts_at,ends_at,reason,created_by) values(p_arena,p_start,p_end,p_reason,auth.uid()) returning id into v_id;return v_id;
end $$;
create or replace function public.owner_cancel_booking(p_booking uuid,p_reason text)
returns void language sql security definer set search_path=public as $$ select public.cancel_arena_booking(p_booking,p_reason); $$;
create function public.owner_cancel_block(p_block uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  update blocked_slots set cancelled_at=now() where id=p_block and public.is_arena_operator(arena_id);
  if not found then raise exception 'NOT_AUTHORIZED';end if;
end $$;
create function public.resolve_inventory_issue(p_type text,p_id uuid,p_court uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_platform_admin() then raise exception 'ADMIN_ONLY';end if;
  if p_type='booking' then update bookings set court_id=p_court where id=p_id;
  elsif p_type='match' then update matches set court_id=p_court where id=p_id;
  elsif p_type='block' then update blocked_slots set court_id=p_court where id=p_id;
  else raise exception 'INVALID_SOURCE';end if;
end $$;

alter table court_reservations enable row level security;
alter table inventory_migration_issues enable row level security;
alter table blocked_slots enable row level security;
do $$ declare r record;begin for r in select policyname from pg_policies where schemaname='public' and tablename='blocked_slots' loop execute format('drop policy %I on blocked_slots',r.policyname);end loop;end $$;
revoke all on court_reservations,inventory_migration_issues,blocked_slots from public,anon,authenticated;
grant select on court_reservations,inventory_migration_issues,blocked_slots to authenticated;
create policy phase1_inventory_staff on court_reservations for select to authenticated using(public.is_arena_operator(arena_id));
create policy phase1_inventory_issues on inventory_migration_issues for select to authenticated using(public.is_platform_admin());
create policy phase1_blocks_staff on blocked_slots for select to authenticated using(public.is_arena_operator(arena_id));
revoke all on all tables in schema arena_private from public,anon,authenticated;
revoke all on all functions in schema arena_private from public,anon,authenticated;
revoke all on function public.arena_availability(uuid,date,date),public.owner_reserve(uuid,timestamptz,timestamptz,text,text,text,boolean,uuid),public.owner_cancel_block(uuid),public.resolve_inventory_issue(text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.arena_availability(uuid,date,date),public.arena_has_available_court(uuid,timestamptz,timestamptz) to anon,authenticated;
grant execute on function public.owner_reserve(uuid,timestamptz,timestamptz,text,text,text,boolean,uuid),public.owner_cancel_block(uuid),public.resolve_inventory_issue(text,uuid,uuid) to authenticated;


-- EXISTING MIGRATION: 202609290003_phase1_rpc_boundaries.sql
-- PHASE 1 / 3. Complete RPC authorization and legacy compatibility.
create or replace function public.join_match(match_id uuid,target_user_id uuid default auth.uid())
returns void language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;v_status text;v_user uuid:=public.require_oman_user();begin
  if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
  select * into m from matches where id=join_match.match_id and status<>'cancelled' and starts_at>now() for update;
  if not found then raise exception 'MATCH_NOT_FOUND';end if;
  if target_user_id is null or (target_user_id<>v_user and m.host_id<>v_user) then raise exception 'HOST_ONLY_INVITE';end if;
  if not exists(select 1 from profiles where id=target_user_id and gender=m.gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
  select status into v_status from match_players where match_players.match_id=join_match.match_id and user_id=target_user_id;
  if v_status='joined' then return;end if;
  if target_user_id=v_user and m.is_private and m.host_id<>v_user and coalesce(v_status,'')<>'invited' then raise exception 'INVITATION_REQUIRED';end if;
  if (select count(*) from match_players where match_players.match_id=join_match.match_id and status='joined')>=m.max_players then raise exception 'MATCH_FULL';end if;
  insert into match_players(match_id,user_id,status) values(m.id,target_user_id,case when target_user_id=v_user then 'joined' else 'invited' end)
    on conflict on constraint match_players_pkey do update set status=excluded.status;
end $$;
create or replace function public.request_match_join(p_match_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;v_status text;v_user uuid:=public.require_oman_user();begin
  if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
  select * into m from matches where id=p_match_id and status<>'cancelled' and starts_at>now() for update;
  if not found then raise exception 'MATCH_NOT_FOUND';end if;
  select status into v_status from match_players where match_id=p_match_id and user_id=v_user;
  if v_status='joined' then return 'joined';end if;
  if not exists(select 1 from profiles where id=v_user and gender=m.gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
  if not m.is_private or m.host_id=v_user or v_status='invited' then
    perform public.join_match(p_match_id,v_user);return 'joined';
  end if;
  insert into match_players(match_id,user_id,status) values(p_match_id,v_user,'requested')
    on conflict on constraint match_players_pkey do update set status='requested';return 'requested';
end $$;
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
  update match_players set status=case when p_accept then 'joined' else 'rejected' end,joined_at=now()
    where match_id=p_match_id and user_id=p_user_id and status='requested';
  if not found then raise exception 'JOIN_REQUEST_NOT_FOUND';end if;
end $$;
create or replace function public.leave_match(match_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.require_oman_user();
  perform 1 from matches where id=leave_match.match_id for update;
  delete from match_players where match_players.match_id=leave_match.match_id and user_id=auth.uid();
end $$;

-- Inventory-aware reduction, including maintenance blocks and migration issues.
create or replace function public.sync_arena_courts_from_count()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.id::text,0));
  if tg_op='UPDATE' and new.court_count<old.court_count and (
    exists(select 1 from court_reservations r join arena_courts c on c.id=r.court_id
      where c.arena_id=new.id and c.court_number>new.court_count and r.ends_at>now())
    or exists(select 1 from inventory_migration_issues where arena_id=new.id and resolved_at is null and ends_at>now())
  ) then raise exception 'COURT_COUNT_HAS_ACTIVE_BOOKINGS';end if;
  insert into arena_courts(arena_id,court_number,label_ar,label_en,is_active)
    select new.id,n,'الملعب رقم '||n,'Court '||n,true from generate_series(1,new.court_count) n
    on conflict(arena_id,court_number) do update set is_active=true;
  update arena_courts set is_active=false where arena_id=new.id and court_number>new.court_count;
  -- Legacy arena-wide maintenance also covers newly activated courts.
  update blocked_slots set court_id=null where arena_id=new.id and court_id is null
    and cancelled_at is null and ends_at>now();
  return new;
end $$;

create or replace function public.notify_booking_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_court_number integer;
begin
  if new.user_id is null then return new; end if;
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
create or replace function public.award_completed_booking_points()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_balance integer; v_coupon_id uuid;
begin
  if new.user_id is null then return new; end if;
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

-- Remove default PUBLIC execute from every exposed definer/invoker function.
-- Existing app RPCs and policy helpers are explicitly allowlisted below.
do $$ declare r record;begin
  for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f'
      and not exists(select 1 from pg_depend d where d.objid=p.oid and d.deptype='e') loop
    execute format('revoke all on function %s from public,anon,authenticated',r.signature);
  end loop;
  for r in select p.oid::regprocedure signature,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=any(array[
      'is_platform_admin_user','is_platform_admin','is_stadium_owner_of','is_arena_operator',
      'can_view_match','can_view_match_players','can_view_match_player_row','is_chat_group_member',
      'my_staff_access','my_profile_complete','complete_my_profile','arena_availability','arena_busy_intervals',
      'arena_has_available_court','create_arena_booking','create_arena_booking_with_coupon','create_arena_match',
      'owner_reserve','owner_create_manual_booking','owner_block_slot','owner_cancel_booking','owner_cancel_block',
      'cancel_arena_booking','resolve_inventory_issue','join_match','request_match_join','respond_match_join_request',
      'leave_match','create_booking_review','moderate_arena_review','finalize_my_completed_events',
      'nearby_arenas','create_group_chat','consume_arena_assistant_rate_limit'
    ]) loop execute format('grant execute on function %s to authenticated',r.signature);end loop;
  for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=any(array['is_platform_admin_user','is_platform_admin','is_stadium_owner_of',
      'is_arena_operator','can_view_match','can_view_match_players','can_view_match_player_row',
      'arena_availability','arena_busy_intervals','arena_has_available_court']) loop
    execute format('grant execute on function %s to anon',r.signature);
  end loop;
end $$;
grant execute on function public.before_user_created_oman(jsonb) to supabase_auth_admin;


create table arena_private.staging_installation(version text primary key, source_sha256 text not null, applied_at timestamptz not null default now());
revoke all on arena_private.staging_installation from public,anon,authenticated;
insert into arena_private.staging_installation(version,source_sha256) values('202609290001','c5df7c788532b3e4cb73577468438237636af68fd32b4d3502222be69c5d2697');
insert into arena_private.staging_installation(version,source_sha256) values('202609290002','7e9670ae6f0ef899c32c11e28a732ee16c30d24414ac3c593d1149befbfa7660');
insert into arena_private.staging_installation(version,source_sha256) values('202609290003','a5ecdc68617cb704617ac6e72949d94e09755bcf9b9ef7f83cc22c606d4f0dab');
commit;
select version,source_sha256 from arena_private.staging_installation order by version;
