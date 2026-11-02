-- Execute ONLY in Dashboard project gtcrijikfaglqcwqozel after identity/preflight.
-- Private in-project recovery snapshot; not a substitute for off-project PITR.
begin;
create table arena_private.phase3_backup_20261008(
 object_name text not null,record jsonb not null,captured_at timestamptz not null default now());
do $$ declare t text;begin
 foreach t in array array['matches','match_players','bookings','court_reservations','checkout_orders','payment_refunds','notifications','notification_push_deliveries','device_tokens'] loop
  execute format('insert into arena_private.phase3_backup_20261008(object_name,record) select %L,to_jsonb(t) from public.%I t',t,t);
 end loop;
 insert into arena_private.phase3_backup_20261008(object_name,record)
 select 'function',jsonb_build_object('name',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid))
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','arena_private') and p.prokind='f';
 insert into arena_private.phase3_backup_20261008(object_name,record)
 select 'constraint',jsonb_build_object('table',conrelid::regclass::text,'name',conname,'definition',pg_get_constraintdef(oid))
 from pg_constraint where conrelid in('matches'::regclass,'match_players'::regclass,'notifications'::regclass);
end $$;
revoke all on arena_private.phase3_backup_20261008 from public,anon,authenticated;
commit;
select object_name,count(*) from arena_private.phase3_backup_20261008 group by object_name order by object_name;
