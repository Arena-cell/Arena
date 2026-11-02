// Public-key client, actual Staging Auth sessions. No service role/provider fakes.
const fs=require('node:fs'),assert=require('node:assert/strict');
process.chdir(require('node:path').resolve(__dirname,'../..'));
const url='https://gtcrijikfaglqcwqozel.supabase.co',key='sb_publishable_pxaampXaN_YJB3uqB-B3CA_dcYA-glr';
const sessions=JSON.parse(fs.readFileSync('build/staging-evidence/sessions.local.json','utf8'));
async function req(route,body,i=0,method=body===undefined?'GET':'POST'){
 const r=await fetch(url+route,{method,headers:{apikey:key,'Content-Type':'application/json',Authorization:'Bearer '+sessions[i].access_token},...(body===undefined?{}:{body:JSON.stringify(body)})});const s=await r.text();return {status:r.status,data:s?JSON.parse(s):null};
}
const rpc=(name,body,i=0)=>req('/rest/v1/rpc/'+name,body,i);
let checks=0;async function test(name,f){await f();checks++;console.log('PASS '+name)}
(async()=>{try{
 const arena='a1000000-0000-4000-8000-000000000002';const catalog=await req('/rest/v1/arena_addons?arena_id=eq.'+arena+'&enabled=eq.true');assert.equal(catalog.status,200);
 const water=catalog.data.find(a=>a.addon_code==='water'),rack=catalog.data.find(a=>a.addon_code==='racket');assert.ok(water&&rack);
 const request={purpose:'booking',payment_method:'cash',arena_id:arena,starts_at:'2026-10-10T10:00:00+04:00',ends_at:'2026-10-10T11:00:00+04:00',addons:[{id:water.id,quantity:2},{id:rack.id,quantity:2}]};
 const result=await rpc('create_checkout',{p_request:request,p_request_key:'f4090000-0000-4000-8000-000000000001'});assert.equal(result.status,200,JSON.stringify(result.data));const order=result.data;
 fs.writeFileSync('build/refund-policy-evidence/order.local.json',JSON.stringify({order_id:order.id,booking_id:order.booking_id,arena}));
 await test('Real user receives server 150-minute cancellation eligibility',async()=>{const r=await rpc('booking_cancellation_summary',{p_booking:order.booking_id});assert.equal(r.status,200);if(r.data.status!=='cancelled')assert.equal(r.data.allowed,true);assert.equal(r.data.expected_refund_baisa,0)});
 await test('Other real user cannot cancel',async()=>{assert.ok((await rpc('cancel_arena_booking',{p_booking_id:order.booking_id,p_reason:'Unauthorized test'},1)).status>=400)});
 await test('Actual cash cancellation and exact retry succeed',async()=>{for(let n=0;n<2;n++)assert.equal((await rpc('cancel_arena_booking',{p_booking_id:order.booking_id,p_reason:'[STAGING TEST] Refund policy cash cancellation'})).status,204)});
 await test('Cancelled ledger and inventory evidence match; no fabricated refund',async()=>{const r=await rpc('booking_cancellation_summary',{p_booking:order.booking_id});assert.equal(r.data.status,'cancelled');assert.equal(r.data.order.payment_status,'unpaid');assert.equal(r.data.refunds.length,0);assert.equal(r.data.addons.find(a=>a.kind==='consumable').restored_quantity,2);assert.ok(r.data.addons.every(a=>a.released_at));});
 await test('Actual stock restored and Court available again',async()=>{const a=await req('/rest/v1/arena_addons?id=eq.'+water.id);assert.equal(a.data[0].stock,water.stock);const q=await rpc('checkout_quote',{p_arena:arena,p_start:request.starts_at,p_end:request.ends_at,p_addons:request.addons,p_coupon:null});assert.equal(q.status,200);assert.ok(q.data.catalog.find(a=>a.code==='racket').available_quantity>=2)});
 await test('Real user cannot forge refund/payment/stock restoration',async()=>{for(const [table,body] of [['checkout_orders',{payment_status:'paid'}],['payment_refunds',{status:'succeeded'}],['booking_addons',{restored_quantity:2}]])assert.ok((await req('/rest/v1/'+table,body,0,'PATCH')).status>=400)});
 await test('Cancelled order cannot restart Thawani',async()=>{const r=await req('/functions/v1/arena-payment',{action:'start',order_id:order.id});assert.equal(r.status,409);assert.equal(r.data.error,'ORDER_NOT_PAYABLE')});
 await test('Real pending Card cancellation creates neither booking nor fake refund',async()=>{
  const card=await rpc('create_checkout',{p_request:{...request,payment_method:'card',starts_at:'2026-10-10T12:00:00+04:00',ends_at:'2026-10-10T13:00:00+04:00'},p_request_key:'f4090000-0000-4000-8000-000000000002'});assert.equal(card.status,200);assert.equal(card.data.booking_id,null);
  assert.equal((await rpc('cancel_pending_booking_checkout',{p_order:card.data.id})).status,204);
  const s=await rpc('ordinary_order_cancellation_summary',{p_order:card.data.id});assert.equal(s.status,200);assert.equal(s.data.status,'cancelled');assert.equal(s.data.expected_refund_baisa,0);assert.equal(s.data.refunds.length,0);
 });
 console.log(`${checks} hosted refund-policy checks passed; actual electronic refunds NOT TESTED.`);
}catch(e){console.error(e.message);process.exitCode=1}})();
