// Inject verified provider outcomes in the isolated local database ONLY.
module.exports=async({sql,run,q,test,assert,uid,parallel})=>{
 const crypto=require('node:crypto');
 function create(mode,date){
  const payload={purpose:'match',payment_method:'card',payment_mode:mode,arena_id:'20000000-0000-4000-8000-000000000002',starts_at:`2038-02-${date}T10:00:00+04:00`,ends_at:`2038-02-${date}T11:00:00+04:00`,capacity:5,name:'Phase3 financial',sport:'football',addons:[]};
  return JSON.parse(run(1,`select create_checkout(${q(JSON.stringify(payload))},${q(crypto.randomUUID())})`));
 }
 const verify=o=>JSON.parse(sql(`set role service_role;select payment_reconcile(${q(o.id)},${q('p3_'+o.id)},${q(o.id)},'OMR',${o.amount_due_baisa},'paid','fake_local_invoice',${q(crypto.randomUUID())})`));
 for(const [mode,date] of [['host_pays_all','01'],['pay_individually','02']]){
  const o=verify(create(mode,date));
  if(mode==='pay_individually'){
   const p=JSON.parse(run(2,`select create_participant_checkout(${q(o.match_id)},${q(crypto.randomUUID())})`));verify(p);
   run(2,`select leave_match(${q(o.match_id)})`);
   test('Paid withdrawal keeps entitlement and excludes member',()=>{assert.equal(sql(`select count(*) from match_players where match_id=${q(o.match_id)} and user_id=${q(uid(2))}`),'0');assert.equal(sql(`select payment_status from checkout_orders where id=${q(p.id)}`),'paid');});
   const policy=sql("select exists(select 1 from information_schema.columns where table_name='checkout_orders' and column_name='entitlement_revoked_at')")==='t';
   test(policy?'Refund-requested seat rejoin requires new pending payment':'Paid seat rejoin does not charge twice',()=>{const r=JSON.parse(run(2,`select create_participant_checkout(${q(o.match_id)},${q(crypto.randomUUID())})`));if(policy){assert.notEqual(r.id,p.id);assert.equal(r.payment_status,'pending');assert.equal(sql(`select count(*) from payment_refunds where order_id=${q(p.id)}`),'1');}else{assert.equal(r.id,p.id);assert.equal(r.payment_status,'paid');}});
  }else run(2,`select create_participant_checkout(${q(o.match_id)},${q(crypto.randomUUID())})`);
  sql(`update matches set starts_at=now()+interval '80 minutes',ends_at=now()+interval '140 minutes' where id=${q(o.match_id)}`);
  test('Financial auto cancellation '+mode,()=>assert.equal(sql(`select arena_private.decide_match(${q(o.match_id)})`),'cancelled'));
  test('Cancellation requests refunds without imaginary success '+mode,()=>{
   assert.equal(sql(`select count(*) from payment_refunds r join checkout_orders o on o.id=r.order_id where o.match_id=${q(o.match_id)} and r.status='requested'`),mode==='host_pays_all'?'1':'2');
   assert.equal(sql(`select refunded_amount_baisa||':'||payment_status||':'||fulfillment_status from checkout_orders where id=${q(o.id)}`),'0:paid:refund_required');
  });
  test('Repeated financial cancellation/refund request safe '+mode,()=>{
   const count=sql('select count(*) from payment_refunds');sql(`select arena_private.decide_match(${q(o.match_id)});select arena_private.require_cancelled_match_refund(${q(o.id)})`);assert.equal(sql('select count(*) from payment_refunds'),count);
  });
  test('Refund pending notification only '+mode,()=>{assert.equal(sql(`select count(*) from notifications where user_id=${q(uid(1))} and type='refund_pending' and data->>'order_id'=${q(o.id)}`),'1');assert.equal(sql(`select count(*) from notifications where type='refund_completed' and data->>'order_id'=${q(o.id)}`),'0');});
  if(mode==='host_pays_all'){
   const r=sql(`select id from payment_refunds where order_id=${q(o.id)}`);
   sql(`set role service_role;select payment_confirm_refund(${q(r)},'local_fake_phase3_refund',${o.amount_due_baisa},true);select payment_confirm_refund(${q(r)},'local_fake_phase3_refund',${o.amount_due_baisa},true)`);
   test('Verified refund fake completes once in tests only',()=>assert.equal(sql(`select count(*) from notifications where user_id=${q(uid(1))} and type='refund_completed' and data->>'order_id'=${q(o.id)}`),'1'));
  }
 }
 const host=verify(create('pay_individually','03'));
 for(const n of [2,3,4])verify(JSON.parse(run(n,`select create_participant_checkout(${q(host.match_id)},${q(crypto.randomUUID())})`)));
 const late=JSON.parse(run(5,`select create_participant_checkout(${q(host.match_id)},${q(crypto.randomUUID())})`));
 sql(`update matches set starts_at=now()+interval '80 minutes',ends_at=now()+interval '140 minutes' where id=${q(host.match_id)}`);
 const results=await parallel([
  `select arena_private.decide_match(${q(host.match_id)})`,
  `set role service_role;select payment_reconcile(${q(late.id)},'local_late_session',${q(late.id)},'OMR',${late.amount_due_baisa},'paid','local_fake_invoice','local_late_event')`
 ]);
 test('Concurrent verified payment and decision avoid deadlocks',()=>{assert.ok(results.every(r=>r.ok),JSON.stringify(results));assert.equal(sql(`select decision_outcome||':'||decision_joined_count from matches where id=${q(host.match_id)}`),'confirmed:4');assert.equal(sql(`select count(*) from match_players where match_id=${q(host.match_id)} and status='joined'`),'5');});
 test('Participant payment confirmed notification deduplicated',()=>assert.equal(sql(`select count(*) from notifications where user_id=${q(uid(5))} and type='payment_confirmed' and data->>'order_id'=${q(late.id)}`),'1'));
 test('User cannot request own refund',()=>assert.throws(()=>run(5,`select request_payment_refund(${q(late.id)},100,'forged',${q(crypto.randomUUID())})`),/ADMIN_ONLY/));
 const cancelledHost=verify(create('pay_individually','04'));
 const capturedLate=JSON.parse(run(2,`select create_participant_checkout(${q(cancelledHost.match_id)},${q(crypto.randomUUID())})`));
 sql(`update matches set starts_at=now()+interval '80 minutes',ends_at=now()+interval '140 minutes',court_id=(select id from arena_courts where arena_id='20000000-0000-4000-8000-000000000002' and court_number=2) where id=${q(cancelledHost.match_id)};select arena_private.decide_match(${q(cancelledHost.match_id)})`);
 verify(capturedLate);verify(capturedLate);
 test('Late capture on cancelled match requires one refund and no seat',()=>{assert.equal(sql(`select count(*) from payment_refunds where order_id=${q(capturedLate.id)}`),'1');assert.equal(sql(`select count(*) from match_players where match_id=${q(cancelledHost.match_id)} and user_id=${q(uid(2))}`),'0');assert.equal(sql(`select payment_status||':'||fulfillment_status||':'||refunded_amount_baisa from checkout_orders where id=${q(capturedLate.id)}`),'paid:refund_required:0');});
};
