// LOCAL ONLY: synthetic token strings, no FCM connection and no device data.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const db=fs.readFileSync('build/phase1-test-db.txt','utf8').trim();assert.match(db,/^arena_phase1_test_\d+$/);
const exe='C:/Program Files/PostgreSQL/18/bin/psql.exe',args=['-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-qAt'];
function sql(s){try{return cp.execFileSync(exe,args,{input:s,encoding:'utf8',stdio:['pipe','pipe','pipe']}).trim()}catch(e){throw Error(e.stderr.toString())}}
assert(sql('show data_directory').replaceAll('\\','/').endsWith('/playon/build/phase1-pgdata'));
const a=crypto.randomUUID(),b=crypto.randomUUID(),event=crypto.randomUUID(),token='LOCAL_TOKEN_'+crypto.randomUUID(),q=x=>`'${String(x).replaceAll("'","''")}'`;
sql(`insert into auth.users(id) values(${q(a)}),(${q(b)});`);
const setup=`begin;insert into device_tokens(user_id,token,platform) values(${q(a)},${q(token)},'android');
select arena_private.notify(${q(a)},'stadium_update',${q(event)},'{}','LOCAL notification','LOCAL only');`;
const role=u=>`set local role authenticated;set local request.jwt.claim.sub=${q(u)};`;
const run=(u,s)=>sql(setup+role(u)+s+';rollback;').split(/\r?\n/).filter(Boolean).at(-1)??'';
let count=0;const test=(name,fn)=>{fn();count++;console.log('PASS '+name)};
test('own token visible',()=>assert.equal(run(a,'select count(*) from device_tokens'),'1'));
test('another account cannot read token',()=>assert.equal(run(b,'select count(*) from device_tokens'),'0'));
test('cannot register destination for another user',()=>assert.throws(()=>run(b,`insert into device_tokens(user_id,token,platform) values(${q(a)},'LOCAL_FORGED','android')`),/row-level security/));
test('cannot deactivate another users token',()=>assert.equal(run(b,`with x as(update device_tokens set is_active=false where user_id=${q(a)} returning id) select count(*) from x`),'0'));
test('cannot remove another users token',()=>assert.equal(run(b,`with x as(delete from device_tokens where user_id=${q(a)} returning id) select count(*) from x`),'0'));
test('own logout removes only own registration',()=>assert.equal(run(a,`with x as(delete from device_tokens where token=${q(token)} returning id) select count(*) from x`),'1'));
test('unauthenticated cannot see token',()=>assert.equal(sql(setup+'set local role anon;select count(*) from device_tokens;rollback;').split(/\r?\n/).filter(Boolean).at(-1),'0'));
test('own inbox visible',()=>assert.equal(run(a,`select count(*) from notifications where event_key=${q(event)}`),'1'));
test('other account cannot read inbox',()=>assert.equal(run(b,`select count(*) from notifications where event_key=${q(event)}`),'0'));
test('other account cannot mark notification read',()=>assert.equal(run(b,`with x as(update notifications set read_at=now() where event_key=${q(event)} returning id) select count(*) from x`),'0'));
test('own notification read marker works',()=>assert.equal(run(a,`update notifications set read_at=now() where event_key=${q(event)} returning read_at is not null`),'t'));
test('client cannot forge notification content',()=>assert.throws(()=>run(a,"update notifications set title='forged'"),/permission denied/));
test('client cannot send a push on behalf of another user',()=>assert.throws(()=>run(b,`insert into notifications(user_id,type,title,body) values(${q(a)},'stadium_update','forged','forged')`),/permission denied/));
test('client cannot claim push worker jobs',()=>assert.throws(()=>run(a,'select claim_arena_push_batch(1)'),/permission denied/));
console.log(count+' token/inbox security tests passed');
