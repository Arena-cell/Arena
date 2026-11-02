-- Phase 1 requirement change: phone + OTP only; no fixed account PIN.
-- Keep already-applied migrations immutable. Preserve existing private hashes
-- as inaccessible legacy data; no new hashes are written or consulted.
begin;
drop function if exists public.complete_my_profile(text,text,date,text,text);
create or replace function public.my_profile_complete()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from profiles p join auth.users u on u.id=p.id
    where p.id=auth.uid() and u.phone ~ '^\+?968[0-9]{8}$'
      and u.phone_confirmed_at is not null and p.profile_version=1
      and p.onboarding_complete and nullif(trim(p.display_name),'') is not null
      and p.username ~ '^[a-z][a-z0-9_]{3,31}$' and p.date_of_birth is not null
      and p.gender in ('men','women'));
$$;

create or replace function public.complete_my_profile(
  p_display_name text,p_username text,p_date_of_birth date,p_gender text
) returns void language plpgsql security definer set search_path=public,extensions as $$
declare v_id uuid:=public.require_oman_user(); v_username text:=lower(trim(p_username));
begin
  if char_length(trim(p_display_name)) not between 1 and 100 or p_display_name is null
    or v_username is null or v_username !~ '^[a-z][a-z0-9_]{3,31}$'
    or p_date_of_birth is null or p_date_of_birth>(now() at time zone 'Asia/Muscat')::date
    or p_date_of_birth<((now() at time zone 'Asia/Muscat')::date-interval '120 years')::date
    or p_gender is null or p_gender not in ('men','women') then
    raise exception 'INVALID_PROFILE';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('profile:'||v_id::text,0));
  if public.my_profile_complete() then raise exception 'PROFILE_ALREADY_COMPLETE'; end if;
  insert into profiles(id,display_name,username,date_of_birth,gender,first_name,last_name,onboarding_complete,profile_version)
    values(v_id,trim(p_display_name),v_username,p_date_of_birth,p_gender,trim(p_display_name),'',true,1)
    on conflict(id) do update set display_name=excluded.display_name,username=excluded.username,
      date_of_birth=excluded.date_of_birth,gender=excluded.gender,first_name=excluded.first_name,
      last_name=excluded.last_name,onboarding_complete=true,profile_version=1;
end $$;


revoke all on function public.complete_my_profile(text,text,date,text) from public,anon;
grant execute on function public.complete_my_profile(text,text,date,text) to authenticated;
notify pgrst, 'reload schema';
commit;
