// Dashboard single-file build. Canonical source is checked by deno check first.
const fs=require('node:fs'),cp=require('node:child_process'),path=require('node:path');
process.chdir(path.resolve(__dirname,'../..'));
fs.mkdirSync('build/phase2-deploy',{recursive:true});
const provider=fs.readFileSync('supabase/functions/_shared/thawani.mjs','utf8').replaceAll('export ','');
const shared=fs.readFileSync('supabase/functions/_shared/payments.ts','utf8').replace(/^import .*from '\.\/thawani.mjs';\r?\n/m,'').replace(/^export \{.*\};\r?\n/m,'').replaceAll('export ','');
for(const name of ['arena-payment','thawani-webhook','payment-reconcile']){
 const entry=fs.readFileSync('supabase/functions/'+name+'/index.ts','utf8').replace(/^import .*;\r?\n/gm,'');
 fs.writeFileSync('build/phase2-deploy/'+name+'.ts',provider+'\n'+shared+'\n'+entry);
}
console.log('Generated dashboard inputs. Transpile with esbuild; do not edit generated files.');
