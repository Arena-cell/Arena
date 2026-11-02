// Local-only PostgreSQL integration harness. Never connects to hosted Supabase.
const fs=require('fs'),path=require('path'),cp=require('child_process');
const root=path.resolve(__dirname,'../..');process.chdir(root);
const psql='C:/Program Files/PostgreSQL/18/bin/psql.exe';
const db='arena_phase1_test_'+Date.now();
const args=['-X','-h','127.0.0.1','-p','55439','-U','postgres','-v','ON_ERROR_STOP=1'];
function sql(text,database=db){try{return cp.execFileSync(psql,[...args,'-d',database,'-qAt'],{input:text,encoding:'utf8',stdio:['pipe','pipe','pipe']});}catch(e){throw Error(e.stderr?.toString()||e.message);}}
function file(p){return fs.readFileSync(p,'utf8').replace(/^\uFEFF/,'');}
const setup=`
do $$ begin
  if not exists(select 1 from pg_roles where rolname='anon') then create role anon;end if;
  if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated;end if;
  if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role bypassrls;end if;
  if not exists(select 1 from pg_roles where rolname='supabase_auth_admin') then create role supabase_auth_admin;end if;
end $$;
create schema auth;create schema storage;create schema extensions;
create extension pgcrypto with schema extensions;
grant usage on schema auth,public to anon,authenticated,service_role;
alter default privileges in schema public grant all on tables to anon,authenticated,service_role;
create table auth.users(id uuid primary key,phone text unique,phone_confirmed_at timestamptz,email text,raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function auth.role() returns text language sql stable as $$ select current_user::text $$;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);
alter table storage.objects enable row level security;
create function storage.foldername(text) returns text[] language sql as $$ select string_to_array($1,'/') $$;
create publication supabase_realtime;
`;
(async()=>{try{
 const expected=path.resolve(root,'build/phase1-pgdata').replaceAll('\\','/').toLowerCase();
 const actual=sql('show data_directory','postgres').trim().replaceAll('\\','/').toLowerCase();
 if(actual!==expected)throw Error('Refusing database outside this workspace local test cluster');
 sql('create database '+db,'postgres');sql(setup);
 const base=file('supabase/production_schema.sql');
 const a=base.indexOf('create table if not exists public.profiles'),b=base.indexOf('\n);',a)+3;
 sql(base.slice(a,b)+"\nalter table profiles add column role text not null default 'player';");
 for(const p of ['supabase/production_schema.sql','supabase/setup_messaging.sql','supabase/setup_profiles.sql','supabase/public_games_chat_images_and_arena_classification.sql','supabase/booking_conflicts_and_match_options.sql','supabase/fix_reservation_creation_and_maps.sql','../arena_owner/supabase/owner_operations.sql','../playon_admin/supabase/staff_username_auth.sql','../playon_admin/supabase/admin_dashboard.sql','supabase/arena_v2_booking_system.sql']) sql(file(p));
 sql(`insert into auth.users(id,phone,phone_confirmed_at,raw_user_meta_data) values('90000000-0000-4000-8000-000000000001','96899999999',now(),'{"username":"legacy_player","gender":"men"}');
 insert into arenas(id,name,location,price_per_hour,opening_time,closing_time,court_count,audience_gender) values('90000000-0000-4000-8000-000000000002','Legacy','Muscat',10,'08:00','23:00',2,'men');
 insert into bookings(user_id,arena_id,starts_at,ends_at,total_price,status) select '90000000-0000-4000-8000-000000000001','90000000-0000-4000-8000-000000000002','2035-02-01 10:00+04','2035-02-01 11:00+04',10,'upcoming' from generate_series(1,3);`);
 const migrations=fs.readdirSync('supabase/migrations').filter(x=>/^2026.*\.sql$/.test(x)).sort();
 if(new Set(migrations.map(x=>x.split('_')[0])).size!==migrations.length)throw Error('Duplicate migration version');
 for(const p of migrations.filter(p=>p.includes('_phase1_'))) {sql(file('supabase/migrations/'+p));console.log('Applied '+p);}
 if(fs.existsSync('supabase/tests/phase1_assertions.sql')) {console.log(sql(file('supabase/tests/phase1_assertions.sql')));}
 await require('./phase1_cases.cjs')(sql, statements => Promise.all(statements.map(statement => new Promise(resolve => {
   const child=cp.spawn(psql,[...args,'-d',db,'-qAt']);let error='';child.stderr.on('data',d=>error+=d);child.stdout.resume();child.on('error',e=>resolve({ok:false,error:e.message}));child.on('close',code=>resolve({ok:code===0,error}));child.stdin.end(statement);
 }))));
 for(const p of migrations.filter(p=>p.includes('_phase2_'))) {sql(file('supabase/migrations/'+p));console.log('Applied '+p);}
 if(process.env.ARENA_TEST_REFUND_POLICY==='1') for(const p of migrations.filter(p=>p.includes('_phase3_'))) {sql(file('supabase/migrations/'+p));console.log('Applied '+p);}
 console.log('LOCAL DATABASE: '+db);
 fs.writeFileSync('build/phase1-test-db.txt',db);
 }catch(e){console.error(e.message);console.error('Local test database retained: '+db);process.exitCode=1;}})();
