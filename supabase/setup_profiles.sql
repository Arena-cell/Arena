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
