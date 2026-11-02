-- Named Staging only: legacy Cash/no-capture test fixture, never a fake paid match.
-- Existing modern Create Match remains Card only.
begin;
do $$ begin
 if not exists(select 1 from arena_private.staging_installation where version='202610090104') then raise exception 'HOST_POLICY_REQUIRED';end if;
 if exists(select 1 from matches where id='f3090000-0000-4000-8000-000000000004') then raise exception 'FIXTURE_ALREADY_EXISTS';end if;
end $$;
insert into matches(id,arena_id,court_id,host_id,name,sport,starts_at,ends_at,max_players,price_per_player,gender,status,payment_mode,payment_method,total_amount_baisa,is_private)
select 'f3090000-0000-4000-8000-000000000004','a1000000-0000-4000-8000-000000000002',
 arena_private.allocate_court('a1000000-0000-4000-8000-000000000002','2026-10-11 20:00+04','2026-10-11 21:00+04'),
 'dd11863b-c437-4e50-b612-94a2c2891ea8','Phase 3 private host cancellation test','football','2026-10-11 20:00+04','2026-10-11 21:00+04',5,2,'men','upcoming','host_pays_all','cash',10000,true;
insert into match_players(match_id,user_id,status) values
 ('f3090000-0000-4000-8000-000000000004','c1faaa2a-f829-46f0-ae35-9f095a01ef4f','joined'),
 ('f3090000-0000-4000-8000-000000000004','dd11863b-c437-4e50-b612-94a2c2891ea8','joined');
commit;
select id,name,status,payment_method,payment_mode,checkout_order_id,starts_at from matches where id='f3090000-0000-4000-8000-000000000004';


