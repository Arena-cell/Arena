-- ONLY arena-staging gtcrijikfaglqcwqozel. Confirm Dashboard URL before running.
begin;
do $$ begin
 if to_regclass('arena_private.staging_installation') is null or
    (select count(*) from arena_private.staging_installation where version in('202609290001','202609290002','202609290003'))<>3 then raise exception 'STAGING_RECEIPTS_REQUIRED';end if;
 if to_regclass('public.checkout_orders') is not null then raise exception 'PHASE2_ALREADY_PRESENT';end if;
 if exists(select 1 from public.inventory_migration_issues where resolved_at is null) then raise exception 'UNRESOLVED_INVENTORY';end if;
 if exists(select 1 from public.bookings where payment_status<>'unpaid') then raise exception 'HISTORICAL_FINANCIAL_REVIEW_REQUIRED';end if;
end $$;
create table arena_private.phase2_backup_20261004 (
 id bigint generated always as identity primary key,
 object_name text not null, snapshot jsonb not null, captured_at timestamptz not null default now()
);
revoke all on arena_private.phase2_backup_20261004 from public,anon,authenticated;
insert into arena_private.phase2_backup_20261004(object_name,snapshot)
 select 'bookings',to_jsonb(b) from public.bookings b union all
 select 'matches',to_jsonb(m) from public.matches m union all
 select 'match_players',to_jsonb(p) from public.match_players p union all
 select 'reward_coupons',to_jsonb(c) from public.reward_coupons c;
insert into arena_private.phase2_backup_20261004(object_name,snapshot)
 select 'function:'||p.oid::regprocedure::text,jsonb_build_object('definition',pg_get_functiondef(p.oid))
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f';
insert into arena_private.phase2_backup_20261004(object_name,snapshot)
 select 'constraint:'||conname,jsonb_build_object('table',conrelid::regclass::text,'definition',pg_get_constraintdef(oid))
 from pg_constraint where conrelid in('public.bookings'::regclass,'public.matches'::regclass,'public.match_players'::regclass);
commit;
select split_part(object_name,':',1) object_kind,count(*) snapshots from arena_private.phase2_backup_20261004 group by 1 order by 1;
