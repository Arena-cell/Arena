-- Named Staging only: legacy Cash/no-capture test fixture, never a fake paid match.
-- Existing modern Create Match remains Card only.
begin;
do $$ begin
 if not exists(select 1 from arena_private.staging_installation where version='202610090103') then raise exception 'HOST_POLICY_REQUIRED';end if;
 if exists(select 1 from matches where id='f3090000-0000-4000-8000-000000000003') then raise exception 'FIXTURE_ALREADY_EXISTS';end if;
end $$;
insert into matches(id,arena_id,court_id,host_id,name,sport,starts_at,ends_at,max_players,price_per_player,gender,status,payment_mode,payment_method,total_amount_baisa)
select 'f3090000-0000-4000-8000-000000000003','a1000000-0000-4000-8000-000000000002',
 arena_private.allocate_court('a1000000-0000-4000-8000-000000000002','2026-10-11 18:00+04','2026-10-11 19:00+04'),
 'c1faaa2a-f829-46f0-ae35-9f095a01ef4f','Phase 3 immediate cancellation refresh test','football','2026-10-11 18:00+04','2026-10-11 19:00+04',5,2,'men','upcoming','host_pays_all','cash',10000;
insert into match_players(match_id,user_id,status) values
 ('f3090000-0000-4000-8000-000000000003','c1faaa2a-f829-46f0-ae35-9f095a01ef4f','joined'),
 ('f3090000-0000-4000-8000-000000000003','dd11863b-c437-4e50-b612-94a2c2891ea8','joined');
commit;
select id,name,status,payment_method,payment_mode,checkout_order_id,starts_at from matches where id='f3090000-0000-4000-8000-000000000003';

