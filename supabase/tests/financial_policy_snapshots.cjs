// Loopback-only integration/concurrency tests; no hosted payments or transfers.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const db=fs.readFileSync('build/phase1-test-db.txt','utf8').trim();assert.match(db,/^arena_phase1_test_\d+$/);
const exe='C:/Program Files/PostgreSQL/18/bin/psql.exe';
const args=['-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-qAt'];
const sql=s=>{try{return cp.execFileSync(exe,args,{input:s,encoding:'utf8',maxBuffer:16*1024*1024,stdio:['pipe','pipe','pipe']}).trim()}catch(e){throw Error(e.stderr.toString()||e.message)}};
const q=s=>`'${String(s).replaceAll("'","''")}'`;
assert(sql('show data_directory').replaceAll('\\','/').endsWith('/playon/build/phase1-pgdata'));
const as=(n,s)=>`set role authenticated;set request.jwt.claim.sub='10000000-0000-4000-8000-${String(n).padStart(12,'0')}';${s}`;
const run=(n,s)=>sql(as(n,s));
const arena=crypto.randomUUID();
sql(`insert into arenas(id,owner_id,name,location,price_per_hour,opening_time,closing_time,court_count,audience_gender)
values(${q(arena)},'10000000-0000-4000-8000-000000000003','Finance local fixture','Muscat',10,'08:00','23:00',2,'men')`);
let count=0;const test=(name,fn)=>{fn();count++;console.log('PASS '+name)};
const original=sql('select coalesce(jsonb_object_agg(id,to_jsonb(o)-\'promotion_id\'),\'{}\') from checkout_orders o');
for(const file of ['202610240002_disable_new_user_cash_checkout.sql','202610240004_financial_policy_and_discount_snapshots.sql']) {
 const marker=file.includes('0002') ? "select to_regprocedure('arena_private.reject_new_cash_checkout()') is null" : "select to_regclass('public.booking_financial_snapshots') is null";
 if(sql(marker)==='t')sql(fs.readFileSync('supabase/migrations/'+file,'utf8'));
}
test('migration leaves every historical order unchanged',()=>assert.equal(original,sql(`select coalesce(jsonb_object_agg(id,to_jsonb(o)-'promotion_id'),'{}') from checkout_orders o where id in(select jsonb_object_keys(${q(original)}::jsonb)::uuid)`)));
// The comparison above removes the additive nullable promotion_id from new schema.
const suffix=crypto.randomUUID().slice(0,8).toUpperCase();
const def=(code,extra={})=>({code,kind:'fixed',value:100,starts_at:'2037-01-01T00:00:00Z',ends_at:'2039-01-01T00:00:00Z',usage_limit:100,arena_ids:[arena],funding_mode:'arena',arena_funding_bps:10000,owner_funding_bps:0,active:true,...extra});
// Date windows encompass the actual server time as well as the future bookings.
const campaign=d=>{d.starts_at='2026-01-01T00:00:00Z';return run(4,`select admin_save_discount(null,${q(JSON.stringify(d))})`)};
const request=(promo,extra={})=>({purpose:'booking',payment_method:'card',arena_id:arena,starts_at:'2038-01-01T10:00:00+04:00',ends_at:'2038-01-01T11:00:00+04:00',addons:[],...(promo?{promo_code:promo}:{}),...extra});
const create=(payload,key=crypto.randomUUID(),user=1)=>JSON.parse(run(user,`select create_checkout(${q(JSON.stringify(payload))},${q(key)})`));
const snapshot=id=>JSON.parse(sql(`select to_jsonb(s) from booking_financial_snapshots s where origin_order_id=${q(id)}`));
test('active campaign without valid funding is rejected',()=>assert.throws(()=>campaign(def('BAD'+suffix,{funding_mode:null,arena_funding_bps:null,owner_funding_bps:null})),/check constraint/));
test('shared percentages must sum to 100%',()=>assert.throws(()=>campaign(def('SUM'+suffix,{funding_mode:'shared',arena_funding_bps:7000,owner_funding_bps:2000})),/check constraint/));
test('owner cannot create promotions',()=>assert.throws(()=>run(3,`select admin_save_discount(null,${q(JSON.stringify(def('OWN'+suffix)))})`),/ADMIN_ONLY/));
let arenaOrder,ownerOrder,sharedOrder;const arenaCode='AR'+suffix,ownerCode='OW'+suffix,sharedCode='SH'+suffix;
const arenaPromo=campaign(def(arenaCode));campaign(def(ownerCode,{funding_mode:'owner',arena_funding_bps:0,owner_funding_bps:10000}));
campaign(def(sharedCode,{funding_mode:'shared',arena_funding_bps:6000,owner_funding_bps:4000,value:500}));
test('Arena funding preserves owner entitlement and snapshots rates',()=>{arenaOrder=create(request(arenaCode));const s=snapshot(arenaOrder.id);assert.equal(s.commission_baisa,800);assert.equal(s.owner_net_baisa,9200);assert.equal(s.arena_discount_baisa,100);assert.equal(s.owner_discount_baisa,0);assert.equal(s.arena_funding_bps,10000)});
test('Owner funding reduces only owner share',()=>{ownerOrder=create(request(ownerCode));const s=snapshot(ownerOrder.id);assert.equal(s.owner_net_baisa,9100);assert.equal(s.arena_discount_baisa,0);assert.equal(s.owner_discount_baisa,100)});
test('shared funding and line totals reconcile exactly',()=>{sharedOrder=create(request(sharedCode));const s=snapshot(sharedOrder.id);assert.equal(s.arena_discount_baisa,300);assert.equal(s.owner_discount_baisa,200);assert.equal(s.owner_net_baisa,9000);assert.equal(s.owner_net_baisa+s.commission_baisa-s.arena_discount_baisa,sharedOrder.total_amount_baisa);const lines=JSON.parse(sql(`select jsonb_agg(to_jsonb(l)) from booking_financial_lines l where snapshot_id=${q(s.id)}`));assert.equal(lines.reduce((n,l)=>n+l.paid_baisa,0),sharedOrder.total_amount_baisa)});
test('editing campaign does not restate past snapshots',()=>{const before=snapshot(arenaOrder.id);run(4,`select admin_save_discount(${q(arenaPromo)},${q(JSON.stringify(def(arenaCode,{funding_mode:'owner',arena_funding_bps:0,owner_funding_bps:10000})))})`);assert.deepEqual(snapshot(arenaOrder.id),before)});
test('discount cannot exceed Arena 5.5% internal share',()=>{const code='CAP'+suffix;campaign(def(code,{value:600}));assert.throws(()=>create(request(code)),/DISCOUNT_EXCEEDS_ARENA_SHARE/)});
test('no new cash order can bypass the UI',()=>assert.throws(()=>create(request(null,{payment_method:'cash'})),/CASH_TEMPORARILY_DISABLED/));
test('pending card remains pending without a booking or provider reference',()=>{assert.equal(arenaOrder.payment_status,'pending');assert.equal(arenaOrder.booking_id,null);assert.equal(arenaOrder.provider_session_id,null)});
test('owner cannot read internal financial tables',()=>assert.equal(run(3,'select count(*) from booking_financial_snapshots'),'0'));
test('client direct snapshot writes are denied',()=>assert.throws(()=>run(1,"update booking_financial_snapshots set commission_baisa=0"),/permission denied/));
test('snapshot even resists privileged accidental restatement',()=>assert.throws(()=>sql(`update booking_financial_snapshots set commission_baisa=0 where origin_order_id=${q(ownerOrder.id)}`),/IMMUTABLE_FINANCIAL_SNAPSHOT/));
test('duplicate checkout does not duplicate its snapshot',()=>{const key=crypto.randomUUID();const first=create(request(ownerCode),key);assert.equal(create(request(ownerCode),key).id,first.id);assert.equal(sql(`select count(*) from booking_financial_snapshots where origin_order_id=${q(first.id)}`),'1')});
test('regular user has no finance access',()=>assert.equal(run(1,'select my_finance_access()'),'f'));
const concurrent=s=>new Promise(resolve=>{const child=cp.spawn(exe,args);let out='',err='';child.stdout.on('data',d=>out+=d);child.stderr.on('data',d=>err+=d);child.on('close',code=>resolve({code,out,err}));child.stdin.end(s)});
(async()=>{
 const code='ONE'+suffix;campaign(def(code,{usage_limit:1}));
 const results=await Promise.all([1,2].map(user=>concurrent(as(user,`select create_checkout(${q(JSON.stringify(request(code)))},${q(crypto.randomUUID())})`))));
 assert.equal(results.filter(x=>x.code===0).length,1);assert(results.some(x=>/PROMOTION_USAGE_LIMIT/.test(x.err)));count++;console.log('PASS concurrent last promotion use succeeds once');
 console.log(count+' tests passed');
})().catch(e=>{console.error(e);process.exitCode=1});
