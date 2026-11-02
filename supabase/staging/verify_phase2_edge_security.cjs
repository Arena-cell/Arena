const fs=require('node:fs'),assert=require('node:assert/strict');
process.chdir(require('node:path').resolve(__dirname,'../..'));
const token=JSON.parse(fs.readFileSync('build/staging-evidence/sessions.local.json','utf8'))[0].access_token;
const base='https://gtcrijikfaglqcwqozel.supabase.co/functions/v1/';
(async()=>{
 for(const name of ['thawani-webhook','payment-reconcile']){
  const r=await fetch(base+name,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:'{}'});
  assert.ok(r.status>=400&&r.status<600,name+' must reject an ordinary user JWT without signature/job secret');
  console.log('PASS '+name+' rejects user request without its server credential; HTTP '+r.status);
 }
})().catch(e=>{console.error(e.message);process.exitCode=1;});
