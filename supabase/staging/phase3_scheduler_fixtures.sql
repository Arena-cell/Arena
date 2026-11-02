-- STAGING ONLY: retained, labelled no-charge fixtures using real existing accounts.
-- No fake payment/refund states. Do not run twice after a final decision.
begin;
insert into matches(id,arena_id,court_id,host_id,name,description,sport,starts_at,ends_at,max_players,price_per_player,gender,status,is_private)
select 'f3000000-0000-4000-8000-000000000001',c.arena_id,c.id,'dd11863b-c437-4e50-b612-94a2c2891ea8',
 '[STAGING TEST] Phase3 scheduler confirmation','Server scheduling verification only. Legacy no-charge fixture; no provider payment.','football',
 now()+interval '3 hours',now()+interval '4 hours',2,0,'men','upcoming',true
from arena_courts c where c.arena_id='a1000000-0000-4000-8000-000000000002' and c.court_number=1;
insert into matches(id,arena_id,court_id,host_id,name,description,sport,starts_at,ends_at,max_players,price_per_player,gender,status,is_private)
select 'f3000000-0000-4000-8000-000000000002',c.arena_id,c.id,'dd11863b-c437-4e50-b612-94a2c2891ea8',
 '[STAGING TEST] Phase3 scheduler cancellation','Server scheduling verification only. Legacy no-charge fixture; no provider payment.','football',
 now()+interval '3 hours',now()+interval '4 hours',3,0,'men','upcoming',true
from arena_courts c where c.arena_id='a1000000-0000-4000-8000-000000000002' and c.court_number=2;
insert into match_players(match_id,user_id,status) values
 ('f3000000-0000-4000-8000-000000000001','dd11863b-c437-4e50-b612-94a2c2891ea8','joined'),
 ('f3000000-0000-4000-8000-000000000001','c1faaa2a-f829-46f0-ae35-9f095a01ef4f','joined'),
 ('f3000000-0000-4000-8000-000000000002','dd11863b-c437-4e50-b612-94a2c2891ea8','joined');
-- Simulate recovery of overdue work. Only the automatic Cron worker will decide.
update matches set starts_at=now()+interval '50 minutes',ends_at=now()+interval '110 minutes'
 where id in('f3000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000002');
commit;
select id,status,decision_at,decision_outcome from matches where id::text like 'f3000000-%';
