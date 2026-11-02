-- Security fixes only. Does not modify booking/payment/match policies.
begin;

-- CREATE OR REPLACE VIEW preserves old ACLs, including column privileges.
revoke all privileges on public.public_profiles from public, anon, authenticated;
do $$
declare col record;
begin
  for col in select attname from pg_attribute
    where attrelid='public.public_profiles'::regclass and attnum>0 and not attisdropped
  loop
    execute format('revoke all privileges (%I) on public.public_profiles from public, anon, authenticated',col.attname);
  end loop;
end $$;
grant select on public.public_profiles to authenticated;

-- Remove every legacy stadium write policy: permissive policies combine with OR.
drop policy if exists "owners upload stadium images" on storage.objects;
drop policy if exists "owners update stadium images" on storage.objects;
drop policy if exists "admins manage stadium image objects" on storage.objects;

create or replace function public.can_manage_stadium_image(p_object_name text)
returns boolean language plpgsql stable security definer
set search_path=pg_catalog,public,storage
as $$
declare parts text[]; arena uuid;
begin
  if auth.uid() is null then return false; end if;
  parts := storage.foldername(p_object_name);
  if coalesce(array_length(parts,1),0)<>2 then return false; end if;
  begin arena:=parts[2]::uuid;
  exception when invalid_text_representation then return false;
  end;
  if not exists(select 1 from public.arenas where id=arena) then return false; end if;
  if public.is_platform_admin() then return true; end if;
  return parts[1]=auth.uid()::text and public.is_stadium_owner_of(arena);
end $$;
revoke all on function public.can_manage_stadium_image(text) from public,anon;
grant execute on function public.can_manage_stadium_image(text) to authenticated,service_role;
create policy "authorized stadium image insert" on storage.objects for insert to authenticated
with check(bucket_id='stadium-images' and public.can_manage_stadium_image(name));
create policy "authorized stadium image update" on storage.objects for update to authenticated
using(bucket_id='stadium-images' and public.can_manage_stadium_image(name))
with check(bucket_id='stadium-images' and public.can_manage_stadium_image(name));
create policy "authorized stadium image delete" on storage.objects for delete to authenticated
using(bucket_id='stadium-images' and public.can_manage_stadium_image(name));

commit;
