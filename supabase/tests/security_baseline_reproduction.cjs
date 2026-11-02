// Intentionally reproduces the CURRENT hosted pre-fix ACL/policies locally.
// All permission changes and fixture writes are inside ROLLBACK transactions.
// NEVER contacts Staging; this is evidence of baseline behavior, not a pass.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const db=fs.readFileSync('build/phase1-test-db.txt','utf8').trim();assert.match(db,/^arena_phase1_test_\d+$/);
const exe='C:/Program Files/PostgreSQL/18/bin/psql.exe',args=['-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-qAt'];
const sql=s=>cp.execFileSync(exe,args,{input:s,encoding:'utf8',stdio:['pipe','pipe','pipe']}).trim(),q=s=>`'${String(s).replaceAll("'","''")}'`;
assert(sql('show data_directory').replaceAll('\\','/').endsWith('/playon/build/phase1-pgdata'));
const a=crypto.randomUUID(),b=crypto.randomUUID();sql(`insert into auth.users(id) values(${q(a)}),(${q(b)});`);
const role=u=>`set local role authenticated;set local request.jwt.claim.sub=${q(u)};`;
let count=0;const proof=(id,fn)=>{fn();count++;console.log('BASELINE REPRODUCED '+id+' (rolled back)')};
proof('SEC-01 cross-profile view UPDATE',()=>assert.equal(sql(`begin;grant update on public_profiles to authenticated;${role(a)}with x as(update public_profiles set display_name='LOCAL BASELINE ONLY' where id=${q(b)} returning id) select count(*) from x;rollback;`),'1'));
const oldMessages=`begin;alter table direct_messages disable trigger security_guard_direct_message;
drop policy "direct participants read" on direct_messages;drop policy "direct sender inserts" on direct_messages;drop policy "direct recipient marks read" on direct_messages;
grant all on direct_messages to authenticated;
create policy "local old message policy" on direct_messages for all using(auth.uid() in(sender_id,receiver_id)) with check(auth.uid()=sender_id);`;
proof('SEC-03 receiver rewrite',()=>{
 const id=crypto.randomUUID();assert.equal(sql(oldMessages+role(a)+`insert into direct_messages(id,sender_id,receiver_id,content) values(${q(id)},${q(a)},${q(b)},'LOCAL ONLY');reset role;`+role(b)+`with x as(update direct_messages set sender_id=${q(b)},receiver_id=${q(a)},content='LOCAL REWRITTEN' where id=${q(id)} returning id) select count(*) from x;rollback;`),'1');
});
proof('SEC-04 blocked direct send',()=>assert.equal(sql(oldMessages+`insert into user_blocks(blocker_id,blocked_id) values(${q(b)},${q(a)});`+role(a)+`with x as(insert into direct_messages(sender_id,receiver_id,content) values(${q(a)},${q(b)},'LOCAL BLOCKED BASELINE') returning id) select count(*) from x;rollback;`),'1'));
proof('SEC-05 self-approved friendship',()=>assert.equal(sql(`begin;alter table friend_requests disable trigger security_guard_friend_request;
drop policy "friend participants read" on friend_requests;drop policy "friend sender requests" on friend_requests;drop policy "friend participants update" on friend_requests;drop policy "friend participants remove" on friend_requests;
grant all on friend_requests to authenticated;
create policy "local old friend policy" on friend_requests for all using(auth.uid() in(sender_id,receiver_id)) with check(auth.uid()=sender_id);
${role(a)}insert into friend_requests(sender_id,receiver_id,status) values(${q(a)},${q(b)},'accepted');select status from friend_requests where sender_id=${q(a)};rollback;`),'accepted'));
console.log(count+' pre-fix baseline behaviors reproduced locally; no permissions persisted');
