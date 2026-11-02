// Refresh existing test sessions on the named Staging only. Never logs credentials.
const fs=require('node:fs');
process.chdir(require('node:path').resolve(__dirname,'../..'));
const path='build/staging-evidence/sessions.local.json';
const url='https://gtcrijikfaglqcwqozel.supabase.co';
const key='sb_publishable_pxaampXaN_YJB3uqB-B3CA_dcYA-glr';
(async()=>{
 const sessions=JSON.parse(fs.readFileSync(path,'utf8'));
 for(let i=0;i<sessions.length;i++){
  const response=await fetch(url+'/auth/v1/token?grant_type=refresh_token',{method:'POST',headers:{apikey:key,'Content-Type':'application/json'},body:JSON.stringify({refresh_token:sessions[i].refresh_token})});
  if(!response.ok)throw Error('Staging test session '+i+' needs sign-in; HTTP '+response.status);
  sessions[i]=await response.json();
  fs.writeFileSync(path,JSON.stringify(sessions));
 }
 console.log('PASS Existing Staging sessions refreshed; credentials remain in ignored build directory.');
})().catch(e=>{console.error(e.message);process.exitCode=1;});
