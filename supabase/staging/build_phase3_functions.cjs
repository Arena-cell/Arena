// Dashboard single-file inputs, generated from checked canonical handlers.
const fs=require('node:fs'),path=require('node:path');
process.chdir(path.resolve(__dirname,'../..'));
fs.mkdirSync('build/phase3-deploy',{recursive:true});
for(const [name,handler] of [['arena-scheduler','arenaSchedulerHandler'],['push-notifications','pushNotificationHandler']]){
 const source=fs.readFileSync('supabase/functions/'+name+'/handler.ts','utf8');
 fs.writeFileSync('build/phase3-deploy/'+name+'.ts',source+`\nDeno.serve(${handler});\n`);
}
console.log('Built two secret-free Staging Edge Function inputs.');
