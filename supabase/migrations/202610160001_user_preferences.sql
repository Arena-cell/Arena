-- Optional push preferences never suppress the inbox or mandatory service events.
begin;
create table public.user_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  private_profile boolean not null default false,
  match_reminders boolean not null default true,
  booking_reminders boolean not null default true,
  chat_messages boolean not null default true,
  offers boolean not null default false,
  news boolean not null default false
);
alter table public.user_preferences enable row level security;
revoke all on public.user_preferences from public,anon,authenticated;
grant select,insert,update on public.user_preferences to authenticated;
create policy own_preferences on public.user_preferences for all to authenticated
  using(user_id=auth.uid()) with check(user_id=auth.uid());

create function public.set_my_preference(p_key text,p_value boolean) returns void
language plpgsql security invoker set search_path=public as $$
begin
 if auth.uid() is null or p_value is null or p_key not in
 ('private_profile','match_reminders','booking_reminders','chat_messages','offers','news') then
   raise exception 'INVALID_PREFERENCE' using errcode='22023';
 end if;
 insert into user_preferences(user_id) values(auth.uid()) on conflict do nothing;
 execute format('update public.user_preferences set %I=$1 where user_id=auth.uid()',p_key) using p_value;
end;
$$;
revoke all on function public.set_my_preference(text,boolean) from public,anon;
grant execute on function public.set_my_preference(text,boolean) to authenticated;

create function public.can_view_public_profile(p_user uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select auth.uid() is not null and (
   auth.uid()=p_user or public.is_platform_admin()
   or not coalesce((select private_profile from user_preferences where user_id=p_user),false)
   or exists(select 1 from bookings b where b.user_id=p_user and public.is_stadium_owner_of(b.arena_id))
   or exists(select 1 from match_players mp join matches m on m.id=mp.match_id
       where mp.user_id=p_user and public.is_stadium_owner_of(m.arena_id))
 );
$$;
revoke all on function public.can_view_public_profile(uuid) from public,anon;
grant execute on function public.can_view_public_profile(uuid) to authenticated;
create or replace view public.public_profiles with (security_barrier=true) as
 select id,username,display_name,first_name,last_name,avatar_url from public.profiles
 where public.can_view_public_profile(id);
commit;
