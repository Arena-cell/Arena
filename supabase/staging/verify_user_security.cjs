const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const sessions=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../../build/staging-evidence/sessions.local.json')));
const url='https://gtcrijikfaglqcwqozel.supabase.co';
const key='sb_publishable_pxaampXaN_YJB3uqB-B3CA_dcYA-glr';
async function req(route,method='GET',body,user=0) {
  const r=await fetch(url+'/rest/v1/'+route,{method,headers:{apikey:key,Authorization:`Bearer ${sessions[user].access_token}`,'Content-Type':'application/json',Prefer:'return=representation'},...(body===undefined?{}:{body:JSON.stringify(body)})});
  const text=await r.text(); return {status:r.status,data:text?JSON.parse(text):null};
}
async function denied(label,route,method,body,user=0) {
  const r=await req(route,method,body,user);
  assert.ok(r.status>=400,label+': '+JSON.stringify(r));
  console.log('PASS '+label);
}
(async()=>{
  const me=await req('profiles?select=id,role,onboarding_complete');
  assert.equal(me.status,200);assert.equal(me.data.length,1);
  assert.equal(me.data[0].id,sessions[0].user.id);
  assert.equal(me.data[0].role,'player');
  console.log('PASS auth.uid()-scoped profile RLS and player role');
  await denied('role escalation','profiles?id=eq.'+sessions[0].user.id,'PATCH',{role:'admin'});
  await denied('completion escalation','profiles?id=eq.'+sessions[0].user.id,'PATCH',{onboarding_complete:true});
  await denied('admin insertion','admin_users','POST',{user_id:sessions[0].user.id,active:true});
  await denied('direct booking insertion','bookings','POST',{user_id:sessions[0].user.id});
  await denied('Auth hook inaccessible to clients','rpc/staging_deny_real_sms','POST',{event:{}});
  const other=await req('profiles?id=eq.'+sessions[1].user.id+'&select=id');
  assert.deepEqual(other.data,[]);console.log('PASS other user profile hidden');
  const complete=await req('rpc/complete_my_profile','POST',{p_display_name:'Staging Player B',p_username:'stage_test_b',p_date_of_birth:'2000-01-01',p_gender:'men'},1);
  assert.ok([200,204].includes(complete.status) || complete.data?.message==='PROFILE_ALREADY_COMPLETE',JSON.stringify(complete));
  const state=await req('rpc/my_profile_complete','POST',{},1);
  assert.equal(state.data,true);console.log('PASS completed profile recognized without PIN parameter');
  const before=await req('rpc/my_profile_complete','POST',{});
  await denied(before.data ? 'completed profile cannot be overwritten' : 'case-insensitive username uniqueness','rpc/complete_my_profile','POST',{p_display_name:'Staging Player A',p_username:'STAGE_TEST_B',p_date_of_birth:'2000-01-01',p_gender:'men'});
  const a=await req('rpc/my_profile_complete','POST',{});
  assert.equal(a.data,before.data);console.log('PASS rejected profile update preserves completion state');
})().catch(e=>{console.error(e.message);process.exitCode=1});
