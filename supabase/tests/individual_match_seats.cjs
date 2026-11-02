// LOCAL PostgreSQL only. All provider confirmations and clock changes are test fakes.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const db=fs.readFileSync('build/phase1-test-db.txt','utf8').trim();assert.match(db,/^arena_phase1_test_\d+$/);
const exe='C:/Program Files/PostgreSQL/18/bin/psql.exe',args=['-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-qAt'];
const sql=s=>{try{return cp.execFileSync(exe,args,{input:s,encoding:'utf8',stdio:['pipe','pipe','pipe']}).trim()}catch(e){throw Error(e.stderr.toString())}};
assert(sql('show data_directory').replaceAll('\\','/').endsWith('/playon/build/phase1-pgdata'));
const q=s=>`'${String(s).replaceAll("'","''")}'`,key=()=>crypto.randomUUID(),run=(u,s)=>sql(`set role authenticated;set request.jwt.claim.sub=${q(u)};${s}`);
const owner='10000000-0000-4000-8000-000000000003';let count=0;const test=(name,f)=>{f();count++;console.log('PASS '+name)};
const originalClock=sql("select pg_get_functiondef('arena_private.match_decision_clock()'::regprocedure)");
const tick=date=>sql(`create or replace function arena_private.match_decision_clock() returns timestamptz language sql volatile set search_path=pg_catalog as $$select ${q(date)}::timestamptz$$`);
const T='2039-01-01T00:00:00Z',START='2039-01-03T00:00:00Z',FIRST='2039-01-02T00:00:00Z',FINAL='2039-01-02T22:00:00Z';
const users=[];
function fixture(capacity=100,quantity=3,mode='pay_individually',start=START){
 tick(T);const arena=key();sql(`insert into arenas(id,owner_id,name,location,price_per_hour,opening_time,closing_time,court_count,audience_gender) values(${q(arena)},${q(owner)},'Seat policy LOCAL','Muscat',10,'00:00','23:59',1,'men')`);
 const payload={purpose:'match',payment_method:'card',payment_mode:mode,arena_id:arena,starts_at:start,ends_at:new Date(new Date(start).getTime()+3600000).toISOString(),capacity,name:'Seat LOCAL',sport:'football',seat_quantity:quantity,addons:[]};
 const order=JSON.parse(run(users[0],`select create_checkout(${q(JSON.stringify(payload))},${q(key())})`));return {arena,order,payload};
}
const pay=o=>JSON.parse(sql(`set role service_role;select payment_reconcile(${q(o.id)},${q('LOCAL_FAKE_'+o.id)},${q(o.id)},'OMR',${o.amount_due_baisa},'paid','LOCAL_TEST_INVOICE',${q('LOCAL_EVENT_'+o.id)})`));
const decide=m=>sql(`select arena_private.decide_match(${q(m)})`);
const joined=m=>Number(sql(`select arena_private.eligible_match_players(${q(m)})`));
const seatOrder=(u,m,n,k=key())=>JSON.parse(run(u,`select create_match_seat_checkout(${q(m)},${q(k)},${n})`));
function populate(seats,capacity=100){const f=fixture(capacity,Math.min(3,seats));f.order=pay(f.order);assert.equal(f.order.fulfillment_status,'fulfilled',f.order.failure_code);let left=seats-f.order.seat_quantity,i=1;while(left){const n=Math.min(3,left);pay(seatOrder(users[i++],f.order.match_id,n));left-=n}return f;}
const parallel=queries=>Promise.all(queries.map(query=>new Promise(resolve=>{const p=cp.spawn(exe,args);let out='',error='';p.stdout.on('data',d=>out+=d);p.stderr.on('data',d=>error+=d);p.on('close',code=>resolve({code,out,error}));p.stdin.end(query)})));
(async()=>{try{
 tick(T);
 for(let i=0;i<35;i++){
  const id=key(),name='seat_'+id.replaceAll('-','').slice(0,20),phone='968'+String(80000000+crypto.randomInt(19000000));
  sql(`insert into auth.users(id,phone,phone_confirmed_at) values(${q(id)},${q(phone)},now())`);
  run(id,`select complete_my_profile('LOCAL seat test',${q(name)},'2000-01-01','men')`);users.push(id);
 }
 test('client cannot execute clock or decision internals',()=>{assert.throws(()=>run(users[0],"select arena_private.match_decision_clock()"),/permission denied/);assert.throws(()=>run(users[0],"select process_arena_scheduled_events()"),/permission denied/)});
 for(const n of [1,2,3]){const f=fixture(10,n);test(`host ${n} seats charged exactly`,()=>{assert.equal(f.order.seat_quantity,n);assert.equal(f.order.amount_due_baisa,n*1000);assert.equal(f.order.payment_status,'pending');assert.equal(f.order.match_id,null)});f.order=pay(f.order);test(`host ${n} seats eligible only after provider fake verification`,()=>assert.equal(joined(f.order.match_id),n));}
 for(const n of [0,4])test(`invalid host quantity ${n} rejected`,()=>assert.throws(()=>fixture(10,n),/INVALID_SEAT_QUANTITY/));
 for(const start of ['2039-01-01T23:59:59Z','2039-01-02T00:00:00Z'])test(`creation at/within 24h rejected ${start}`,()=>assert.throws(()=>fixture(10,1,'pay_individually',start),/INDIVIDUAL_MATCH_REQUIRES_24_HOURS/));
 const rounding=fixture(3,3);test('three rounded seat amounts sum exactly to 10 OMR',()=>assert.equal(rounding.order.amount_due_baisa,10000));
 const payers=populate(3,10),m=payers.order.match_id;
 for(const n of [1,2,3]){const o=seatOrder(users[n],m,n);test(`participant ${n} seats remain excluded while pending`,()=>assert.equal(joined(m),3+(n-1)*n/2));pay(o);test(`participant ${n} seats counted after complete payment`,()=>assert.equal(joined(m),3+n*(n+1)/2));}
 const k=key(),existing=seatOrder(users[1],m,1,k);test('duplicate/retry returns existing payment, no second charge',()=>assert.equal(seatOrder(users[1],m,1,k).id,existing.id));
 test('quantity cannot silently change an existing payment',()=>assert.throws(()=>seatOrder(users[1],m,2),/SEAT_QUANTITY_ALREADY_RESERVED/));
 for(const percentage of [79,80,99,100]){
  const f=populate(percentage),id=f.order.match_id;tick('2039-01-01T23:59:59.999999Z');
  test(`${percentage}% before 24h remains pending`,()=>assert.equal(decide(id),'pending'));
  tick(FIRST);const expected=percentage<80?'cancelled':'pending';
  test(`${percentage}% exactly at 24h`,()=>assert.equal(decide(id),expected));
  test(`${percentage}% 24h checkpoint recorded once`,()=>{decide(id);assert.equal(sql(`select count(*) from arena_private.individual_match_checkpoints where match_id=${q(id)} and checkpoint='24h'`),'1')});
  if(percentage<80){
   test('24h cancellation releases court and leaves full refunds requested',()=>{assert.equal(sql(`select count(*) from court_reservations where source_id=${q(id)}`),'0');assert.equal(sql(`select bool_and(r.status='requested' and r.amount_baisa=o.amount_due_baisa) from payment_refunds r join checkout_orders o on o.id=r.order_id where o.match_id=${q(id)}`),'t')});continue;
  }
  test(`${percentage}% provisional pass is not final confirmation`,()=>assert.equal(sql(`select status||':'||precheck_outcome from matches where id=${q(id)}`),'upcoming:passed'));
  tick('2039-01-02T21:59:59.999999Z');test(`${percentage}% before 2h remains pending`,()=>assert.equal(decide(id),'pending'));
  tick(FINAL);test(`${percentage}% exactly at 2h`,()=>assert.equal(decide(id),percentage===100?'confirmed':'cancelled'));
  const notices=sql(`select count(*) from notifications where data->>'match_id'=${q(id)} and type in('match_confirmed','match_cancelled')`);
  decide(id);test(`${percentage}% duplicate decision does not duplicate notifications/refunds`,()=>assert.equal(sql(`select count(*) from notifications where data->>'match_id'=${q(id)} and type in('match_confirmed','match_cancelled')`),notices));
 }
 const early=populate(100),e=early.order.match_id;
 test('early 100% does not lock withdrawal',()=>{assert.equal(decide(e),'pending');assert.equal(JSON.parse(run(users[1],`select my_match_withdrawal_summary(${q(e)})`)).allowed,true)});
 tick(FIRST);decide(e);tick('2039-01-02T01:00:00Z');
 test('100% after provisional 24h pass still permits withdrawal before 2h',()=>{assert.equal(sql(`select precheck_outcome||':'||decision_outcome from matches where id=${q(e)}`),'passed:pending');assert.equal(JSON.parse(run(users[1],`select my_match_withdrawal_summary(${q(e)})`)).allowed,true)});
 const old=JSON.parse(sql(`select to_jsonb(o) from checkout_orders o where match_id=${q(e)} and user_id=${q(users[1])}`));
 run(users[1],`select leave_match(${q(e)})`);
 test('withdrawal releases every paid seat and requests full payer refund once',()=>{assert.equal(joined(e),97);assert.equal(sql(`select amount_baisa||':'||status from payment_refunds where order_id=${q(old.id)}`),'300:requested')});
 const fresh=seatOrder(users[1],e,3);test('rejoin cannot reuse refunded entitlement',()=>{assert.notEqual(fresh.id,old.id);assert.equal(fresh.payment_status,'pending');assert.equal(joined(e),97)});pay(fresh);
 tick(FINAL);decide(e);
 test('final 100% locks RPC withdrawal and legacy direct delete',()=>{assert.throws(()=>run(users[1],`select leave_match(${q(e)})`),/WITHDRAWAL_LOCKED/);assert.throws(()=>sql(`delete from match_players where match_id=${q(e)} and user_id=${q(users[1])}`),/WITHDRAWAL_LOCKED/)});
 const race=populate(8,10),rm=race.order.match_id;
 const rr=await parallel([users[5],users[6]].map(u=>`set role authenticated;set request.jwt.claim.sub=${q(u)};select create_match_seat_checkout(${q(rm)},${q(key())},2)`));
 test('concurrent reservation of final two seats succeeds only once',()=>{assert.equal(rr.filter(r=>r.code===0).length,1,JSON.stringify(rr));assert(rr.some(r=>/MATCH_FULL/.test(r.error)))});
 const late=populate(79),lm=late.order.match_id;const pending=seatOrder(users[30],lm,1);tick(FIRST);decide(lm);const lateResult=pay(pending);
 test('late verified payment after cancellation cannot resurrect match',()=>{assert.equal(lateResult.fulfillment_status,'refund_required');assert.equal(sql(`select status from matches where id=${q(lm)}`),'cancelled')});
 test('late/duplicate capture makes one full refund request',()=>{pay(pending);assert.equal(sql(`select count(*)||':'||max(amount_baisa)||':'||max(status) from payment_refunds where order_id=${q(pending.id)}`),'1:100:requested')});
 const finalRace=populate(99),fm=finalRace.order.match_id,finalPending=seatOrder(users[34],fm,1);tick(FIRST);decide(fm);tick(FINAL);
 const racing=await parallel([
  `select arena_private.decide_match(${q(fm)})`,
  `set role service_role;select payment_reconcile(${q(finalPending.id)},${q('LOCAL_FAKE_'+finalPending.id)},${q(finalPending.id)},'OMR',100,'paid','LOCAL_TEST_INVOICE',${q('LOCAL_EVENT_'+finalPending.id)})`,
 ]);
 test('simultaneous final decision and last payment cannot count a late seat',()=>{assert(racing.every(r=>r.code===0),JSON.stringify(racing));assert.equal(sql(`select decision_outcome||':'||decision_joined_count from matches where id=${q(fm)}`),'cancelled:99')});
 test('payment racing cancellation receives one requested refund, never success',()=>assert.equal(sql(`select count(*)||':'||max(status) from payment_refunds where order_id=${q(finalPending.id)}`),'1:requested'));
 const leaveRace=populate(100),wm=leaveRace.order.match_id;tick(FINAL);
 const leaveResults=await parallel([`select arena_private.decide_match(${q(wm)})`,`set role authenticated;set request.jwt.claim.sub=${q(users[1])};select leave_match(${q(wm)})`]);
 test('simultaneous final decision and leave serializes to final confirmation',()=>{assert.equal(leaveResults[0].code,0);assert.notEqual(leaveResults[1].code,0);assert.match(leaveResults[1].error,/WITHDRAWAL_LOCKED/);assert.equal(joined(wm),100)});
 const delayed=populate(80),dm=delayed.order.match_id;tick('2039-01-02T22:05:00Z');
 const job=JSON.parse(sql('set role service_role;select process_arena_scheduled_events()'));
 test('scheduler outage recovery processes both missed checkpoints',()=>{assert.equal(sql(`select decision_outcome from matches where id=${q(dm)}`),'cancelled');assert.equal(sql(`select count(*) from arena_private.individual_match_checkpoints where match_id=${q(dm)}`),'2');assert.equal(job.individual_precheck_errors,0)});
 const lateHost=fixture(10,3);tick(FIRST);const lateHostResult=pay(lateHost.order);
 test('late initial host capture creates no match and requests a full refund',()=>{assert.equal(lateHostResult.match_id,null);assert.equal(lateHostResult.fulfillment_status,'refund_required');assert.equal(sql(`select amount_baisa||':'||status from payment_refunds where order_id=${q(lateHost.order.id)}`),'3000:requested')});
 const hostAll=fixture(5,3,'host_pays_all','2039-01-01T03:00:00Z');hostAll.order=pay(hostAll.order);
 test('host-pays-all retains full amount, one account seat and 90-minute decision',()=>{assert.equal(hostAll.order.amount_due_baisa,10000);assert.equal(hostAll.order.seat_quantity,1);assert.equal(sql(`select individual_policy||':'||(starts_at-decision_at)::text from matches where id=${q(hostAll.order.match_id)}`),'legacy_90_80:01:30:00')});
 test('ordinary cancellation boundary remains exactly 150 minutes',()=>assert.equal(sql("select arena_private.booking_cancel_allowed('2039-01-01 02:30Z','2039-01-01 00:00Z')"),'t'));
 test('client cannot write paid seats, decisions or refunds',()=>{for(const statement of ["update matches set status='confirmed'","update checkout_orders set seat_quantity=3","update match_players set seat_quantity=3","insert into arena_private.individual_match_checkpoints(match_id,checkpoint,outcome,paid_seats,due_at) values(null,'2h','confirmed',100,now())"])assert.throws(()=>run(users[0],statement),/permission denied/)});
 console.log(count+' individual match seat tests passed');
}catch(e){console.error(e);process.exitCode=1}finally{sql(originalClock)}})();
