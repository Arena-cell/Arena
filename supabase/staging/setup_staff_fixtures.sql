-- Staging ONLY: gtcrijikfaglqcwqozel. Review project reference before execution.
-- Test staff access and two synthetic arenas; not a production migration.
begin;
do $$
begin
  if not exists(select 1 from arena_private.staging_installation where version='202609290003') then
    raise exception 'Missing staging installation receipt';
  end if;
  if (select count(*) from auth.users where
      (id='eac4c6b3-dc0f-42ab-a9e0-a4e8dc03fa34' and email='owner_stage@staff.playon.internal')
      or (id='f6b51893-1415-4c26-a7ca-bd2b4a9e231d' and email='admin_stage@staff.playon.internal')) <> 2 then
    raise exception 'Expected staging test identities not found';
  end if;
end $$;
insert into public.staff_login_accounts(user_id,username,account_type,active) values
 ('eac4c6b3-dc0f-42ab-a9e0-a4e8dc03fa34','owner_stage','owner',true),
 ('f6b51893-1415-4c26-a7ca-bd2b4a9e231d','admin_stage','admin',true)
on conflict(user_id) do update set username=excluded.username,account_type=excluded.account_type,active=true;
insert into public.admin_users(user_id,active)
values('f6b51893-1415-4c26-a7ca-bd2b4a9e231d',true)
on conflict(user_id) do update set active=true;
insert into public.arenas(id,owner_id,name,location,price_per_hour,opening_time,closing_time,court_count,is_active,audience_gender) values
 ('a1000000-0000-4000-8000-000000000001','eac4c6b3-dc0f-42ab-a9e0-a4e8dc03fa34','Staging Single Court','Muscat',10,'08:00','23:00',1,true,'men'),
 ('a1000000-0000-4000-8000-000000000002','eac4c6b3-dc0f-42ab-a9e0-a4e8dc03fa34','Staging Two Courts','Muscat',10,'08:00','23:00',2,true,'men')
on conflict(id) do nothing;
commit;
select username,account_type,active from public.staff_login_accounts
where user_id in ('eac4c6b3-dc0f-42ab-a9e0-a4e8dc03fa34','f6b51893-1415-4c26-a7ca-bd2b4a9e231d');
