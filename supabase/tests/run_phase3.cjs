// Real loopback PostgreSQL, authenticated roles and concurrent clients.
// No provider fakes or fixture migrations are ever sent to hosted Supabase.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
process.chdir(require('node:path').resolve(__dirname,'../..'));
const db=fs.readFileSync('build/phase1-test-db.txt','utf8').trim();
if(!/^arena_phase1_test_\d+$/.test(db))throw Error('Local database required');
const exe='C:/Program Files/PostgreSQL/18/bin/psql.exe';
const args=['-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-qAt'];
function sql(s){try{return cp.execFileSync(exe,args,{input:s,encoding:'utf8',stdio:['pipe','pipe','pipe']}).trim();}catch(e){throw Error(e.stderr.toString());}}
const q=s=>`'${String(s).replaceAll("'","''")}'`;
const uid=n=>`30000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const as=(n,s)=>`set role authenticated;set request.jwt.claim.sub=${q(uid(n))};${s}`;
const run=(n,s)=>sql(as(n,s));
const parallel=ss=>Promise.all(ss.map(s=>new Promise(resolve=>{let error='';const p=cp.spawn(exe,args);p.stdout.resume();p.stderr.on('data',d=>error+=d);p.on('close',code=>resolve({ok:code===0,error}));p.stdin.end(s);}))); 
let checks=0;function test(name,f){f();checks++;console.log('PASS '+name);}
function fixture(capacity,joined){
 const a=crypto.randomUUID(),m=crypto.randomUUID();
 sql(`insert into arenas(id,name,location,price_per_hour,opening_time,closing_time,court_count,audience_gender,is_active) values(${q(a)},'Phase3 local','Muscat',10,'00:00','23:59',1,'men',true);
 insert into matches(id,arena_id,court_id,host_id,name,sport,starts_at,ends_at,max_players,price_per_player,gender,status)
 select ${q(m)},${q(a)},id,${q(uid(1))},'Phase3 local','football',now()+interval '3 hours',now()+interval '4 hours',${capacity},1,'men','upcoming' from arena_courts where arena_id=${q(a)};
 insert into match_players(match_id,user_id,status) select ${q(m)},id,'joined' from auth.users where id in(${Array.from({length:joined},(_,i)=>q(uid(i+1))).join(',')||'null'});`);
 return m;
}
const due=m=>sql(`update matches set starts_at=now()+interval '80 minutes',ends_at=now()+interval '140 minutes' where id=${q(m)}`);
const decide=m=>sql(`select arena_private.decide_match(${q(m)})`);
(async()=>{try{
 assert.ok(sql('show data_directory').replaceAll('\\','/').toLowerCase().endsWith('/playon/build/phase1-pgdata'));
 for(let n=1;n<=101;n++){
  sql(`insert into auth.users(id,phone,phone_confirmed_at) values(${q(uid(n))},${q('96893'+String(n).padStart(6,'0'))},now())`);
  run(n,`select complete_my_profile('Phase3 Player','phase3_user_${n}','2000-01-01','men')`);
 }
 for(const [cap,n,expected] of [[100,79,'cancelled'],[100,80,'confirmed'],[10,10,'confirmed'],[10,0,'cancelled'],[5,4,'confirmed'],[12,9,'cancelled'],[12,10,'confirmed'],[14,11,'cancelled'],[14,12,'confirmed'],[20,16,'confirmed']]){
  const m=fixture(cap,n);due(m);
  test(`${n}/${cap} -> ${expected}`,()=>assert.equal(decide(m),expected));
  test('Repeated decision is final '+cap+'/'+n,()=>assert.equal(decide(m),expected));
  if(expected==='cancelled')test('Cancellation releases court '+cap+'/'+n,()=>assert.equal(sql(`select count(*) from court_reservations where source_id=${q(m)}`),'0'));
 }
 const m=fixture(10,8);due(m);decide(m);
 test('Confirmed withdrawal denied by RPC',()=>assert.throws(()=>run(2,`select leave_match(${q(m)})`),/WITHDRAWAL_LOCKED/));
 test('Legacy definer direct delete guarded',()=>assert.throws(()=>sql(`delete from match_players where match_id=${q(m)} and user_id=${q(uid(2))}`),/WITHDRAWAL_LOCKED/));
 test('Legacy status edit cannot reverse final decision',()=>assert.throws(()=>sql(`update matches set status='cancelled' where id=${q(m)}`),/FINAL_MATCH_DECISION/));
 test('New player may join after confirmation',()=>{run(9,`select join_match(${q(m)},${q(uid(9))})`);assert.equal(sql(`select count(*) from match_players where match_id=${q(m)} and status='joined'`),'9');});
 test('Join does not change final snapshot',()=>assert.equal(sql(`select decision_joined_count from matches where id=${q(m)}`),'8'));
 for(const statement of [`update matches set status='confirmed' where id=${q(m)}`,`delete from match_players where match_id=${q(m)}`,`insert into notifications(user_id,type,title,body) values(${q(uid(2))},'match_confirmed','Fake','Fake')`,`select process_arena_scheduled_events()`])
  test('Authenticated direct write/job denied',()=>assert.throws(()=>run(1,statement),/permission denied/));
 const delayed=fixture(5,4);sql(`update matches set starts_at=now()-interval '5 minutes',ends_at=now()+interval '55 minutes' where id=${q(delayed)}`);
 test('Delayed scheduler catches missed cutoff',()=>{sql('select process_arena_scheduled_events()');assert.equal(sql(`select decision_outcome from matches where id=${q(delayed)}`),'confirmed');});
 test('Joining after start rejected',()=>assert.throws(()=>run(5,`select join_match(${q(delayed)},${q(uid(5))})`),/MATCH_NOT_FOUND|MATCH_UNAVAILABLE/));
 test('Late match reminder survives outage',()=>assert.equal(sql(`select count(*) from notifications where data->>'match_id'=${q(delayed)} and type='match_reminder'`),'4'));
 test('Repeated scheduler does not duplicate notifications',()=>{const before=sql('select count(*) from notifications');sql('select process_arena_scheduled_events()');assert.equal(sql('select count(*) from notifications'),before);});
 const race=fixture(10,8);due(race);
 const rr=await parallel([`begin;select arena_private.decide_match(${q(race)});select pg_sleep(0.1);commit;`,as(2,`select leave_match(${q(race)})`),as(9,`select join_match(${q(race)},${q(uid(9))})`)]);
 test('Concurrent decision/join/leave stays consistent',()=>{assert.ok(rr[0].ok);assert.ok(!rr[1].ok);assert.ok(rr[2].ok);assert.equal(sql(`select decision_outcome||':'||decision_joined_count from matches where id=${q(race)}`),'confirmed:8');});
 // A pre-cutoff leave reduces eligibility without deleting its financial entitlement.
 const before=fixture(5,4);run(2,`select leave_match(${q(before)})`);due(before);
 test('Pre-cutoff leave excluded',()=>assert.equal(decide(before),'cancelled'));
 await require('./phase3_financial_cases.cjs')({sql,run,q,test,assert,uid,parallel});
 require('./phase3_booking_cases.cjs')({sql,fixture,q,test,assert,uid});
 require('./phase3_queue_cases.cjs')({sql,run,q,test,assert,uid});
 require('./phase3_scheduler_recovery_cases.cjs')({sql,fixture,due,q,test,assert});
 console.log(`${checks} Phase 3 PostgreSQL checks passed. Native push delivery is NOT TESTED.`);
}catch(e){console.error(e.message);process.exitCode=1;}})();
