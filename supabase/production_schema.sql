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
  audience_gender text not null default 'mixed' check (audience_gender in ('men','women','mixed')),
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
