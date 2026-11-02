// Hosted public-client tests: hard-coded Staging only, no service role.
const fs=require('node:fs'),assert=require('node:assert/strict'),crypto=require('node:crypto');
process.chdir(require('node:path').resolve(__dirname,'../..'));
const url='https://gtcrijikfaglqcwqozel.supabase.co',key='sb_publishable_pxaampXaN_YJB3uqB-B3CA_dcYA-glr';
const sessions=JSON.parse(fs.readFileSync('build/staging-evidence/sessions.local.json','utf8'));
async function request(route,body,token=sessions[0].access_token,method=body===undefined?'GET':'POST'){
 const r=await fetch(url+route,{method,headers:{apikey:key,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{}),Origin:'http://127.0.0.1:5178'},...(body===undefined?{}:{body:JSON.stringify(body)})});
 const text=await r.text();return {status:r.status,data:text?JSON.parse(text):null,cors:r.headers.get('access-control-allow-origin')};
}
const rpc=(name,body,token)=>request('/rest/v1/rpc/'+name,body,token);
(async()=>{
 const fixturesPath='build/phase2-evidence/orders.local.json';
 let fixture;
 if(fs.existsSync(fixturesPath))fixture=JSON.parse(fs.readFileSync(fixturesPath,'utf8'));
 else {
  const p={purpose:'booking',payment_method:'cash',arena_id:'a1000000-0000-4000-8000-000000000002',starts_at:'2036-04-01T10:00:00+04:00',ends_at:'2036-04-01T11:00:00+04:00',addons:[]};
  const quote=await rpc('checkout_quote',{p_arena:p.arena_id,p_start:p.starts_at,p_end:p.ends_at,p_addons:[],p_coupon:null});assert.equal(quote.status,200,JSON.stringify(quote));assert.equal(quote.data.total_amount_baisa,10000);
  const idem=crypto.randomUUID();const cash=await rpc('create_checkout',{p_request:p,p_request_key:idem});assert.equal(cash.status,200,JSON.stringify(cash));assert.equal(cash.data.payment_status,'unpaid');assert.equal(cash.data.fulfillment_status,'fulfilled');
  const again=await rpc('create_checkout',{p_request:p,p_request_key:idem});assert.equal(again.data.id,cash.data.id);
  const card=await rpc('create_checkout',{p_request:{...p,payment_method:'card',starts_at:'2036-04-02T10:00:00+04:00',ends_at:'2036-04-02T11:00:00+04:00'},p_request_key:crypto.randomUUID()});assert.equal(card.status,200,JSON.stringify(card));assert.equal(card.data.payment_status,'pending');assert.equal(card.data.booking_id,null);
  fixture={cash:cash.data,card:card.data};fs.mkdirSync('build/phase2-evidence',{recursive:true});fs.writeFileSync(fixturesPath,JSON.stringify(fixture));
 }
 console.log('PASS Staging cash unpaid; server pricing; same request idempotent; card pending without reservation');
 for(const table of ['checkout_orders','arena_addons','booking_addons','payment_refunds']){
  const changes=table==='checkout_orders'?{payment_status:'paid'}:table==='arena_addons'?{unit_amount_baisa:0}:table==='booking_addons'?{quantity:100}:{amount_baisa:1};
  const r=await request('/rest/v1/'+table,changes,sessions[0].access_token,'PATCH');assert.ok(r.status>=400,table+' direct writes');
 }
 const cross=await request('/rest/v1/checkout_orders?id=eq.'+fixture.card.id,undefined,sessions[1].access_token);assert.equal(cross.status,200);assert.equal(cross.data.length,0);
 const reconcile=await rpc('payment_reconcile',{p_order:fixture.card.id,p_session:'forged',p_reference:fixture.card.id,p_currency:'OMR',p_amount:10000,p_status:'paid',p_invoice:'forged',p_event_key:'forged'});assert.ok(reconcile.status>=400);
 console.log('PASS Staging RLS: financial writes denied, cross-user order hidden, reconciliation denied');
 const payment=await request('/functions/v1/arena-payment',{order_id:fixture.card.id,action:'start'});
 assert.equal(payment.status,503,JSON.stringify(payment));assert.equal(payment.data.error,'PAYMENT_PROVIDER_NOT_CONFIGURED');assert.equal(payment.cors,'http://127.0.0.1:5178');
 const after=await request('/rest/v1/checkout_orders?id=eq.'+fixture.card.id);assert.equal(after.data[0].payment_status,'pending');assert.equal(after.data[0].provider_creation_state,'not_started');
 console.log('PASS deployed payment: missing keys 503; no provider attempt and no fake paid; correct CORS');
 const noauth=await request('/functions/v1/arena-payment',{order_id:fixture.card.id,action:'start'},null);assert.equal(noauth.status,401);
 console.log('PASS deployed payment rejects unauthenticated request');
})().catch(e=>{console.error(e.message);process.exitCode=1;});
