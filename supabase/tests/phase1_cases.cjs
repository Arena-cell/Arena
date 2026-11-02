// Real PostgreSQL transactions with SET ROLE authenticated (not superuser assertions).
const assert = require('node:assert/strict');
module.exports = async function run(sql, parallel) {
  const uid = n => `10000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
  const aid = n => `20000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
  const q = value => `'${String(value).replaceAll("'", "''")}'`;
  const as = (n, statement) => `set role authenticated; set request.jwt.claim.sub=${q(uid(n))}; ${statement}`;
  let passed=0;
  function check(name, fn) { fn(); console.log('PASS '+name); passed++; }
  function denied(n, statement, match=/permission denied|row-level security|NOT_AUTHORIZED|ADMIN_ONLY/) { assert.throws(()=>sql(as(n,statement)), match); }
  check('Legacy null courts allocated; unresolved conflict preserved',()=>{
    assert.equal(sql("select count(*) from bookings where arena_id='90000000-0000-4000-8000-000000000002'").trim(),'3');
    assert.equal(sql("select count(*) from bookings where arena_id='90000000-0000-4000-8000-000000000002' and court_id is not null").trim(),'2');
    assert.equal(sql("select count(*) from inventory_migration_issues where resolved_at is null").trim(),'1');
    assert.equal(sql("select arena_has_available_court('90000000-0000-4000-8000-000000000002','2035-02-01 10:00+04','2035-02-01 11:00+04')").trim(),'f');
  });
  for(let i=1;i<=8;i++) sql(`insert into auth.users(id,phone,phone_confirmed_at,raw_user_meta_data) values(${q(uid(i))},'9689123400${i}',now(),'{"role":"admin","onboarding_complete":true}');`);
  sql(`insert into admin_users(user_id,active) values(${q(uid(4))},true);`);
  for(let i=1;i<=4;i++)sql(`insert into arenas(id,owner_id,name,location,price_per_hour,opening_time,closing_time,court_count,is_active,audience_gender) values(${q(aid(i))},${q(uid(3))},'Local test','Muscat',10,'08:00','23:00',${i===2?2:1},true,'men');`);
  check('Metadata cannot assign role or completion',()=>assert.equal(sql(`select role||':'||onboarding_complete from profiles where id=${q(uid(1))}`).trim(),'player:false'));
  check('Auth hook allows Oman and rejects other signup',()=>{
    assert.equal(sql(`set role supabase_auth_admin;select before_user_created_oman('{"user":{"phone":"96891234567"}}')`).trim(),'{}');
    assert.match(sql(`set role supabase_auth_admin;select before_user_created_oman('{"user":{"email":"user@example.test"}}')`),/Oman phone signup only/);
    denied(1,`select before_user_created_oman('{}')`);
  });
  for(const i of [1,2])sql(as(i,`select complete_my_profile('Player ${i}','test_user_${i}','2000-01-01','men')`));
  check('Server profile complete without PIN credentials',()=>{
    assert.equal(sql(as(1,'select my_profile_complete()')).trim(),'t');
    assert.equal(sql(`select count(*) from arena_private.profile_credentials`).trim(),'0');
  });
  check('Server rejects non-Oman and unconfirmed phone profiles',()=>{
    sql(`update auth.users set phone='971501234567' where id=${q(uid(7))};update auth.users set phone_confirmed_at=null where id=${q(uid(8))}`);
    for(const i of [7,8])denied(i,"select complete_my_profile('Invalid','invalid_user','2000-01-01','men')",/VERIFIED_OMAN_PHONE_REQUIRED/);
  });
  check('Normal user cannot elevate roles, staff or ownership',()=>{
    denied(1,`update profiles set role='admin' where id=${q(uid(1))}`);
    denied(1,`insert into admin_users(user_id,active) values(${q(uid(1))},true)`);
    denied(1,`insert into owner_stadium_assignments(user_id,stadium_id) values(${q(uid(1))},${q(aid(1))})`);
    denied(1,`update staff_login_accounts set account_type='admin'`);
    assert.equal(sql(as(1,`update arenas set owner_id=${q(uid(1))} where id=${q(aid(1))} returning id`)).trim(),'');
    assert.equal(sql(as(1,'select my_staff_access()')).trim(),'');
  });
  check('Users cannot edit another profile or read credentials',()=>{
    assert.equal(sql(as(1,`update profiles set display_name='Stolen' where id=${q(uid(2))} returning id`)).trim(),'');
    for(const i of [1,3,4])denied(i,'select * from arena_private.profile_credentials');
    denied(1,`update profiles set onboarding_complete=true`);
  });
  check('Direct sensitive writes denied for user, owner and admin',()=>{
    for(const i of [1,3,4])for(const table of ['bookings','matches','match_players','reviews','arena_courts','court_reservations','blocked_slots'])denied(i,`delete from ${table}`);
    denied(1,`insert into bookings(user_id,arena_id,starts_at,ends_at,total_price) values(${q(uid(1))},${q(aid(1))},'2035-01-01 19:30+04','2035-01-01 20:30+04',0)`);
  });
  check('Authoritative owner/admin access',()=>{
    assert.equal(sql(as(3,'select my_staff_access()')).trim(),'stadium_owner');
    assert.equal(sql(as(4,'select my_staff_access()')).trim(),'admin');
    denied(3,`update arenas set owner_id=${q(uid(1))} where id=${q(aid(1))}`);
  });
  check('Disabled staff account cannot use existing ownership',()=>{
    sql(`insert into staff_login_accounts(user_id,username,account_type,active) values(${q(uid(3))},'owner_test','owner',false)`);
    assert.equal(sql(as(3,'select my_staff_access()')).trim(),'');
    assert.equal(sql(as(3,`select is_arena_operator(${q(aid(1))})`)).trim(),'f');
    sql(`update staff_login_accounts set active=true where user_id=${q(uid(3))}`);
  });
  const available = (a,s,e) => sql(as(1,`select arena_has_available_court(${q(aid(a))},'2035-01-01 ${s}+04','2035-01-01 ${e}+04')`)).trim()==='t';
  const booking = (a,s,e,key='gen_random_uuid()') => `select booking_id from create_arena_booking(${q(aid(a))},'2035-01-01 ${s}+04','2035-01-01 ${e}+04',0,${key})`;
  const booked=sql(as(1,booking(1,'19:30','20:30',"'30000000-0000-4000-8000-000000000001'"))).trim();
  check('Idempotent booking retry returns same ID',()=>assert.equal(sql(as(1,booking(1,'19:30','20:30',"'30000000-0000-4000-8000-000000000001'"))).trim(),booked));
  check('Changed payload rejected for same request',()=>assert.throws(()=>sql(as(1,booking(1,'20:30','21:30',"'30000000-0000-4000-8000-000000000001'"))),/IDEMPOTENCY_PAYLOAD_MISMATCH/));
  check('Exact adjacency and half-hour intervals',()=>{
    for(const [s,e] of [['18:30','19:30'],['20:30','21:00'],['08:00','08:30']])assert.equal(available(1,s,e),true);
    for(const [s,e] of [['19:00','20:00'],['20:00','21:00'],['19:00','21:00'],['19:45','20:00']])assert.equal(available(1,s,e),false);
    assert.equal(available(1,'07:30','08:30'),false);assert.equal(available(1,'22:30','23:30'),false);
  });
  check('Availability RPC contains half-hour slots',()=>assert.equal(sql(as(1,`select count(*) from arena_availability(${q(aid(1))},'2035-01-01','2035-01-02')`)).trim(),'48'));
  check('Availability independent of session timezone',()=>assert.equal(sql(as(1,`set timezone='Pacific/Honolulu';select arena_has_available_court(${q(aid(1))},'2035-01-01 19:30+04','2035-01-01 20:30+04')`)).trim(),'f'));
  const reserve=(a,s,e,block=false)=>`select owner_reserve(${q(aid(a))},'2035-01-01 ${s}+04','2035-01-01 ${e}+04','Customer','91234567','Maintenance',${block},gen_random_uuid())`;
  check('Normal user cannot perform owner booking',()=>denied(1,reserve(2,'10:00','11:00')));
  sql(as(3,reserve(2,'10:00','11:00')));
  check('Manual booking leaves second court available',()=>assert.equal(available(2,'10:00','11:00'),true));
  const block=sql(as(3,reserve(2,'10:00','11:00',true))).trim();
  check('Block consumes last court',()=>assert.equal(available(2,'10:00','11:00'),false));
  sql(as(3,`select owner_cancel_block(${q(block)})`));
  check('Cancel block releases capacity',()=>assert.equal(available(2,'10:00','11:00'),true));
  // Staggered courts: each half is available, but no ONE court spans both.
  sql(`insert into blocked_slots(arena_id,court_id,starts_at,ends_at,reason,created_by) select ${q(aid(2))},id,'2035-01-01 14:00+04','2035-01-01 15:00+04','test',${q(uid(3))} from arena_courts where arena_id=${q(aid(2))} and court_number=1;
    insert into blocked_slots(arena_id,court_id,starts_at,ends_at,reason,created_by) select ${q(aid(2))},id,'2035-01-01 15:00+04','2035-01-01 16:00+04','test',${q(uid(3))} from arena_courts where arena_id=${q(aid(2))} and court_number=2;`);
  check('Whole range requires same court',()=>{assert.equal(available(2,'14:00','15:00'),true);assert.equal(available(2,'15:00','16:00'),true);assert.equal(available(2,'14:00','16:00'),false);});
  sql(as(1,`select * from create_arena_match(${q(aid(1))},'Test match','','','football','2035-01-01 12:00+04','2035-01-01 13:00+04',4,false,true,'cash',gen_random_uuid())`));
  check('Match consumes shared booking inventory',()=>assert.equal(available(1,'12:30','13:30'),false));
  sql(`update arenas set is_active=false where id=${q(aid(4))}`);
  check('Inactive arena is unavailable',()=>assert.equal(available(4,'10:00','11:00'),false));
  sql(`update arenas set is_active=true,opening_time='20:00',closing_time='02:00' where id=${q(aid(4))}`);
  check('Overnight operating hours supported',()=>assert.equal(sql(as(1,`select arena_has_available_court(${q(aid(4))},'2035-01-01 23:30+04','2035-01-02 01:30+04')`)).trim(),'t'));
  const results=await parallel([as(1,`begin;${booking(3,'18:00','19:00')};select pg_sleep(0.5);commit;`),as(2,booking(3,'18:00','19:00'))]);
  check('Concurrent last-court bookings: exactly one succeeds',()=>{assert.equal(results.filter(r=>r.ok).length,1);assert.match(results.find(r=>!r.ok).error,/TIME_NO_LONGER_AVAILABLE|conflicting key/);});
  const mixed=await parallel([as(1,`begin;${booking(3,'20:00','21:00')};select pg_sleep(0.5);commit;`),as(3,reserve(3,'20:00','21:00',true))]);
  check('Concurrent booking versus owner block: exactly one succeeds',()=>assert.equal(mixed.filter(r=>r.ok).length,1));
  const match=sql(as(1,`select match_id from create_arena_match(${q(aid(3))},'Private match','','','football','2035-01-02 12:00+04','2035-01-02 13:00+04',4,true,true,'cash',gen_random_uuid())`)).trim();
  check('Private membership cannot bypass invitation',()=>assert.throws(()=>sql(as(2,`select join_match(${q(match)},${q(uid(2))})`)),/INVITATION_REQUIRED/));
  sql(as(1,`select join_match(${q(match)},${q(uid(2))})`));sql(as(2,`select join_match(${q(match)},${q(uid(2))})`));
  check('Host invitation and invited user join still work',()=>assert.equal(sql(as(2,`select status from match_players where match_id=${q(match)} and user_id=${q(uid(2))}`)).trim(),'joined'));
  sql(as(3,`select cancel_arena_booking(${q(booked)},'Local test cancellation')`));
  check('Owner cancellation releases court',()=>assert.equal(available(1,'19:30','20:30'),true));
  const usernames=await parallel([5,6].map(i=>as(i,`begin;select complete_my_profile('Concurrent','same_username','2001-01-01','men');select pg_sleep(0.4);commit;`)));
  check('Concurrent username claim: exactly one succeeds',()=>{assert.equal(usernames.filter(r=>r.ok).length,1);assert.match(usernames.find(r=>!r.ok).error,/duplicate key/);});
  check('Duplicate username rolls back profile without credentials',()=>{assert.equal(sql(`select count(*) from profiles where username='same_username'`).trim(),'1');assert.equal(sql(`select count(*) from arena_private.profile_credentials where user_id in (${q(uid(5))},${q(uid(6))})`).trim(),'0');});
  console.log(`${passed} PostgreSQL integration checks passed (including concurrent clients).`);
};
