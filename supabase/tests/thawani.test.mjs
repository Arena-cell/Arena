import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {configuration,Thawani,verifiedSession,verifySignature} from '../functions/_shared/thawani.mjs';
const order={id:'test-order',amount_due_baisa:10000};
test('Missing keys do not configure a payment provider',()=>assert.throws(()=>configuration(()=>undefined),/PAYMENT_PROVIDER_NOT_CONFIGURED/));
test('Production mode is disabled in Phase 2',()=>assert.throws(()=>configuration(n=>n==='THAWANI_ENV'?'production':'test-only'),/PRODUCTION_PAYMENTS_DISABLED/));
test('Create contract uses server amount and references',async()=>{
 const calls=[];const provider=new Thawani({base:'https://uatcheckout.thawani.om/api/v1',secret:'test-only',publishable:'test-only',success:'https://example.test/success',cancel:'https://example.test/cancel'},async(url,options)=>{calls.push({url,options});return new Response(JSON.stringify({success:true,data:{session_id:'s'}}));});
 await provider.create(order);const body=JSON.parse(calls[0].options.body);
 assert.equal(body.products[0].unit_amount,10000);assert.equal(body.client_reference_id,order.id);assert.equal(body.expire_in_minutes,30);assert.equal(body.save_card_on_success,false);
 assert.equal(calls[0].url,'https://uatcheckout.thawani.om/api/v1/checkout/session');
 assert.ok(!('Idempotency-Key' in calls[0].options.headers));
});
test('Success redirect alone cannot verify payment',()=>assert.throws(()=>verifiedSession(order,{success:true}),/PROVIDER_VERIFICATION_MISMATCH/));
test('Authoritative session must match amount currency and owner reference',()=>{
 const valid={session_id:'s',client_reference_id:order.id,currency:'OMR',total_amount:10000,payment_status:'paid'};
 assert.equal(verifiedSession(order,valid),valid);
 for(const delta of [{total_amount:1},{currency:'USD'},{client_reference_id:'other'},{payment_status:'successful'}])assert.throws(()=>verifiedSession(order,{...valid,...delta}));
 for(const state of ['paid','unpaid','cancelled'])assert.equal(verifiedSession(order,{...valid,payment_status:state}).payment_status,state);
});
test('Webhook signature authenticates exact raw body and timestamp',async()=>{
 const raw='{"event_type":"checkout.completed"}',stamp=String(Math.floor(Date.now()/1000));
 const signature=createHmac('sha256','test-only').update(raw+'-'+stamp).digest('hex');
 assert.equal(await verifySignature(raw,stamp,signature,'test-only'),true);
 assert.equal(await verifySignature(raw+' ',stamp,signature,'test-only'),false);
 assert.equal(await verifySignature(raw,stamp,signature,'wrong'),false);
 assert.equal(await verifySignature(raw,stamp,signature,'test-only',Date.now()+3600000),false);
});
test('Uncertain transport errors propagate, never fake paid',async()=>{
 const provider=new Thawani({base:'https://example.test',secret:'test-only'},async()=>{throw Error('timeout');});
 await assert.rejects(provider.retrieve('s'),/timeout/);
});
