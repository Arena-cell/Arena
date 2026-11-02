-- Staging gtcrijikfaglqcwqozel ONLY. Reviewed preflight before running once.
begin;
do $$ begin
 if not exists(select 1 from arena_private.staging_installation where version='202610090102') then raise exception 'REFUND_POLICY_BASELINE_REQUIRED';end if;
 if exists(select 1 from arena_private.staging_installation where version='202610090103') then raise exception 'HOST_POLICY_ALREADY_APPLIED';end if;
end $$;
create table arena_private.phase3_final_backup_20261009(kind text not null,row_key text not null,payload jsonb not null,captured_at timestamptz not null default now(),primary key(kind,row_key));
insert into arena_private.phase3_final_backup_20261009
 select 'matches',id::text,to_jsonb(m),now() from matches m union all
 select 'match_players',match_id::text||':'||user_id::text,to_jsonb(m),now() from match_players m union all
 select 'checkout_orders',id::text,to_jsonb(o),now() from checkout_orders o union all
 select 'payment_refunds',id::text,to_jsonb(r),now() from payment_refunds r union all
 select 'booking_addons',id::text,to_jsonb(a),now() from booking_addons a union all
 select 'arena_addons',id::text,to_jsonb(a),now() from arena_addons a union all
 select 'court_reservations',id::text,to_jsonb(r),now() from court_reservations r;
insert into arena_private.phase3_final_backup_20261009
 select 'function',p.oid::text,jsonb_build_object('identity',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid)),now()
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','arena_private') and p.prokind='f';
insert into arena_private.phase3_final_backup_20261009
 select 'constraint',oid::text,jsonb_build_object('table',conrelid::regclass::text,'name',conname,'definition',pg_get_constraintdef(oid)),now() from pg_constraint where conrelid in('matches'::regclass,'match_players'::regclass);
revoke all on arena_private.phase3_final_backup_20261009 from public,anon,authenticated;
commit;
select kind,count(*) from arena_private.phase3_final_backup_20261009 group by kind order by kind;
