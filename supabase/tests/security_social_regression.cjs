// LOCAL ONLY. Real PostgreSQL roles/RLS/triggers; storage HTTP/CDN is not emulated.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const db=fs.readFileSync('build/phase1-test-db.txt','utf8').trim();assert.match(db,/^arena_phase1_test_\d+$/);
const exe='C:/Program Files/PostgreSQL/18/bin/psql.exe',args=['-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-qAt'];
function sql(s){try{return cp.execFileSync(exe,args,{input:s,encoding:'utf8',stdio:['pipe','pipe','pipe']}).trim()}catch(e){throw Error(e.stderr.toString())}}
assert(sql('show data_directory').replaceAll('\\','/').endsWith('/playon/build/phase1-pgdata'));
const q=x=>`'${String(x).replaceAll("'","''")}'`,id=()=>crypto.randomUUID();
const a=id(),b=id(),c=id(),ownerB=id(),ownerA='10000000-0000-4000-8000-000000000003',admin='10000000-0000-4000-8000-000000000004',arenaA=id(),arenaB=id(),message=id();
sql(`insert into auth.users(id) values ${[a,b,c,ownerB].map(x=>`(${q(x)})`).join(',')};
insert into profiles(id,display_name) values ${[a,b,c,ownerB].map(x=>`(${q(x)},'LOCAL security fixture')`).join(',')} on conflict do nothing;
insert into arenas(id,owner_id,name,location,price_per_hour,opening_time,closing_time,court_count,audience_gender) values
(${q(arenaA)},${q(ownerA)},'LOCAL security A','Muscat',10,'00:00','23:59',1,'men'),
(${q(arenaB)},${q(ownerB)},'LOCAL security B','Muscat',10,'00:00','23:59',1,'men');`);
const role=u=>`set local role authenticated;set local request.jwt.claim.sub=${q(u)};set local request.jwt.claims=${q(JSON.stringify({sub:u,role:'authenticated'}))};`;
// The historical test cluster has a simplified foldername stub. Correct it
// inside each rollback transaction to the hosted Storage folder semantics.
const prepare=`begin;create or replace function storage.foldername(text) returns text[] language sql immutable as $$select (string_to_array($1,'/'))[1:array_length(string_to_array($1,'/'),1)-1]$$;
grant usage on schema storage to authenticated,anon;grant select,insert,update,delete on storage.objects to authenticated;grant select on storage.objects to anon;
insert into direct_messages(id,sender_id,receiver_id,content) values(${q(message)},${q(a)},${q(b)},'LOCAL message');
insert into storage.objects(bucket_id,name) values('chat-images',${q(a+'/legacy.jpg')}),('chat-images',${q(c+'/other.jpg')}),('stadium-images',${q(ownerA+'/'+arenaA+'/existing.jpg')});
insert into direct_messages(sender_id,receiver_id,image_url) values(${q(a)},${q(b)},${q('https://gtcrijikfaglqcwqozel.supabase.co/storage/v1/object/public/chat-images/'+a+'/legacy.jpg')});`;
let count=0;
function test(name,fn){fn();count++;console.log('PASS '+name)}
function run(u,s,setup=''){return sql(prepare+setup+role(u)+s+';rollback;')}
const denied=(u,s,setup='')=>assert.throws(()=>run(u,s,setup),/permission denied|row-level security|MESSAGE_|FRIEND_|CONTACT_BLOCKED|INVALID_CHAT_ATTACHMENT|PENDING_REQUEST_NOT_FOUND/);
for(const operation of ["update public_profiles set display_name='forged'",`insert into public_profiles(id,display_name) values(${q(id())},'forged')`,'delete from public_profiles'])
 test('public_profiles rejects '+operation.split(' ')[0],()=>denied(a,operation));
test('own allowed profile update works',()=>assert.equal(run(a,`update profiles set display_name='LOCAL own update' where id=${q(a)} returning display_name`),'LOCAL own update'));
test('other profile update changes zero rows',()=>assert.equal(run(a,`with x as(update profiles set display_name='forged' where id=${q(b)} returning id) select count(*) from x`),'0'));
test('profile role escalation rejected',()=>denied(a,"update profiles set role='admin'"));
test('public profile projection remains readable',()=>assert.equal(run(a,`select count(*) from public_profiles where id=${q(b)}`),'1'));
test('private profile hidden from unrelated player',()=>assert.equal(run(a,`select count(*) from public_profiles where id=${q(b)}`,`insert into user_preferences(user_id,private_profile) values(${q(b)},true);`),'0'));
test('private profile visible to its user',()=>assert.equal(run(b,`select count(*) from public_profiles where id=${q(b)}`,`insert into user_preferences(user_id,private_profile) values(${q(b)},true);`),'1'));
test('private profile visible to authorized admin',()=>assert.equal(run(admin,`select count(*) from public_profiles where id=${q(b)}`,`insert into user_preferences(user_id,private_profile) values(${q(b)},true);`),'1'));
const privateBooking=`insert into user_preferences(user_id,private_profile) values(${q(b)},true);
insert into bookings(user_id,arena_id,starts_at,ends_at,total_price,status) values(${q(b)},${q(arenaA)},'2039-02-01 10:00+04','2039-02-01 11:00+04',10,'cancelled');`;
test('related owner retains necessary private profile access',()=>assert.equal(run(ownerA,`select count(*) from public_profiles where id=${q(b)}`,privateBooking),'1'));
test('unrelated owner has no private profile access',()=>assert.equal(run(ownerB,`select count(*) from public_profiles where id=${q(b)}`,privateBooking),'0'));
test('message sender reads',()=>assert.equal(run(a,`select count(*) from direct_messages where id=${q(message)}`),'1'));
test('message recipient reads',()=>assert.equal(run(b,`select count(*) from direct_messages where id=${q(message)}`),'1'));
test('outsider cannot read message',()=>assert.equal(run(c,`select count(*) from direct_messages where id=${q(message)}`),'0'));
test('recipient marks read with server time',()=>assert.equal(run(b,`update direct_messages set read_at='2099-01-01' where id=${q(message)} returning read_at<clock_timestamp()+interval '1 second'`),'t'));
test('sender cannot mark recipient read',()=>assert.equal(run(a,`with x as(update direct_messages set read_at=now() where id=${q(message)} returning id) select count(*) from x`),'0'));
for(const field of ["content='forged'",`sender_id=${q(b)}`,`receiver_id=${q(c)}`,"created_at=now()"])
 test('recipient cannot rewrite '+field.split('=')[0],()=>denied(b,`update direct_messages set ${field} where id=${q(message)}`));
test('sender cannot edit text',()=>denied(a,`update direct_messages set content='edit' where id=${q(message)}`));
test('shared message cannot be globally deleted',()=>denied(a,`delete from direct_messages where id=${q(message)}`));
test('legitimate send works',()=>assert.equal(run(a,`insert into direct_messages(sender_id,receiver_id,content) values(${q(a)},${q(b)},'hello') returning content`),'hello'));
test('spoofed sender rejected',()=>denied(c,`insert into direct_messages(sender_id,receiver_id,content) values(${q(a)},${q(b)},'forged')`));
for(const [blocker,blocked] of [[a,b],[b,a]]) {
 const block=`insert into user_blocks(blocker_id,blocked_id) values(${q(blocker)},${q(blocked)});`;
 test('message blocked from either side '+blocker,()=>denied(a,`insert into direct_messages(sender_id,receiver_id,content) values(${q(a)},${q(b)},'blocked')`,block));
 test('friend request blocked from either side '+blocker,()=>denied(a,`insert into friend_requests(sender_id,receiver_id) values(${q(a)},${q(b)})`,block));
}
test('cannot remove another users block',()=>assert.equal(run(a,`with x as(delete from user_blocks where blocker_id=${q(b)} returning blocker_id) select count(*) from x`,`insert into user_blocks(blocker_id,blocked_id) values(${q(b)},${q(a)});`),'0'));
test('friend pending request allowed',()=>assert.equal(run(a,`insert into friend_requests(sender_id,receiver_id) values(${q(a)},${q(b)}) returning status`),'pending'));
test('friend preaccepted insert rejected',()=>denied(a,`insert into friend_requests(sender_id,receiver_id,status) values(${q(a)},${q(b)},'accepted')`));
const pending=role(a)+`insert into friend_requests(sender_id,receiver_id) values(${q(a)},${q(b)});reset role;`;
test('sender cannot approve own request',()=>denied(a,"update friend_requests set status='accepted'",pending));
test('recipient can accept via RPC',()=>assert.equal(run(b,`select respond_friend_request(${q(a)},true);select status from friend_requests where sender_id=${q(a)}`,pending),'accepted'));
test('recipient can decline via RPC',()=>assert.equal(run(b,`select respond_friend_request(${q(a)},false);select status from friend_requests where sender_id=${q(a)}`,pending),'declined'));
test('unrelated account cannot accept request',()=>denied(c,`select respond_friend_request(${q(a)},true)`,pending));
test('request parties immutable',()=>denied(a,`update friend_requests set receiver_id=${q(c)}`,pending));
test('own pending upsert remains usable',()=>assert.equal(run(a,`insert into friend_requests(sender_id,receiver_id,status) values(${q(a)},${q(b)},'pending') on conflict(sender_id,receiver_id) do update set status='pending' returning status`,pending),'pending'));
test('real client friendship retry uses RPC without immutable-column upsert',()=>assert.equal(run(a,`select request_friendship(${q(b)})`,pending),'pending'));
test('friendship request RPC does not reset an accepted friendship',()=>assert.equal(run(a,`select request_friendship(${q(b)})`,pending+role(b)+`select respond_friend_request(${q(a)},true);reset role;`),'accepted'));
test('chat bucket private',()=>assert.equal(sql("select not public from storage.buckets where id='chat-images'"),'t'));
test('chat legacy URL recipient gets object metadata',()=>assert.equal(run(b,`select count(*) from storage.objects where bucket_id='chat-images' and name=${q(a+'/legacy.jpg')}`),'1'));
test('chat uploader reads own upload',()=>assert.equal(run(a,`select count(*) from storage.objects where bucket_id='chat-images' and name=${q(a+'/legacy.jpg')}`),'1'));
test('chat unrelated account cannot read object',()=>assert.equal(run(c,`select count(*) from storage.objects where bucket_id='chat-images' and name=${q(a+'/legacy.jpg')}`),'0'));
test('admin has no blanket access to private chat images',()=>assert.equal(run(admin,`select count(*) from storage.objects where bucket_id='chat-images' and name=${q(a+'/legacy.jpg')}`),'0'));
const group=id(),groupSetup=`insert into chat_groups(id,owner_id,name) values(${q(group)},${q(a)},'LOCAL privacy group');
insert into chat_group_members(group_id,user_id) values(${q(group)},${q(a)}),(${q(group)},${q(b)}) on conflict do nothing;
insert into storage.objects(bucket_id,name) values('chat-images',${q(a+'/group.jpg')});
insert into group_messages(group_id,sender_id,image_url) values(${q(group)},${q(a)},${q('chat-images/'+a+'/group.jpg')});`;
test('group image remains accessible to member',()=>assert.equal(run(b,`select count(*) from storage.objects where bucket_id='chat-images' and name=${q(a+'/group.jpg')}`,groupSetup),'1'));
test('group image denied to nonmember',()=>assert.equal(run(c,`select count(*) from storage.objects where bucket_id='chat-images' and name=${q(a+'/group.jpg')}`,groupSetup),'0'));
test('former group member cannot request image access',()=>assert.equal(run(b,`select count(*) from storage.objects where bucket_id='chat-images' and name=${q(a+'/group.jpg')}`,groupSetup+`delete from chat_group_members where group_id=${q(group)} and user_id=${q(b)};`),'0'));
test('direct block does not change existing group text policy',()=>assert.equal(run(b,`insert into group_messages(group_id,sender_id,content) values(${q(group)},${q(b)},'LOCAL existing group behavior') returning content`,groupSetup+`insert into user_blocks(blocker_id,blocked_id) values(${q(a)},${q(b)});`),'LOCAL existing group behavior'));
test('cannot forge attachment to gain access',()=>denied(b,`insert into direct_messages(sender_id,receiver_id,image_url) values(${q(b)},${q(c)},${q('chat-images/'+a+'/legacy.jpg')})`));
test('new private attachment works',()=>assert.equal(run(a,`insert into direct_messages(sender_id,receiver_id,image_url) values(${q(a)},${q(b)},${q('chat-images/'+a+'/legacy.jpg')}) returning image_url`),'chat-images/'+a+'/legacy.jpg'));
test('own direct upload cannot bypass deep validation',()=>denied(a,`insert into storage.objects(bucket_id,name) values('chat-images',${q(a+'/new.jpg')})`));
test('cannot upload under another user',()=>denied(b,`insert into storage.objects(bucket_id,name) values('chat-images',${q(a+'/new.jpg')})`));
for(const [user,arena,allowed,label] of [[ownerA,arenaA,true,'owner A own'],[ownerB,arenaB,true,'owner B own'],[ownerA,arenaB,false,'owner A other'],[ownerB,arenaA,false,'owner B other'],[a,arenaA,false,'player'],[admin,arenaA,true,'admin']]) {
 const path=user+'/'+arena+'/new.jpg';
 test('stadium server authorization '+label,()=>{assert.equal(run(user,`select can_manage_stadium_image(${q(path)})`),allowed?'t':'f');denied(user,`insert into storage.objects(bucket_id,name) values('stadium-images',${q(path)})`)});
}
test('stadium helper rejects invalid arena',()=>assert.equal(run(admin,`select can_manage_stadium_image(${q(admin+'/'+id()+'/new.jpg')})`),'f'));
test('stadium own direct replacement cannot bypass decoder',()=>assert.equal(run(ownerA,`with x as(update storage.objects set name=${q(ownerA+'/'+arenaA+'/renamed.jpg')} where bucket_id='stadium-images' and name=${q(ownerA+'/'+arenaA+'/existing.jpg')} returning name) select count(*) from x`),'0'));
test('stadium cannot move own image into other arena',()=>assert.equal(run(ownerA,`with x as(update storage.objects set name=${q(ownerA+'/'+arenaB+'/forged.jpg')} where bucket_id='stadium-images' and name=${q(ownerA+'/'+arenaA+'/existing.jpg')} returning name) select count(*) from x`),'0'));
test('own arena image deletion remains authorized',()=>assert.equal(run(ownerA,`delete from storage.objects where bucket_id='stadium-images' and name=${q(ownerA+'/'+arenaA+'/existing.jpg')} returning name`),ownerA+'/'+arenaA+'/existing.jpg'));
test('other owner cannot delete arena image',()=>assert.equal(run(ownerB,`with x as(delete from storage.objects where bucket_id='stadium-images' and name=${q(ownerA+'/'+arenaA+'/existing.jpg')} returning name) select count(*) from x`),'0'));
for(const [bucket,limit] of [['avatars',3145728],['chat-images',5242880],['stadium-images',10485760]])test('bucket size and MIME policy '+bucket,()=>assert.equal(sql(`select file_size_limit=${limit} and allowed_mime_types=array['image/jpeg','image/png','image/webp'] from storage.buckets where id=${q(bucket)}`),'t'));
test('anonymous chat read is denied',()=>assert.equal(sql(prepare+"set local role anon;select count(*) from storage.objects where bucket_id='chat-images';rollback;"),'0'));
console.log(count+' security tests passed');
