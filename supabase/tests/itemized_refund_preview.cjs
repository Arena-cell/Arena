const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict');
const db=fs.readFileSync('build/phase1-test-db.txt','utf8').trim();assert.match(db,/^arena_phase1_test_\d+$/);
const args=['-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-qAt'];
const sql=s=>cp.execFileSync('C:/Program Files/PostgreSQL/18/bin/psql.exe',args,{input:s,encoding:'utf8',stdio:['pipe','pipe','pipe']}).trim();
if(sql("select to_regprocedure('arena_private.itemized_refund_preview(jsonb)') is null")==='t')sql(fs.readFileSync('supabase/migrations/202610240003_itemized_refund_preview.sql','utf8'));
const lines=[{line_id:'base',line_type:'base',original_baisa:10000,refunded_baisa:0},{line_id:'racket',line_type:'addon',addon_code:'racket',original_baisa:2000,refunded_baisa:0},{line_id:'water',line_type:'addon',addon_code:'water',original_baisa:1000,refunded_baisa:0}];
const quote=l=>JSON.parse(sql(`select arena_private.itemized_refund_preview('${JSON.stringify(l)}'::jsonb)`));
let checks=0;function test(n,f){f();checks++;console.log('PASS '+n)}
test('no refund retains 0.960 commission and 12.040 owner share',()=>{const q=quote(lines);assert.equal(q.commission_baisa,960);assert.equal(q.owner_net_baisa,12040)});
test('water refund does not reverse any commission',()=>{const l=structuredClone(lines);l[2].refunded_baisa=1000;const q=quote(l);assert.equal(q.commission_reversal_baisa,0);assert.equal(q.owner_net_baisa,11040)});
test('approved partial base/rental refunds reverse 8% of eligible amounts',()=>{const l=structuredClone(lines);l[0].refunded_baisa=1000;l[1].refunded_baisa=500;const q=quote(l);assert.equal(q.commission_reversal_baisa,120);assert.equal(q.commission_baisa,840);assert.equal(q.owner_net_baisa,10660)});
test('full refund leaves zero commission and zero owner entitlement',()=>{const l=lines.map(x=>({...x,refunded_baisa:x.original_baisa}));const q=quote(l);assert.equal(q.commission_baisa,0);assert.equal(q.owner_net_baisa,0)});
test('missing allocation is rejected, never prorated',()=>assert.throws(()=>quote([{line_id:'base',line_type:'base',original_baisa:10000}])));
test('duplicate line and over-refund are rejected',()=>{assert.throws(()=>quote([...lines,lines[1]]));const l=structuredClone(lines);l[2].refunded_baisa=1001;assert.throws(()=>quote(l))});
test('same cumulative inputs give identical result without incremental duplication',()=>assert.deepEqual(quote(lines),quote(lines)));
test('gateway fee and refunded fee remain unknown',()=>{const q=quote(lines);assert.equal(q.actual_gateway_fee_baisa,null);assert.equal(q.gateway_refunded_fee_baisa,null)});
test('client roles cannot invoke internal refund calculations',()=>{for(const role of ['anon','authenticated'])assert.equal(sql(`select has_function_privilege('${role}','arena_private.itemized_refund_preview(jsonb)','execute')`),'f')});
console.log(checks+' tests passed');
