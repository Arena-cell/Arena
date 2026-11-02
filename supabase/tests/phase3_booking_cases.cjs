module.exports=({sql,fixture,q,test,assert,uid})=>{
 const match=fixture(2,0);
 const b=sql(`insert into bookings(user_id,arena_id,court_id,starts_at,ends_at,total_price,status,payment_method,payment_status)
 select ${q(uid(1))},arena_id,court_id,now()+interval '40 minutes',now()+interval '100 minutes',10,'upcoming','cash','unpaid'
 from matches where id=${q(match)} returning id`);
 sql('select process_arena_scheduled_events()');
 test('Cash booking reminder catches missed 60-minute deadline',()=>assert.equal(sql(`select count(*) from notifications where type='booking_reminder' and data->>'booking_id'=${q(b)}`),'1'));
 test('Cash booking reminder preserves financial state',()=>assert.equal(sql(`select payment_method||':'||payment_status from bookings where id=${q(b)}`),'cash:unpaid'));
 sql('select process_arena_scheduled_events();select process_arena_scheduled_events()');
 test('Repeated booking reminder job is idempotent',()=>assert.equal(sql(`select count(*) from notifications where type='booking_reminder' and data->>'booking_id'=${q(b)}`),'1'));
};
