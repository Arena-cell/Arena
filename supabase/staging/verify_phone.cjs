// Public-client, hosted Staging test. Never accepts a production target.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const path = require('node:path');
const url = 'https://gtcrijikfaglqcwqozel.supabase.co';
const key = 'sb_publishable_pxaampXaN_YJB3uqB-B3CA_dcYA-glr';
async function request(route, body, token) {
  const response = await fetch(url + route, {
    method: body === undefined ? 'GET' : 'POST',
    headers: {apikey:key, 'Content-Type':'application/json', ...(token ? {Authorization:`Bearer ${token}`} : {})},
    ...(body === undefined ? {} : {body:JSON.stringify(body)})
  });
  return {status:response.status, data:await response.json()};
}
(async () => {
  const settings = await request('/auth/v1/settings');
  assert.equal(settings.data.external.phone,true);
  assert.equal(settings.data.phone_autoconfirm,false);
  console.log('PASS Phone enabled; confirmation required');
  const sessions = [];
  for (const [phone,code] of [['96891234567','123456'],['96891234568','234567']]) {
    const sent = await request('/auth/v1/otp',{phone,create_user:true,data:{role:'admin',onboarding_complete:true}});
    assert.equal(sent.status,200,JSON.stringify(sent));
    const wrong = await request('/auth/v1/verify',{phone,token:'999999',type:'sms'});
    assert.ok(wrong.status>=400,'Incorrect OTP must be rejected');
    const verified = await request('/auth/v1/verify',{phone,token:code,type:'sms'});
    assert.equal(verified.status,200,JSON.stringify(verified));
    assert.ok(verified.data.access_token && verified.data.refresh_token);
    const claims = JSON.parse(Buffer.from(verified.data.access_token.split('.')[1],'base64url'));
    assert.equal(claims.iss,url+'/auth/v1');
    assert.equal(claims.sub,verified.data.user.id);
    const me = await request('/auth/v1/user',undefined,verified.data.access_token);
    assert.equal(me.status,200);
    assert.equal(me.data.id,claims.sub);
    const staff = await request('/rest/v1/rpc/my_staff_access',{},verified.data.access_token);
    assert.equal(staff.status,200,JSON.stringify(staff));
    assert.ok(!staff.data,'Metadata must not grant staff access');
    console.log(`PASS real Auth session, wrong OTP rejection, metadata escalation denied: ${phone}`);
    sessions.push(verified.data);
  }
  const dir = path.resolve(__dirname,'../../build/staging-evidence');
  fs.mkdirSync(dir,{recursive:true});
  fs.writeFileSync(path.join(dir,'sessions.local.json'),JSON.stringify(sessions));
  const blocked = await request('/auth/v1/otp',{phone:'96891234570',create_user:true});
  assert.ok(blocked.status>=400);
  assert.match(JSON.stringify(blocked.data),/Staging permits configured/);
  console.log('PASS non-test phone rejected by SMS hook; no SMS provider used');
})().catch(error=>{console.error(error.message);process.exitCode=1;});
