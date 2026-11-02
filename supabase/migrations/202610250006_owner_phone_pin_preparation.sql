-- LOCAL PREPARATION ONLY. No Auth account is created/modified here.
-- Enable only after reviewed identity migration, real SMS and client acceptance.
begin;
create table arena_private.owner_phone_policy(singleton boolean primary key default true check(singleton),enabled boolean not null default false);
insert into arena_private.owner_phone_policy values(true,false);
create table arena_private.owner_accounts(
 user_id uuid primary key references auth.users(id),display_name text not null check(length(trim(display_name)) between 2 and 150),
 phone text not null unique check(phone~'^\+968[79][0-9]{7}$'),approved boolean not null default true,
 credential_version integer not null default 1,verified_after timestamptz not null default clock_timestamp(),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp());
create table arena_private.owner_pin_credentials(user_id uuid primary key references arena_private.owner_accounts(user_id),pin_hash text not null,device_hash bytea not null,failed_attempts integer not null default 0,blocked_until timestamptz,updated_at timestamptz not null default clock_timestamp());
create table arena_private.owner_pin_grants(id uuid primary key default gen_random_uuid(),user_id uuid not null references arena_private.owner_accounts(user_id),session_id uuid not null,token_hash bytea not null unique,credential_version integer not null,expires_at timestamptz not null,revoked_at timestamptz);
create table arena_private.owner_used_otp(user_id uuid not null,session_id uuid not null,otp_time bigint not null,primary key(user_id,session_id,otp_time));
create table arena_private.owner_admin_audit(id bigint generated always as identity primary key,actor uuid not null,owner_id uuid,event text not null,proof text,created_at timestamptz not null default clock_timestamp());
create table arena_private.owner_sms_limits(key_hash bytea primary key,window_start timestamptz not null,attempts integer not null,last_attempt timestamptz not null);
create table arena_private.owner_provision_requests(id uuid primary key,actor uuid not null,owner_id uuid,display_name text not null,phone text not null,arena_ids uuid[] not null,proof text not null,operation text not null check(operation in('create','phone_change','enroll','update')),status text not null default 'prepared',created_at timestamptz not null default clock_timestamp());
revoke all on arena_private.owner_phone_policy,arena_private.owner_accounts,arena_private.owner_pin_credentials,arena_private.owner_pin_grants,arena_private.owner_used_otp,arena_private.owner_admin_audit,arena_private.owner_sms_limits,arena_private.owner_provision_requests from public,anon,authenticated;

create function arena_private.owner_auth_session() returns uuid language plpgsql stable security definer set search_path=pg_catalog,auth as $$
declare sid uuid;begin
 begin sid:=(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'session_id')::uuid;exception when others then return null;end;
 if exists(select 1 from auth.sessions where id=sid and user_id=auth.uid()) then return sid;end if;return null;
end$$;
create function arena_private.owner_identity_ready() returns boolean language sql stable security definer set search_path=pg_catalog,public,arena_private,auth as $$
 select (select enabled from arena_private.owner_phone_policy where singleton)
 and exists(select 1 from arena_private.owner_accounts a join auth.users u on u.id=a.user_id where a.user_id=auth.uid() and a.approved and '+'||ltrim(u.phone,'+')=a.phone and u.phone_confirmed_at is not null and exists(select 1 from auth.sessions z where z.id=arena_private.owner_auth_session() and z.created_at>=a.verified_after))
 and not exists(select 1 from public.staff_login_accounts where user_id=auth.uid() and not active)
 and arena_private.owner_auth_session() is not null;
$$;
create function arena_private.owner_recent_sms() returns bigint language plpgsql stable security definer set search_path=pg_catalog,arena_private as $$
declare stamp bigint;verified timestamptz;begin
 if not arena_private.owner_identity_ready() then return null;end if;
 select max((x->>'timestamp')::bigint) into stamp from jsonb_array_elements(coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->'amr','[]')) x where x->>'method'='otp';
 select verified_after into verified from arena_private.owner_accounts where user_id=auth.uid();
 if stamp is null or stamp<floor(extract(epoch from verified)) or to_timestamp(stamp)<clock_timestamp()-interval '5 minutes' then return null;end if;
 return stamp;
end$$;
create function arena_private.owner_pin_access(p_user uuid) returns boolean language plpgsql stable security definer set search_path=pg_catalog,arena_private as $$
declare token text;begin
 if not (select enabled from arena_private.owner_phone_policy where singleton) then return true;end if;
 -- Server workers remain authorized by their existing roles, never client headers.
 if current_setting('role',true) in('service_role','postgres','none') then return true;end if;
 if p_user is distinct from auth.uid() or not arena_private.owner_identity_ready() then return false;end if;
 token:=nullif(current_setting('request.headers',true),'')::jsonb->>'x-arena-owner-unlock';
 if token is null or length(token)<>64 then return false;end if;
 return exists(select 1 from arena_private.owner_pin_grants g join arena_private.owner_accounts a using(user_id)
 where g.user_id=p_user and g.session_id=arena_private.owner_auth_session() and g.token_hash=extensions.digest(token,'sha256') and g.credential_version=a.credential_version and g.revoked_at is null and g.expires_at>clock_timestamp());
end$$;
create or replace function public.is_stadium_owner_of(p_arena_id uuid,p_user_id uuid default auth.uid()) returns boolean language sql stable security definer set search_path=pg_catalog,public,arena_private as $$
 select (exists(select 1 from public.arenas where id=p_arena_id and owner_id=p_user_id) or exists(select 1 from public.owner_stadium_assignments where stadium_id=p_arena_id and user_id=p_user_id))
 and not exists(select 1 from public.staff_login_accounts where user_id=p_user_id and not active)
 and arena_private.owner_pin_access(p_user_id);
$$;
create function public.owner_phone_state(p_device text) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,arena_private as $$
declare c arena_private.owner_pin_credentials%rowtype;begin
 if not (select enabled from arena_private.owner_phone_policy where singleton) then return jsonb_build_object('approved',false,'error','OWNER_PHONE_NOT_ENABLED');end if;
 if not arena_private.owner_identity_ready() then return jsonb_build_object('approved',false,'error','OWNER_NOT_AUTHORIZED');end if;
 select * into c from arena_private.owner_pin_credentials where user_id=auth.uid();
 return jsonb_build_object('approved',true,'name',(select display_name from arena_private.owner_accounts where user_id=auth.uid()),'needs_setup',c.user_id is null or c.device_hash is distinct from extensions.digest(coalesce(p_device,''),'sha256'),'recent_sms',arena_private.owner_recent_sms() is not null,'unlocked',arena_private.owner_pin_access(auth.uid()));
end$$;
create function arena_private.owner_issue_pin_grant(p_user uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,arena_private as $$
declare token text;until_at timestamptz:=clock_timestamp()+interval '30 minutes';begin
 token:=encode(extensions.gen_random_bytes(32),'hex');
 update arena_private.owner_pin_grants set revoked_at=clock_timestamp() where user_id=p_user and session_id=arena_private.owner_auth_session() and revoked_at is null;
 insert into arena_private.owner_pin_grants(user_id,session_id,token_hash,credential_version,expires_at) select p_user,arena_private.owner_auth_session(),extensions.digest(token,'sha256'),credential_version,until_at from arena_private.owner_accounts where user_id=p_user;
 return jsonb_build_object('ok',true,'unlock_token',token,'expires_at',until_at);
end$$;
create function public.owner_set_pin(p_pin text,p_device text) returns jsonb language plpgsql security definer set search_path=pg_catalog,arena_private as $$
declare stamp bigint;u uuid:=auth.uid();begin
 if not arena_private.owner_identity_ready() then raise exception 'OWNER_NOT_AUTHORIZED' using errcode='42501';end if;
 if coalesce(p_pin,'')!~'^[0-9]{6}$' or coalesce(p_device,'')!~'^[a-f0-9]{64}$' then return jsonb_build_object('ok',false,'error','INVALID_PIN_FORMAT');end if;
 perform 1 from arena_private.owner_accounts where user_id=u for update;
 stamp:=arena_private.owner_recent_sms();
 if stamp is null or exists(select 1 from arena_private.owner_used_otp where user_id=u and session_id=arena_private.owner_auth_session() and otp_time=stamp) then return jsonb_build_object('ok',false,'error','SMS_REVERIFY_REQUIRED');end if;
 insert into arena_private.owner_used_otp values(u,arena_private.owner_auth_session(),stamp);
 insert into arena_private.owner_pin_credentials(user_id,pin_hash,device_hash) values(u,extensions.crypt(p_pin,extensions.gen_salt('bf',12)),extensions.digest(p_device,'sha256'))
 on conflict(user_id) do update set pin_hash=excluded.pin_hash,device_hash=excluded.device_hash,failed_attempts=0,blocked_until=null,updated_at=clock_timestamp();
 update arena_private.owner_accounts set credential_version=credential_version+1 where user_id=u;
 return arena_private.owner_issue_pin_grant(u);
end$$;
create function public.owner_unlock_pin(p_pin text,p_device text) returns jsonb language plpgsql security definer set search_path=pg_catalog,arena_private as $$
declare c arena_private.owner_pin_credentials%rowtype;u uuid:=auth.uid();begin
 if not arena_private.owner_identity_ready() then raise exception 'OWNER_NOT_AUTHORIZED' using errcode='42501';end if;
 if coalesce(p_pin,'')!~'^[0-9]{6}$' or coalesce(p_device,'')!~'^[a-f0-9]{64}$' then return jsonb_build_object('ok',false,'error','INVALID_PIN_FORMAT');end if;
 select * into c from arena_private.owner_pin_credentials where user_id=u for update;
 if not found or c.device_hash is distinct from extensions.digest(p_device,'sha256') then return jsonb_build_object('ok',false,'error','SMS_REVERIFY_REQUIRED');end if;
 if c.blocked_until>clock_timestamp() then return jsonb_build_object('ok',false,'error','PIN_RATE_LIMITED','retry_after',ceil(extract(epoch from c.blocked_until-clock_timestamp())));end if;
 if c.blocked_until is not null then update arena_private.owner_pin_credentials set failed_attempts=0,blocked_until=null where user_id=u;c.failed_attempts:=0;end if;
 if extensions.crypt(p_pin,c.pin_hash)<>c.pin_hash then
  update arena_private.owner_pin_credentials set failed_attempts=failed_attempts+1,blocked_until=case when failed_attempts+1>=5 then clock_timestamp()+interval '15 minutes' else null end where user_id=u;
  return jsonb_build_object('ok',false,'error',case when c.failed_attempts+1>=5 then 'PIN_RATE_LIMITED' else 'INVALID_PIN' end);
 end if;
 update arena_private.owner_pin_credentials set failed_attempts=0,blocked_until=null where user_id=u;
 return arena_private.owner_issue_pin_grant(u);
end$$;
create function public.owner_lock_session() returns void language sql security definer set search_path=pg_catalog,arena_private as $$
 update arena_private.owner_pin_grants set revoked_at=clock_timestamp() where user_id=auth.uid() and session_id=arena_private.owner_auth_session() and revoked_at is null;
$$;

create function public.admin_owner_directory() returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,arena_private as $$
begin if not public.is_platform_admin() then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',s.user_id,'name',coalesce(a.display_name,p.display_name,s.username),'phone',a.phone,'active',s.active,'phone_ready',a.user_id is not null,'arena_ids',(select coalesce(jsonb_agg(id),'[]') from public.arenas where owner_id=s.user_id or exists(select 1 from public.owner_stadium_assignments x where x.stadium_id=arenas.id and x.user_id=s.user_id)))),'[]') from public.staff_login_accounts s left join arena_private.owner_accounts a on a.user_id=s.user_id left join public.profiles p on p.id=s.user_id where s.account_type='owner');
end$$;
create function public.admin_prepare_owner(p_request uuid,p_owner uuid,p_name text,p_phone text,p_arenas uuid[],p_proof text,p_verified boolean) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,arena_private as $$
declare r arena_private.owner_provision_requests%rowtype;n text;begin
 if not public.is_platform_admin() then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 n:=arena_private.normalize_oman_contact(p_phone);
 if p_request is null or n!~'^\+968[79][0-9]{7}$' or n is null or length(trim(coalesce(p_name,''))) not between 2 and 150 or p_verified is distinct from true or length(trim(coalesce(p_proof,'')))<12 then raise exception 'VERIFIED_OWNER_DETAILS_REQUIRED';end if;
 -- Serialize administrative sagas before changing Supabase Auth outside this transaction.
 perform pg_advisory_xact_lock(hashtextextended('owner-phone:'||n,0));
 if p_owner is not null then perform pg_advisory_xact_lock(hashtextextended('owner-id:'||p_owner::text,0));end if;
 if exists(select 1 from arena_private.owner_provision_requests where id<>p_request and status<>'completed' and (phone=n or (p_owner is not null and owner_id=p_owner))) then raise exception 'OWNER_REQUEST_PENDING_REVIEW';end if;
 if p_owner is not null and (exists(select 1 from public.admin_users where user_id=p_owner) or not exists(select 1 from public.staff_login_accounts where user_id=p_owner and account_type='owner')) then raise exception 'OWNER_IDENTITY_MISMATCH' using errcode='42501';end if;
 if exists(select 1 from unnest(p_arenas) a where not exists(select 1 from public.arenas where id=a)) then raise exception 'ARENA_NOT_FOUND';end if;
 if exists(select 1 from arena_private.owner_accounts where phone=n and user_id is distinct from p_owner) and not exists(select 1 from arena_private.owner_provision_requests where id=p_request and actor=auth.uid() and status='completed' and operation='create' and phone=n) then raise exception 'OWNER_PHONE_ALREADY_REGISTERED';end if;
 insert into arena_private.owner_provision_requests(id,actor,owner_id,display_name,phone,arena_ids,proof,operation) values(p_request,auth.uid(),p_owner,trim(p_name),n,coalesce(p_arenas,'{}'),trim(p_proof),case when p_owner is null then 'create' when exists(select 1 from arena_private.owner_accounts where user_id=p_owner and phone<>n) then 'phone_change' when exists(select 1 from arena_private.owner_accounts where user_id=p_owner) then 'update' else 'enroll' end) on conflict(id) do nothing;
 select * into strict r from arena_private.owner_provision_requests where id=p_request;
 if r.actor<>auth.uid() or (r.owner_id is distinct from p_owner and not(p_owner is null and r.operation='create' and r.status='completed')) or (r.display_name,r.phone,r.arena_ids,r.proof) is distinct from (trim(p_name),n,coalesce(p_arenas,'{}'),trim(p_proof)) then raise exception 'REQUEST_ID_REUSED';end if;
 return jsonb_build_object('request_id',r.id,'status',r.status);
end$$;
create function public.owner_provision_context(p_request uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,arena_private,auth as $$
declare r arena_private.owner_provision_requests%rowtype;existing uuid;begin
 select * into strict r from arena_private.owner_provision_requests where id=p_request and actor=p_actor;
 if not arena_private.raw_admin(p_actor) then raise exception 'ADMIN_ONLY';end if;
 select id into existing from auth.users where '+'||ltrim(phone,'+')=r.phone;
 if existing is not null and r.owner_id is not null and existing<>r.owner_id then raise exception 'PHONE_BELONGS_TO_ANOTHER_ACCOUNT';end if;
 if exists(select 1 from public.admin_users where user_id=coalesce(r.owner_id,existing)) then raise exception 'ADMIN_IDENTITY_PROTECTED';end if;
 if exists(select 1 from public.arenas a where a.id=any(r.arena_ids)
 and a.owner_id is distinct from coalesce(r.owner_id,existing)
 and not exists(select 1 from public.owner_stadium_assignments x where x.stadium_id=a.id and x.user_id=coalesce(r.owner_id,existing))
 and (a.owner_id is not null or exists(select 1 from public.owner_stadium_assignments x where x.stadium_id=a.id and x.role='owner' and x.user_id is distinct from coalesce(r.owner_id,existing)))) then raise exception 'ARENA_OWNERSHIP_CONFLICT';end if;
 if r.operation='phone_change' and r.status<>'completed' then
  update arena_private.owner_accounts set approved=false,credential_version=credential_version+case when approved then 1 else 0 end where user_id=r.owner_id and phone<>r.phone;
  update arena_private.owner_provision_requests set status='auth_update_pending' where id=p_request;
 end if;
 return jsonb_build_object('name',r.display_name,'phone',r.phone,'owner_id',r.owner_id,'existing_auth_id',existing,'status',r.status);
end$$;
create function public.owner_finalize_provision(p_request uuid,p_actor uuid,p_auth_user uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,arena_private,auth as $$
declare r arena_private.owner_provision_requests%rowtype;prior arena_private.owner_accounts%rowtype;a uuid;begin
 select * into strict r from arena_private.owner_provision_requests where id=p_request and actor=p_actor for update;
 if not arena_private.raw_admin(p_actor) or exists(select 1 from public.admin_users where user_id=p_auth_user) then raise exception 'ADMIN_IDENTITY_PROTECTED';end if;
 if r.owner_id is not null and r.owner_id<>p_auth_user then raise exception 'OWNER_IDENTITY_MISMATCH';end if;
 if not exists(select 1 from auth.users where id=p_auth_user and '+'||ltrim(phone,'+')=r.phone) then raise exception 'AUTH_PHONE_MISMATCH';end if;
 if exists(select 1 from public.staff_login_accounts where user_id=p_auth_user and account_type<>'owner') then raise exception 'STAFF_IDENTITY_PROTECTED';end if;
 if r.status='completed' then return jsonb_build_object('owner_id',p_auth_user,'status','completed');end if;
 foreach a in array r.arena_ids loop
  perform 1 from public.arenas where id=a for update;
  -- Existing links and primary ownership survive authentication migration unchanged.
  if exists(select 1 from public.arenas where id=a and owner_id=p_auth_user) or exists(select 1 from public.owner_stadium_assignments where stadium_id=a and user_id=p_auth_user) then continue;end if;
  if exists(select 1 from public.arenas where id=a and owner_id is not null and owner_id<>p_auth_user) or exists(select 1 from public.owner_stadium_assignments where stadium_id=a and user_id<>p_auth_user and role='owner') then raise exception 'ARENA_OWNERSHIP_CONFLICT';end if;
 end loop;
 select * into prior from arena_private.owner_accounts where user_id=p_auth_user for update;
 insert into arena_private.owner_accounts(user_id,display_name,phone,created_by) values(p_auth_user,r.display_name,r.phone,p_actor)
 on conflict(user_id) do update set display_name=excluded.display_name,phone=excluded.phone,approved=true,credential_version=owner_accounts.credential_version+case when owner_accounts.phone<>excluded.phone then 1 else 0 end,verified_after=case when owner_accounts.phone<>excluded.phone then clock_timestamp() else owner_accounts.verified_after end,updated_at=clock_timestamp();
 if prior.user_id is not null and prior.phone<>r.phone then
  update arena_private.owner_pin_grants set revoked_at=clock_timestamp() where user_id=p_auth_user and revoked_at is null;
  delete from arena_private.owner_pin_credentials where user_id=p_auth_user;
 end if;
 insert into public.staff_login_accounts(user_id,username,account_type,active) values(p_auth_user,'owner_'||substr(replace(p_auth_user::text,'-',''),1,24),'owner',true) on conflict(user_id) do nothing;
 foreach a in array r.arena_ids loop
  if exists(select 1 from public.arenas where id=a and owner_id=p_auth_user) or exists(select 1 from public.owner_stadium_assignments where stadium_id=a and user_id=p_auth_user) then continue;end if;
  insert into public.owner_stadium_assignments(stadium_id,user_id,role) values(a,p_auth_user,'owner') on conflict do nothing;
 end loop;
 update arena_private.owner_provision_requests set owner_id=p_auth_user,status='completed' where id=p_request;
 insert into arena_private.owner_admin_audit(actor,owner_id,event,proof) values(p_actor,p_auth_user,r.operation,r.proof);
 return jsonb_build_object('owner_id',p_auth_user,'status','completed');
end$$;
create function public.guard_owner_assignment_identity() returns trigger language plpgsql security definer set search_path=pg_catalog,public,arena_private,auth as $$
begin
 if tg_op='UPDATE' and(new.stadium_id,new.user_id) is distinct from(old.stadium_id,old.user_id) then raise exception 'OWNER_ASSIGNMENT_IDENTITY_IMMUTABLE';end if;
 if exists(select 1 from public.admin_users where user_id=new.user_id) then raise exception 'ADMIN_IS_NOT_OWNER_IDENTITY';end if;
 if tg_op='INSERT' and exists(select 1 from public.owner_stadium_assignments where stadium_id=new.stadium_id and user_id=new.user_id) then return new;end if;
 perform 1 from public.arenas where id=new.stadium_id for update;
 if not exists(select 1 from auth.users where id=new.user_id) or not (exists(select 1 from public.staff_login_accounts where user_id=new.user_id and account_type='owner' and active) or exists(select 1 from public.arenas where owner_id=new.user_id)) then raise exception 'OWNER_IDENTITY_NOT_REGISTERED';end if;
 if (select enabled from arena_private.owner_phone_policy where singleton) and not exists(select 1 from arena_private.owner_accounts where user_id=new.user_id and approved) then raise exception 'OWNER_PHONE_NOT_APPROVED';end if;
 if exists(select 1 from public.arenas where id=new.stadium_id and owner_id is not null and owner_id<>new.user_id) or exists(select 1 from public.owner_stadium_assignments where stadium_id=new.stadium_id and user_id<>new.user_id and role='owner') then raise exception 'ARENA_OWNERSHIP_CONFLICT';end if;
 return new;
end$$;
revoke all on function public.guard_owner_assignment_identity() from public,anon,authenticated;
create trigger owner_assignment_identity before insert or update on public.owner_stadium_assignments for each row execute function public.guard_owner_assignment_identity();

create function public.owner_sms_authorize(p_phone text,p_ip_hash text) returns boolean language plpgsql security definer set search_path=pg_catalog,public,arena_private as $$
declare k bytea;r arena_private.owner_sms_limits%rowtype;begin
 if not (select enabled from arena_private.owner_phone_policy where singleton) then return false;end if;
 k:=extensions.digest('ip:'||coalesce(p_ip_hash,'unknown'),'sha256');
 insert into arena_private.owner_sms_limits values(k,clock_timestamp(),0,'epoch') on conflict do nothing;
 select * into r from arena_private.owner_sms_limits where key_hash=k for update;
 if r.window_start>clock_timestamp()-interval '1 hour' and r.attempts>=30 then return false;end if;
 update arena_private.owner_sms_limits set attempts=case when window_start<clock_timestamp()-interval '1 hour' then 1 else attempts+1 end,window_start=case when window_start<clock_timestamp()-interval '1 hour' then clock_timestamp() else window_start end,last_attempt=clock_timestamp() where key_hash=k;
 if not exists(select 1 from arena_private.owner_accounts a join public.staff_login_accounts s on s.user_id=a.user_id where a.phone=p_phone and a.approved and s.active and s.account_type='owner') then return false;end if;
 k:=extensions.digest('phone:'||p_phone,'sha256');
 insert into arena_private.owner_sms_limits values(k,clock_timestamp(),0,'epoch') on conflict do nothing;
 select * into r from arena_private.owner_sms_limits where key_hash=k for update;
 if r.last_attempt>clock_timestamp()-interval '60 seconds' or(r.window_start>clock_timestamp()-interval '1 hour' and r.attempts>=5) then return false;end if;
 update arena_private.owner_sms_limits set attempts=case when window_start<clock_timestamp()-interval '1 hour' then 1 else attempts+1 end,window_start=case when window_start<clock_timestamp()-interval '1 hour' then clock_timestamp() else window_start end,last_attempt=clock_timestamp() where key_hash=k;
 return exists(select 1 from arena_private.owner_accounts a join public.staff_login_accounts s on s.user_id=a.user_id where a.phone=p_phone and a.approved and s.active and s.account_type='owner');
end$$;

create function public.admin_unlink_owner_arena(p_owner uuid,p_arena uuid,p_proof text) returns void language plpgsql security definer set search_path=pg_catalog,public,arena_private as $$
begin
 if not public.is_platform_admin() then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 if length(trim(coalesce(p_proof,'')))<12 then raise exception 'VERIFIED_OWNER_DETAILS_REQUIRED';end if;
 perform 1 from public.arenas where id=p_arena for update;
 if exists(select 1 from public.arenas where id=p_arena and owner_id=p_owner) then raise exception 'PRIMARY_OWNER_REVIEW_REQUIRED';end if;
 if exists(select 1 from arena_private.owner_provision_requests where status<>'completed' and p_arena=any(arena_ids)) then raise exception 'OWNER_REQUEST_PENDING_REVIEW';end if;
 delete from public.owner_stadium_assignments where stadium_id=p_arena and user_id=p_owner;
 if found then insert into arena_private.owner_admin_audit(actor,owner_id,event,proof) values(auth.uid(),p_owner,'unlink_arena:'||p_arena::text,trim(p_proof));end if;
end$$;
revoke all on function public.admin_unlink_owner_arena(uuid,uuid,text) from public,anon;
grant execute on function public.admin_unlink_owner_arena(uuid,uuid,text) to authenticated;
revoke all on all functions in schema arena_private from public,anon,authenticated;
revoke all on function public.owner_phone_state(text),public.owner_set_pin(text,text),public.owner_unlock_pin(text,text),public.owner_lock_session(),public.admin_owner_directory(),public.admin_prepare_owner(uuid,uuid,text,text,uuid[],text,boolean) from public,anon;
grant execute on function public.owner_phone_state(text),public.owner_set_pin(text,text),public.owner_unlock_pin(text,text),public.owner_lock_session(),public.admin_owner_directory(),public.admin_prepare_owner(uuid,uuid,text,text,uuid[],text,boolean) to authenticated;
revoke all on function public.owner_provision_context(uuid,uuid),public.owner_finalize_provision(uuid,uuid,uuid),public.owner_sms_authorize(text,text) from public,anon,authenticated;
grant execute on function public.owner_provision_context(uuid,uuid),public.owner_finalize_provision(uuid,uuid,uuid),public.owner_sms_authorize(text,text) to service_role;
commit;
