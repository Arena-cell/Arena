-- PHASE 1 / 1. Requires the existing Arena v2 schema. Apply after preflight.
-- No existing users, profiles, bookings or matches are deleted.
begin;
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
commit;
