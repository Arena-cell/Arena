// Targeted business-rule regression on the latest financial schema.
// Provider confirmations are LOCAL TEST FAKES; no hosted service is contacted.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const db=fs.readFileSync('build/phase1-test-db.txt','utf8').trim();assert.match(db,/^arena_phase1_test_\d+$/);
const exe='C:/Program Files/PostgreSQL/18/bin/psql.exe',args=['-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-qAt'];
const sql=s=>{try{return cp.execFileSync(exe,args,{input:s,encoding:'utf8',stdio:['pipe','pipe','pipe']}).trim()}catch(e){throw Error(e.stderr.toString())}};
const q=s=>`'${String(s).replaceAll("'","''")}'`,key=()=>crypto.randomUUID(),uid=n=>`10000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
assert(sql('show data_directory').replaceAll('\\','/').endsWith('/playon/build/phase1-pgdata'));
const as=(n,s)=>`set role authenticated;set request.jwt.claim.sub=${q(uid(n))};${s}`,run=(n,s)=>sql(as(n,s));
let count=0;const test=(n,f)=>{f();count++;console.log('PASS '+n)};
for(const [minutes,allowed] of [[180,'t'],[150,'t'],[149,'f'],[-1,'f']])test(`ordinary cancellation ${minutes} minutes`,()=>assert.equal(sql(`select arena_private.booking_cancel_allowed('2039-01-01 10:00+04'::timestamptz+interval '${minutes} minutes','2039-01-01 10:00+04')`),allowed));
function fixture(){
 const arena=key();sql(`insert into arenas(id,owner_id,name,location,price_per_hour,opening_time,closing_time,court_count,audience_gender) values(${q(arena)},${q(uid(3))},'Finance regression LOCAL','Muscat',10,'00:00','23:59',1,'men')`);
 const water=run(4,`select admin_set_arena_addon(${q(arena)},'water',true,500,10)`),racket=run(4,`select admin_set_arena_addon(${q(arena)},'racket',true,1000,8)`);
 const payload={purpose:'booking',payment_method:'card',arena_id:arena,starts_at:'2039-01-01T10:00:00+04:00',ends_at:'2039-01-01T11:00:00+04:00',addons:[{id:water,quantity:2},{id:racket,quantity:2}]};
 const order=JSON.parse(run(1,`select create_checkout(${q(JSON.stringify(payload))},${q(key())})`));return {arena,water,racket,order};
}
const verify=o=>JSON.parse(sql(`set role service_role;select payment_reconcile(${q(o.id)},${q('LOCAL_FAKE_'+o.id)},${q(o.id)},'OMR',${o.amount_due_baisa},'paid','LOCAL_FAKE_INVOICE',${q(key())})`));
const a=fixture();a.order=verify(a.order);const cancel=()=>run(1,`select cancel_arena_booking(${q(a.order.booking_id)},'LOCAL regression cancellation')`);
test('new financial snapshot does not change base/addon total',()=>assert.equal(a.order.total_amount_baisa,13000));
test('different user cannot cancel paid booking',()=>assert.throws(()=>run(2,`select cancel_arena_booking(${q(a.order.booking_id)},'Forged')`),/CANCELLATION_NOT_ALLOWED/));
const frozen=sql(`select to_jsonb(s) from booking_financial_snapshots s where origin_order_id=${q(a.order.id)}`);
cancel();cancel();
test('paid cancellation requests full original payment, never fake refund success',()=>assert.equal(sql(`select amount_baisa||':'||status from payment_refunds where order_id=${q(a.order.id)}`),'13000:requested'));
test('duplicate cancellation creates only one refund request',()=>assert.equal(sql(`select count(*) from payment_refunds where order_id=${q(a.order.id)}`),'1'));
test('cancellation preserves immutable historical prices and funding',()=>assert.equal(sql(`select to_jsonb(s) from booking_financial_snapshots s where origin_order_id=${q(a.order.id)}`),frozen));
test('water stock restored only once; rental reservation released',()=>{assert.equal(sql(`select stock from arena_addons where id=${q(a.water)}`),'10');assert.equal(sql(`select count(*) from booking_addons where order_id=${q(a.order.id)} and released_at is null`),'0')});
test('cancelled court becomes available',()=>assert.equal(run(1,`select arena_has_available_court(${q(a.arena)},'2039-01-01 10:00+04','2039-01-01 11:00+04')`),'t'));
const late=fixture();run(1,`select cancel_pending_booking_checkout(${q(late.order.id)})`);verify(late.order);verify(late.order);
test('late/duplicate capture cannot resurrect cancelled pending booking',()=>assert.equal(sql(`select count(*) from bookings where checkout_order_id=${q(late.order.id)}`),'0'));
test('late capture requests exactly one full refund',()=>assert.equal(sql(`select count(*)||':'||max(amount_baisa)||':'||max(status) from payment_refunds where order_id=${q(late.order.id)}`),'1:13000:requested'));
function legacyMatch(joined){
 const eligible=sql("select p.id from profiles p join auth.users u on u.id=p.id where p.profile_version=1 and p.onboarding_complete and nullif(trim(p.display_name),'') is not null and p.username ~ '^[a-z][a-z0-9_]{3,31}$' and p.date_of_birth is not null and p.gender='men' and u.phone ~ '^\\+?968[0-9]{8}$' and u.phone_confirmed_at is not null order by p.id limit 5").split(/\r?\n/);assert(eligible.length>=4);
 const arena=key(),match=key();sql(`insert into arenas(id,name,location,price_per_hour,opening_time,closing_time,court_count,audience_gender) values(${q(arena)},'Legacy decision LOCAL','Muscat',10,'00:00','23:59',1,'men');
 insert into matches(id,arena_id,court_id,host_id,name,sport,starts_at,ends_at,max_players,price_per_player,gender,status) select ${q(match)},${q(arena)},id,${q(uid(1))},'Legacy LOCAL','football',now()+interval '3 hours',now()+interval '4 hours',5,1,'men','upcoming' from arena_courts where arena_id=${q(arena)};
 insert into match_players(match_id,user_id,status) select ${q(match)},id,'joined' from auth.users where id in(${eligible.slice(0,joined).map(q).join(',')});
 update matches set starts_at=now()+interval '80 minutes',ends_at=now()+interval '140 minutes' where id=${q(match)};`);return match;
}
const confirmed=legacyMatch(4),failed=legacyMatch(3);
test('90-minute server decision confirms exactly 80%',()=>assert.equal(sql(`select arena_private.decide_match(${q(confirmed)})`),'confirmed'));
test('under 80% cancels and releases court',()=>{assert.equal(sql(`select arena_private.decide_match(${q(failed)})`),'cancelled');assert.equal(sql(`select count(*) from court_reservations where source_id=${q(failed)}`),'0')});
test('repeated decision cannot reverse confirmed outcome',()=>assert.equal(sql(`select arena_private.decide_match(${q(confirmed)})`),'confirmed'));
test('confirmed withdrawal remains blocked through RPC and privileged legacy write',()=>{assert.throws(()=>run(2,`select leave_match(${q(confirmed)})`),/WITHDRAWAL_LOCKED/);const member=sql(`select user_id from match_players where match_id=${q(confirmed)} and status='joined' order by user_id limit 1`);assert.throws(()=>sql(`delete from match_players where match_id=${q(confirmed)} and user_id=${q(member)}`),/WITHDRAWAL_LOCKED/)});
test('new user cannot directly manipulate payment, refund or commission',()=>{for(const query of ["update checkout_orders set payment_status='paid'","update payment_refunds set status='succeeded'","update booking_financial_snapshots set commission_baisa=0"])assert.throws(()=>run(1,query),/permission denied/)});
console.log(count+' regression tests passed');
