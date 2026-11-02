// Builds a reviewable installer for the EMPTY arena-staging project only.
// Does not connect to or change any database.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=path.resolve(__dirname,'../..');
const read=p=>fs.readFileSync(path.resolve(root,p),'utf8').replace(/^\uFEFF/,'').replaceAll('\r\n','\n');
const baseline=['supabase/production_schema.sql','supabase/setup_messaging.sql','supabase/setup_profiles.sql','supabase/public_games_chat_images_and_arena_classification.sql','supabase/booking_conflicts_and_match_options.sql','supabase/fix_reservation_creation_and_maps.sql','../arena_owner/supabase/owner_operations.sql','../playon_admin/supabase/staff_username_auth.sql','../playon_admin/supabase/admin_dashboard.sql','supabase/arena_v2_booking_system.sql'];
const migrations=['202609290001_phase1_security_profile.sql','202609290002_phase1_inventory.sql','202609290003_phase1_rpc_boundaries.sql'];
const base=read(baseline[0]);const a=base.indexOf('create table if not exists public.profiles'),b=base.indexOf('\n);',a)+3;
if(a<0||b<3)throw Error('Baseline profile definition missing');
let out=`-- REVIEW BEFORE EXECUTION. Target: arena-staging / gtcrijikfaglqcwqozel ONLY.
-- Do not run against Production mbgqnlbuslrgamkzdqpd.
-- Baseline plus existing Phase 1 migrations in order, one atomic transaction.
-- No mock auth/storage schemas, no users, no copied Production data.
begin;
set local statement_timeout='120s';
do $$ begin
 if exists(select 1 from information_schema.tables where table_schema='public' and table_type='BASE TABLE')
    or exists(select 1 from auth.users) then
   raise exception 'STAGING_INSTALL_REQUIRES_EMPTY_PROJECT';
 end if;
end $$;
create extension if not exists pgcrypto with schema extensions;
`;
out+=base.slice(a,b)+"\nalter table profiles add column role text not null default 'player';\n";
for(const p of baseline)out+='\n-- BASELINE SOURCE: '+p+'\n'+read(p)+'\n';
for(const p of migrations){let s=read('supabase/migrations/'+p);const begin=s.indexOf('\nbegin;');if(begin<0||!s.trimEnd().endsWith('commit;'))throw Error('Unexpected migration transaction envelope: '+p);s=s.slice(0,begin)+s.slice(begin+7);s=s.trimEnd().slice(0,-7);out+='\n-- EXISTING MIGRATION: '+p+'\n'+s+'\n';}
out+=`\ncreate table arena_private.staging_installation(version text primary key, source_sha256 text not null, applied_at timestamptz not null default now());
revoke all on arena_private.staging_installation from public,anon,authenticated;
`;
for(const p of migrations){const hash=crypto.createHash('sha256').update(read('supabase/migrations/'+p)).digest('hex');out+=`insert into arena_private.staging_installation(version,source_sha256) values('${p.split('_')[0]}','${hash}');\n`;}
out+='commit;\nselect version,source_sha256 from arena_private.staging_installation order by version;\n';
fs.writeFileSync(path.join(__dirname,'arena_staging_install.sql'),out);
console.log('Prepared staging-only installer: '+out.length+' characters. No SQL executed.');
