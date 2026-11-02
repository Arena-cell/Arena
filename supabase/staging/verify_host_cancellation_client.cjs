// Named Staging only, public key + real Auth sessions, no financial fakes.
const fs=require('node:fs'),assert=require('node:assert/strict');
process.chdir(require('node:path').resolve(__dirname,'../..'));
const url='https://gtcrijikfaglqcwqozel.supabase.co',key='sb_publishable_pxaampXaN_YJB3uqB-B3CA_dcYA-glr';
const sessions=JSON.parse(fs.readFileSync('build/staging-evidence/sessions.local.json','utf8'));
async function req(route,body,i=0,method=body===undefined?'GET':'POST'){
 const r=await fetch(url+route,{method,headers:{apikey:key,'Content-Type':'application/json',Authorization:'Bearer '+sessions[i].access_token},...(body===undefined?{}:{body:JSON.stringify(body)})});const s=await r.text();return {status:r.status,data:s?JSON.parse(s):null};
}
const rpc=(n,b,i=0)=>req('/rest/v1/rpc/'+n,b,i);
let checks=0;async function test(n,f){await f();checks++;console.log('PASS '+n)}
(async()=>{try{
 const mid='f3090000-0000-4000-8000-000000000001',arena='a1000000-0000-4000-8000-000000000002';
 await test('Other authenticated participant cannot cancel creator match',async()=>{const r=await rpc('cancel_host_paid_match',{p_match:mid});assert.ok(r.status>=400);assert.match(r.data.message,/CREATOR_ONLY/)});
 await test('Direct final match/refund writes rejected',async()=>{for(const [t,b] of [['matches',{status:'cancelled'}],['payment_refunds',{status:'succeeded'}],['checkout_orders',{payment_status:'paid'}]])assert.ok((await req('/rest/v1/'+t,b,0,'PATCH')).status>=400)});
 const request={purpose:'match',payment_method:'card',payment_mode:'host_pays_all',capacity:5,name:'Staging pending host cancellation',sport:'football',arena_id:arena,starts_at:'2026-10-12T16:00:00+04:00',ends_at:'2026-10-12T17:00:00+04:00',addons:[]};
 const pending=await rpc('create_checkout',{p_request:request,p_request_key:'f3090000-0000-4000-8000-000000000002'});assert.equal(pending.status,200,JSON.stringify(pending.data));const oid=pending.data.id;
 await test('Actual pending Card checkout never marked paid',async()=>{assert.equal(pending.data.payment_status,'pending');assert.equal(pending.data.match_id,null)});
 await test('Concurrent new/legacy pending cancellation safe',async()=>{const rs=await Promise.all([rpc('cancel_pending_host_match_checkout',{p_order:oid}),rpc('cancel_unstarted_checkout',{p_order:oid})]);assert.ok(rs.every(r=>r.status===204),JSON.stringify(rs))});
 await test('Cancelled pending entitlement preserved; zero refunded funds',async()=>{const r=await req('/rest/v1/checkout_orders?id=eq.'+oid);assert.equal(r.data[0].fulfillment_status,'cancelled');assert.equal(r.data[0].payment_status,'pending');assert.ok(r.data[0].entitlement_revoked_at);assert.equal(r.data[0].refunded_amount_baisa,0)});
 await test('Cancelled pending checkout cannot restart payment Edge Function',async()=>{const r=await req('/functions/v1/arena-payment',{action:'start',order_id:oid});assert.equal(r.status,409);assert.equal(r.data.error,'ORDER_NOT_PAYABLE')});
 if(process.argv.includes('--after-ui')){
  await test('UI cancellation is final and attributed to real creator',async()=>{const r=await req('/rest/v1/matches?id=eq.'+mid);assert.equal(r.status,200);assert.equal(r.data[0].status,'cancelled');assert.equal(r.data[0].decision_outcome,'cancelled');assert.equal(r.data[0].cancellation_reason,'HOST_PAYS_ALL_CREATOR_CANCELLED');assert.equal(r.data[0].cancelled_by,'c1faaa2a-f829-46f0-ae35-9f095a01ef4f')});
  await test('Actual participant sees preserved cancelled membership',async()=>{const r=await req('/rest/v1/match_players?match_id=eq.'+mid);assert.equal(r.status,200);assert.ok(r.data.length>0);assert.ok(r.data.every(p=>p.status==='cancelled'))});
  await test('Participant receives real cancellation inbox event exactly once',async()=>{const r=await req('/rest/v1/notifications?event_key=eq.match-decision:'+mid);assert.equal(r.status,200);assert.equal(r.data.length,1);assert.match(r.data[0].body_en,/host cancelled/)});
  await test('Court available through original unified availability quote',async()=>{const r=await rpc('checkout_quote',{p_arena:arena,p_start:'2026-10-11T16:00:00+04:00',p_end:'2026-10-11T17:00:00+04:00',p_addons:[],p_coupon:null});assert.equal(r.status,200,JSON.stringify(r.data))});
 }
 if(process.argv.includes('--private')){
  const privateId='f3090000-0000-4000-8000-000000000004';
  await test('Real creator cancels private match with safe duplicate requests',async()=>{const rs=await Promise.all([rpc('cancel_host_paid_match',{p_match:privateId}),rpc('leave_match',{match_id:privateId})]);assert.ok(rs.every(r=>r.status===204),JSON.stringify(rs))});
  await test('Actual private cancellation retains original joined history',async()=>{const r=await req('/rest/v1/match_players?match_id=eq.'+privateId);assert.equal(r.status,200);assert.equal(r.data.length,2);assert.ok(r.data.every(p=>p.status==='cancelled'&&p.cancelled_from_status==='joined'))});
  await test('Real outsider cannot read cancelled private match or its summary',async()=>{const r=await req('/rest/v1/matches?id=eq.'+privateId,undefined,1);assert.equal(r.status,200);assert.equal(r.data.length,0);assert.ok((await rpc('my_match_withdrawal_summary',{p_match:privateId},1)).status>=400)});
 }
 fs.writeFileSync('build/phase3-final-evidence/host-pending-order.json',JSON.stringify({order_id:oid,match_id:mid}));
 console.log(`${checks} actual Staging host-policy checks passed; real Thawani refunds PENDING.`);
}catch(e){console.error(e.message);process.exitCode=1}})();
