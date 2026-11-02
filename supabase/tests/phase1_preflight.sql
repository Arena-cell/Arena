-- READ ONLY. Run on an isolated staging clone before applying Phase 1.
-- Keep outputs private: they include account IDs and operational data.
begin read only;
select version();
select extname,extnamespace::regnamespace from pg_extension where extname in ('pgcrypto','btree_gist');
-- pgcrypto must be in extensions for the reviewed credential functions.
select lower(trim(username)) normalized_username,array_agg(id) account_ids
from profiles where username is not null group by lower(trim(username)) having count(*)>1;
select id,username from profiles where username is not null and username !~ '^[a-z][a-z0-9_]{3,31}$';
-- Do NOT automatically promote legacy profiles.role: it was writable.
select p.id,p.role,a.active confirmed_admin
from profiles p left join admin_users a on a.user_id=p.id where p.role<>'player';
select user_id,active from admin_users;
select user_id,stadium_id,role from owner_stadium_assignments;
select id,owner_id,name,court_count,opening_time,closing_time,is_active from arenas;
select arena_id,count(*) filter(where court_id is null) missing_court,count(*) active_bookings
from bookings where status<>'cancelled' group by arena_id;
select arena_id,count(*) filter(where court_id is null) missing_court,count(*) active_matches
from matches where status<>'cancelled' group by arena_id;
-- Potential conflicts (including null court); final allocation is migration 0002.
with events as (
 select 'booking' kind,id,arena_id,court_id,starts_at,ends_at from bookings where status<>'cancelled'
 union all select 'match',id,arena_id,court_id,starts_at,ends_at from matches where status<>'cancelled'
 union all select 'block',id,arena_id,null::uuid,starts_at,ends_at from blocked_slots
)
select a.kind,a.id,b.kind conflicting_kind,b.id conflicting_id,a.arena_id
from events a join events b on a.arena_id=b.arena_id and (a.kind,a.id)<(b.kind,b.id)
 and a.starts_at<b.ends_at and a.ends_at>b.starts_at
 and (a.court_id is null or b.court_id is null or a.court_id=b.court_id);
select schemaname,tablename,policyname,roles,cmd,qual,with_check from pg_policies
where schemaname in ('public','storage') order by schemaname,tablename,policyname;
select table_name,column_name,grantee,privilege_type from information_schema.column_privileges
where table_schema='public' and table_name in ('profiles','admin_users','staff_login_accounts');
-- Compare every deployed RPC to migration 0003 allowlist before staging rollout.
select p.oid::regprocedure function,p.prosecdef,p.proconfig,p.proacl
from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
and not exists(select 1 from pg_depend d where d.objid=p.oid and d.deptype='e');
rollback;
