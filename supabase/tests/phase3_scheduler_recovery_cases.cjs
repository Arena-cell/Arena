// Test-only database fault injection. Never deployed to Supabase.
module.exports=({sql,fixture,due,q,test,assert})=>{
 const bad=fixture(2,2),good=fixture(2,2);due(bad);due(good);
 sql(`create function arena_private.local_test_decision_failure() returns trigger language plpgsql as $$ begin if new.id=${q(bad)}::uuid and new.decision_outcome='confirmed' then raise exception 'LOCAL_TEST_FAILURE';end if;return new;end $$;
 create trigger local_test_decision_failure before update on matches for each row execute function arena_private.local_test_decision_failure();`);
 try{
  sql('select process_arena_scheduled_events()');
  test('One failed scheduled decision does not block other matches',()=>{assert.equal(sql(`select decision_outcome from matches where id=${q(good)}`),'confirmed');assert.equal(sql(`select decision_outcome||':'||decision_attempt_count||':'||(decision_next_attempt_at>now()) from matches where id=${q(bad)}`),'pending:1:true');});
  test('Failed scheduled job retained for Admin',()=>assert.equal(sql(`select count(*) from arena_scheduled_job_runs where failed_match_id=${q(bad)} and outcome='failed'`),'1'));
 }finally{sql('drop trigger local_test_decision_failure on matches;drop function arena_private.local_test_decision_failure()');}
 sql(`update matches set decision_next_attempt_at=now()-interval '1 minute' where id=${q(bad)};select process_arena_scheduled_events()`);
 test('Decision retry recovers after server failure',()=>assert.equal(sql(`select decision_outcome from matches where id=${q(bad)}`),'confirmed'));
};
