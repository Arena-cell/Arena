// LOCAL ONLY. Separate PostgreSQL connections and transaction barriers.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const db=fs.readFileSync('build/phase1-test-db.txt','utf8').trim();assert.match(db,/^arena_phase1_test_\d+$/);
const exe='C:/Program Files/PostgreSQL/18/bin/psql.exe',args=['-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-qAt'];
const q=s=>`'${String(s).replaceAll("'","''")}'`,id=()=>crypto.randomUUID();
const sql=s=>cp.execFileSync(exe,args,{input:s,encoding:'utf8',stdio:['pipe','pipe','pipe']}).trim();
assert(sql('show data_directory').replaceAll('\\','/').endsWith('/playon/build/phase1-pgdata'));
const role=user=>`set local role authenticated;set local request.jwt.claim.sub=${q(user)};set local request.jwt.claims=${q(JSON.stringify({sub:user,role:'authenticated',aal:'aal1'}))};`;
function fixture(){const a=id(),b=id();sql(`insert into auth.users(id) values(${q(a)}),(${q(b)});`);return {a,b}}
function connection(query){
 const child=cp.spawn(exe,args),out=[],err=[];let ready;
 const started=new Promise(resolve=>ready=resolve);
 child.stdout.on('data',data=>{out.push(data.toString());if(out.join('').includes('READY'))ready()});child.stderr.on('data',data=>err.push(data.toString()));
 const done=new Promise((resolve,reject)=>{child.on('error',reject);child.on('close',code=>{ready();resolve({ok:code===0,out:out.join('').trim(),error:err.join('')})})});
 child.stdin.end(query);return {started,done};
}
let count=0;
async function test(name,fn){await fn();count++;console.log('PASS '+name)}
(async()=>{
 for(const reverse of [false,true])await test('committed block defeats concurrent send '+reverse,async()=>{
  const {a,b}=fixture();const blocker=reverse?b:a,blocked=reverse?a:b;
  const first=connection(`begin;${role(blocker)}insert into user_blocks(blocker_id,blocked_id) values(${q(blocker)},${q(blocked)});select 'READY';select pg_sleep(0.3);commit;`);
  await first.started;
  const second=connection(`begin;${role(a)}insert into direct_messages(sender_id,receiver_id,content) values(${q(a)},${q(b)},'LOCAL RACE');commit;`);
  assert((await first.done).ok);const result=await second.done;assert(!result.ok);assert.match(result.error,/CONTACT_BLOCKED/);
  assert.equal(sql(`select count(*) from direct_messages where sender_id=${q(a)} and receiver_id=${q(b)}`),'0');
 });
 await test('send before block commits once; later sends rejected',async()=>{
  const {a,b}=fixture();const first=connection(`begin;${role(a)}insert into direct_messages(sender_id,receiver_id,content) values(${q(a)},${q(b)},'LOCAL BEFORE BLOCK');select 'READY';select pg_sleep(0.3);commit;`);
  await first.started;const second=connection(`begin;${role(b)}insert into user_blocks(blocker_id,blocked_id) values(${q(b)},${q(a)});commit;`);
  assert((await first.done).ok);assert((await second.done).ok);
  assert.equal(sql(`select count(*) from direct_messages where sender_id=${q(a)} and receiver_id=${q(b)}`),'1');
  const late=await connection(`begin;${role(a)}insert into direct_messages(sender_id,receiver_id,content) values(${q(a)},${q(b)},'LOCAL LATE');commit;`).done;
  assert(!late.ok);assert.match(late.error,/CONTACT_BLOCKED/);
 });
 await test('block serializes with friend request',async()=>{
  const {a,b}=fixture();const first=connection(`begin;${role(b)}insert into user_blocks(blocker_id,blocked_id) values(${q(b)},${q(a)});select 'READY';select pg_sleep(0.3);commit;`);
  await first.started;const second=connection(`begin;${role(a)}insert into friend_requests(sender_id,receiver_id) values(${q(a)},${q(b)});commit;`);
  assert((await first.done).ok);const result=await second.done;assert(!result.ok);assert.match(result.error,/CONTACT_BLOCKED/);
 });
 await test('same backup code cannot be consumed concurrently twice',async()=>{
  const user=id(),code='cd'.repeat(16);
  sql(`insert into auth.users(id) values(${q(user)});insert into admin_users(user_id) values(${q(user)});
  insert into arena_private.admin_mfa_state(user_id) values(${q(user)});
  insert into arena_private.admin_mfa_recovery_codes(user_id,code_hash) values(${q(user)},extensions.digest(${q(user+':'+code)},'sha256'));`);
  const first=connection(`begin;${role(user)}select begin_admin_mfa_recovery(${q(code)})->>'ok';select 'READY';select pg_sleep(0.3);commit;`);
  await first.started;const second=connection(`begin;${role(user)}select begin_admin_mfa_recovery(${q(code)})->>'ok';commit;`);
  const a=await first.done,b=await second.done;assert(a.ok&&b.ok);assert.match(a.out,/true/);assert.equal(b.out,'false');
 });
 console.log(count+' security concurrency tests passed');
})().catch(error=>{console.error(error.message);process.exitCode=1});
