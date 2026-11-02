const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
process.chdir(path.resolve(__dirname,'../..'));
const after=process.argv.find(a=>a.startsWith('--after='))?.slice(8);
if(after&&!/^(20261008010[1-8]|20261009010[2-3])$/.test(after))throw Error('Invalid applied baseline');
const files=fs.readdirSync('supabase/migrations').filter(f=>f.includes('_phase3_')&&(!after||f.split('_')[0]>after)).sort();
if(new Set(files.map(f=>f.split('_')[0])).size!==files.length)throw Error('Duplicate versions');
fs.mkdirSync('build/phase3-evidence',{recursive:true});
const checks=files.map(f=>({file:f,sha256:crypto.createHash('sha256').update(fs.readFileSync('supabase/migrations/'+f)).digest('hex')}));
let sql=`-- Arena Staging ONLY: gtcrijikfaglqcwqozel. Atomic new migrations, no prior migration reruns.\nbegin;
do $$ begin
 if not exists(select 1 from arena_private.staging_installation where version='202610080001') then raise exception 'PHASE2_BASELINE_REQUIRED';end if;
 ${after?`if not exists(select 1 from arena_private.staging_installation where version='${after}') then raise exception 'PHASE3_BASELINE_REQUIRED';end if;`:`if exists(select 1 from arena_private.staging_installation where version like '20261008010%') then raise exception 'PHASE3_ALREADY_INSTALLED';end if;`}
 if not exists(select 1 from arena_private.phase3_backup_20261008) then raise exception 'BACKUP_REQUIRED';end if;
 ${files.some(f=>f.startsWith('20261009'))?"if to_regclass('arena_private.refund_policy_backup_20261009') is null then raise exception 'REFUND_POLICY_BACKUP_REQUIRED';end if;":''}
 ${['202610090102','202610090103'].includes(after)?"if to_regclass('arena_private.phase3_final_backup_20261009') is null then raise exception 'HOST_POLICY_BACKUP_REQUIRED';end if;":''}
end $$;\n`;
for(const c of checks){
 sql+=`do $$ begin if exists(select 1 from arena_private.staging_installation where version='${c.file.split('_')[0]}') then raise exception 'MIGRATION_ALREADY_INSTALLED';end if;end $$;\n`;
 const content=fs.readFileSync('supabase/migrations/'+c.file,'utf8').replace(/^begin;\s*$/gm,'').replace(/^commit;\s*$/gm,'');
 sql+=content+`\ninsert into arena_private.staging_installation(version,source_sha256) values('${c.file.split('_')[0]}','${c.sha256}');\n`;
}
sql+=`commit;\nselect version,source_sha256 from arena_private.staging_installation where version >= '${files[0].split('_')[0]}' order by version;\n`;
fs.writeFileSync('build/phase3-evidence/install'+(after?'-after-'+after:'')+'.sql',sql);
fs.writeFileSync('build/phase3-evidence/migration-hashes'+(after?'-after-'+after:'')+'.json',JSON.stringify(checks,null,2));
console.log('Built '+checks.length+' new Phase 3 migrations; no secrets included.');
