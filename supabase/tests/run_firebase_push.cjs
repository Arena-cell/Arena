// Isolated PostgreSQL only. No hosted credentials or provider success fakes.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict');
process.chdir(require('node:path').resolve(__dirname,'../..'));
const db=fs.readFileSync('build/phase1-test-db.txt','utf8').trim();
if(!/^arena_phase1_test_\d+$/.test(db))throw Error('LOCAL_DATABASE_REQUIRED');
const args=['-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',db,'-qAt','-v','ON_ERROR_STOP=1'];
function sql(s){try{return cp.execFileSync('C:/Program Files/PostgreSQL/18/bin/psql.exe',args,{input:s,encoding:'utf8',stdio:['pipe','pipe','pipe']}).trim();}catch(e){throw Error(e.stderr.toString());}}
const u='fcm00000'; // UUIDs below deliberately independent of earlier fixtures.
const a='f309f000-0000-4000-8000-000000000001',b='f309f000-0000-4000-8000-000000000002';
const as=(id,s)=>`set role authenticated;set request.jwt.claim.sub='${id}';${s}`;
let count=0;const test=(name,fn)=>{fn();console.log('PASS '+name);count++;};
sql(`insert into auth.users(id,phone,phone_confirmed_at) values('${a}','96899001001',now()),('${b}','96899001002',now());`);
test('Multiple own devices',()=>{sql(as(a,`insert into device_tokens(user_id,token,platform) values('${a}','firebase-test-device-a','android'),('${a}','firebase-test-device-b','ios');`));assert.equal(sql(as(a,'select count(*) from device_tokens')),'2');});
test('Another account cannot see tokens',()=>assert.equal(sql(as(b,'select count(*) from device_tokens')),'0'));
test('Another account cannot register token for victim',()=>assert.throws(()=>sql(as(b,`insert into device_tokens(user_id,token,platform) values('${a}','forged','android')`)),/row-level security/));
test('Another account cannot deactivate victim',()=>{sql(as(b,`update device_tokens set is_active=false where user_id='${a}'`));assert.equal(sql(`select count(*) from device_tokens where user_id='${a}' and is_active`),'2');});
test('Token refresh/reactivation',()=>{sql(as(a,`update device_tokens set is_active=false where token='firebase-test-device-a';update device_tokens set token='firebase-test-refreshed',is_active=true where token='firebase-test-device-a'`));assert.equal(sql(as(a,"select count(*) from device_tokens where token='firebase-test-refreshed' and is_active")),'1');});
test('Logout removes only this device',()=>{sql(as(a,"delete from device_tokens where token='firebase-test-refreshed'"));assert.equal(sql(as(a,'select count(*) from device_tokens')),'1');});
test('Unauthenticated cannot see tokens',()=>assert.equal(sql('set role anon;select count(*) from device_tokens'),'0'));
test('Users cannot enqueue forged financial notification',()=>assert.throws(()=>sql(as(a,`insert into notifications(user_id,type,title,body) values('${b}','payment_confirmed','fake','fake')`)),/permission denied/));
test('Worker claims denied to users',()=>assert.throws(()=>sql(as(a,'select claim_arena_push_batch(1)')),/permission denied/));
const arena=sql('select id from arenas order by id limit 1');
sql(`update arenas set owner_id='${a}' where id='${arena}';select arena_private.notify('${b}','stadium_update','firebase-owner-event',jsonb_build_object('arena_id','${arena}'),'update','update');`);
test('Assigned owner receives existing inbox event',()=>assert.equal(sql(`select count(*) from notifications where user_id='${a}' and event_key='owner:firebase-owner-event'`),'1'));
test('Repeated event produces one owner notification',()=>{sql(`select arena_private.notify('${b}','stadium_update','firebase-owner-event',jsonb_build_object('arena_id','${arena}'),'update','update')`);assert.equal(sql(`select count(*) from notifications where event_key='owner:firebase-owner-event'`),'1');});
test('No recursive owner fanout',()=>assert.equal(sql(`select count(*) from notifications where event_key like 'owner:owner:%'`),'0'));
console.log(`FIREBASE SQL: ${count} PASS`);
