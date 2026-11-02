// Named Staging public clients with real Auth sessions. No service role or provider fakes.
const fs=require('node:fs'),assert=require('node:assert/strict'),crypto=require('node:crypto');
process.chdir(require('node:path').resolve(__dirname,'../..'));
const url='https://gtcrijikfaglqcwqozel.supabase.co',key='sb_publishable_pxaampXaN_YJB3uqB-B3CA_dcYA-glr';
const sessions=JSON.parse(fs.readFileSync('build/staging-evidence/sessions.local.json','utf8'));
const confirmed='f3000000-0000-4000-8000-000000000001',cancelled='f3000000-0000-4000-8000-000000000002';
async function request(route,body,session=0,method=body===undefined?'GET':'POST'){
 const response=await fetch(url+route,{method,headers:{apikey:key,'Content-Type':'application/json',...(session===null?{}:{Authorization:'Bearer '+sessions[session].access_token})},...(body===undefined?{}:{body:JSON.stringify(body)})});
 const text=await response.text();return {status:response.status,data:text?JSON.parse(text):null};
}
const rpc=(name,body,session=0)=>request('/rest/v1/rpc/'+name,body,session);
let count=0;async function test(name,f){await f();count++;console.log('PASS '+name);}
(async()=>{try{
 await test('Real Staging lifecycle summary',async()=>{const r=await rpc('match_lifecycle_summary',{p_match:confirmed});assert.equal(r.status,200);assert.equal(r.data.status,'confirmed');assert.equal(r.data.confirmed_players,2);assert.equal(r.data.withdrawal_locked,true);});
 await test('Real user withdrawal locked by server',async()=>{const r=await rpc('leave_match',{match_id:confirmed});assert.equal(r.status,400);assert.match(r.data.message,/WITHDRAWAL_LOCKED/);});
 await test('Real user cannot update final match directly',async()=>assert.ok((await request('/rest/v1/matches?id=eq.'+confirmed,{status:'cancelled'},0,'PATCH')).status>=400));
 await test('Nonmember private summary hidden',async()=>assert.equal((await rpc('match_lifecycle_summary',{p_match:confirmed},1)).status,403));
 await test('Anon scheduler and push database access denied',async()=>{
  for(const name of ['process_arena_scheduled_events','claim_arena_push_batch'])assert.ok((await rpc(name,name==='claim_arena_push_batch'?{p_limit:1}:{},null)).status>=400);
 });
 await test('User scheduler and push access denied',async()=>{
  for(const name of ['process_arena_scheduled_events','claim_arena_push_batch'])assert.ok((await rpc(name,name==='claim_arena_push_batch'?{p_limit:1}:{})).status>=400);
 });
 await test('User cannot create refund or claim paid',async()=>{
  const fake=crypto.randomUUID();assert.ok((await rpc('request_payment_refund',{p_order:fake,p_amount_baisa:100,p_reason:'forged',p_request_key:fake})).status>=400);
  assert.ok((await rpc('payment_reconcile',{p_order:fake,p_session:'fake',p_reference:fake,p_currency:'OMR',p_amount:100,p_status:'paid',p_invoice:'fake',p_event_key:'fake'})).status>=400);
 });
 await test('Ordinary users cannot inspect staff inventory rows',async()=>{for(const id of [confirmed,cancelled]){const r=await request('/rest/v1/court_reservations?source_id=eq.'+id);assert.equal(r.status,200);assert.equal(r.data.length,0);}});
 await test('Real notification recipients and read marking',async()=>{
  const notices=await request('/rest/v1/notifications?type=eq.match_confirmed');assert.equal(notices.status,200);assert.equal(notices.data.length,1);
  const id=notices.data[0].id;
  assert.equal((await request('/rest/v1/notifications?id=eq.'+id,{read_at:new Date().toISOString()},0,'PATCH')).status,204);
  assert.ok((await request('/rest/v1/notifications?id=eq.'+id,{delivery_status:'sent'},0,'PATCH')).status>=400);
  assert.equal((await request('/rest/v1/notifications?id=eq.'+id,undefined,1)).data.length,0);
 });
 console.log(count+' hosted Phase 3 real-session checks passed. No fake payment/push success.');
 fs.writeFileSync('build/phase3-evidence/client-verification.json',JSON.stringify({checked_at:new Date().toISOString(),project_ref:'gtcrijikfaglqcwqozel',checks:count,status:'PASS'},null,2));
}catch(e){console.error(e.message);process.exitCode=1;}})();
