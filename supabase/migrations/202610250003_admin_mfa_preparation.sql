-- PREPARATION ONLY: no account is enrolled and enforcement defaults to off.
begin;
create table arena_private.admin_mfa_policy (
 singleton boolean primary key default true check(singleton),
 enforced boolean not null default false
);
insert into arena_private.admin_mfa_policy(singleton,enforced) values(true,false);
create table arena_private.admin_mfa_state (
 user_id uuid primary key references auth.users(id),
 enforced boolean not null default false,
 recovery_pending boolean not null default false,
 min_iat bigint not null default 0,
 setup_confirmed_at timestamptz,
 failed_attempts integer not null default 0,
 blocked_until timestamptz
);
create table arena_private.admin_mfa_recovery_codes (
 user_id uuid not null references auth.users(id),code_hash bytea not null,
 created_at timestamptz not null default now(),used_at timestamptz,
 primary key(user_id,code_hash)
);
create table arena_private.admin_mfa_recovery_tickets (
 user_id uuid not null references auth.users(id),ticket_hash bytea primary key,
 factor_ids uuid[] not null,expires_at timestamptz not null,completed_at timestamptz
);
create table arena_private.admin_mfa_audit (
 id bigint generated always as identity primary key,user_id uuid not null,
 event text not null,created_at timestamptz not null default clock_timestamp()
);
revoke all on arena_private.admin_mfa_policy,arena_private.admin_mfa_state,arena_private.admin_mfa_recovery_codes,
 arena_private.admin_mfa_recovery_tickets,arena_private.admin_mfa_audit from public,anon,authenticated;

create function arena_private.raw_admin(p_user uuid) returns boolean
language sql stable security definer set search_path=pg_catalog,public as $$
 select exists(select 1 from public.admin_users where user_id=p_user and active)
 and not exists(select 1 from public.staff_login_accounts where user_id=p_user and not active);
$$;
create function arena_private.admin_totp_verified(p_user uuid) returns boolean
language sql stable security definer set search_path=pg_catalog,auth as $$
 select exists(select 1 from auth.mfa_factors where user_id=p_user and factor_type='totp' and status='verified');
$$;
create function arena_private.admin_aal2(p_user uuid) returns boolean
language sql stable security definer set search_path=pg_catalog,arena_private as $$
 select auth.uid()=p_user
 and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'aal','aal1')='aal2'
 and coalesce((nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'iat')::bigint,0)
     >=coalesce((select min_iat from arena_private.admin_mfa_state where user_id=p_user),0)
 and arena_private.admin_totp_verified(p_user);
$$;
create or replace function public.is_platform_admin_user(p_user_id uuid) returns boolean
language sql stable security definer set search_path=pg_catalog,public,arena_private as $$
 select arena_private.raw_admin(p_user_id)
 and not coalesce((select recovery_pending from arena_private.admin_mfa_state where user_id=p_user_id),false)
 and (not ((select enforced from arena_private.admin_mfa_policy where singleton)
           or coalesce((select enforced from arena_private.admin_mfa_state where user_id=p_user_id),false))
      or arena_private.admin_aal2(p_user_id));
$$;

create function public.admin_mfa_setup_state() returns jsonb
language sql stable security definer set search_path=pg_catalog,arena_private as $$
 select jsonb_build_object('eligible',arena_private.raw_admin(auth.uid()),
 'required',(select enforced from admin_mfa_policy where singleton) or coalesce((select enforced from admin_mfa_state where user_id=auth.uid()),false),
 'recovery_pending',coalesce((select recovery_pending from admin_mfa_state where user_id=auth.uid()),false),
 'confirmed',exists(select 1 from admin_mfa_state where user_id=auth.uid() and setup_confirmed_at is not null));
$$;
create function public.generate_admin_recovery_codes() returns jsonb
language plpgsql security definer set search_path=pg_catalog,arena_private,extensions as $$
declare result jsonb:='[]'; code text;
begin
 if not arena_private.raw_admin(auth.uid()) or not arena_private.admin_aal2(auth.uid()) then
   raise exception 'ADMIN_AAL2_REQUIRED' using errcode='42501';
 end if;
 insert into admin_mfa_state(user_id) values(auth.uid()) on conflict do nothing;
 perform 1 from admin_mfa_state where user_id=auth.uid() for update;
 delete from admin_mfa_recovery_codes where user_id=auth.uid();
 update admin_mfa_recovery_tickets set completed_at=clock_timestamp()
 where user_id=auth.uid() and completed_at is null;
 for i in 1..10 loop
   code:=encode(extensions.gen_random_bytes(16),'hex');
   insert into admin_mfa_recovery_codes(user_id,code_hash) values(auth.uid(),extensions.digest(auth.uid()::text||':'||code,'sha256'));
   result:=result||jsonb_build_array(code);
 end loop;
 update admin_mfa_state set setup_confirmed_at=null where user_id=auth.uid();
 insert into admin_mfa_audit(user_id,event) values(auth.uid(),'recovery_codes_generated');
 return result;
end $$;
create function public.confirm_admin_mfa_setup(p_codes_saved boolean) returns void
language plpgsql security definer set search_path=pg_catalog,arena_private as $$
begin
 if p_codes_saved is distinct from true or not arena_private.raw_admin(auth.uid())
    or not arena_private.admin_aal2(auth.uid()) then raise exception 'ADMIN_AAL2_REQUIRED' using errcode='42501';end if;
 perform 1 from admin_mfa_state where user_id=auth.uid() for update;
 if (select count(*) from admin_mfa_recovery_codes where user_id=auth.uid() and used_at is null)<>10 then
   raise exception 'BACKUP_CODES_REQUIRED';end if;
 update admin_mfa_state set setup_confirmed_at=clock_timestamp(),recovery_pending=false,failed_attempts=0,blocked_until=null where user_id=auth.uid();
 insert into admin_mfa_audit(user_id,event) values(auth.uid(),'setup_confirmed_without_activation');
end $$;
-- Deliberately service-only. Run only after explicit human confirmation.
create function public.activate_admin_mfa(p_user uuid) returns void
language plpgsql security definer set search_path=pg_catalog,arena_private as $$
begin
 perform 1 from admin_mfa_state where user_id=p_user for update;
 if not arena_private.raw_admin(p_user) or not arena_private.admin_totp_verified(p_user)
 or not exists(select 1 from admin_mfa_state where user_id=p_user and setup_confirmed_at is not null and not recovery_pending)
 or (select count(*) from admin_mfa_recovery_codes where user_id=p_user and used_at is null)<>10 then
   raise exception 'MFA_ACTIVATION_NOT_READY';end if;
 update admin_mfa_state set enforced=true where user_id=p_user;
 -- Once explicitly activated, future admin accounts cannot bypass MFA merely
 -- because they have not enrolled yet. Preparation remains off until then.
 update admin_mfa_policy set enforced=true where singleton;
 insert into admin_mfa_audit(user_id,event) values(p_user,'enforcement_activated');
end $$;

-- A recovery code never creates AAL2 or grants admin access. It authorizes
-- only removal of the snapshotted old factors by the trusted recovery worker.
create function public.begin_admin_mfa_recovery(p_code text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,arena_private,extensions as $$
declare state admin_mfa_state; hashed bytea; ticket text; factors uuid[];
begin
 if not arena_private.raw_admin(auth.uid()) then return jsonb_build_object('ok',false);end if;
 select * into state from admin_mfa_state where user_id=auth.uid() for update;
 if not found or coalesce(state.blocked_until>clock_timestamp(),false) then return jsonb_build_object('ok',false);end if;
 hashed:=extensions.digest(auth.uid()::text||':'||coalesce(p_code,''),'sha256');
 update admin_mfa_recovery_codes set used_at=clock_timestamp()
 where user_id=auth.uid() and code_hash=hashed and used_at is null;
 if not found then
   update admin_mfa_state set failed_attempts=case when failed_attempts>=4 then 0 else failed_attempts+1 end,
   blocked_until=case when failed_attempts>=4 then clock_timestamp()+interval '15 minutes' else null end where user_id=auth.uid();
   insert into admin_mfa_audit(user_id,event) values(auth.uid(),'recovery_rejected');
   return jsonb_build_object('ok',false);
 end if;
 select coalesce(array_agg(id),'{}'::uuid[]) into factors from auth.mfa_factors where user_id=auth.uid() and factor_type='totp';
 ticket:=encode(extensions.gen_random_bytes(32),'hex');
 insert into admin_mfa_recovery_tickets(user_id,ticket_hash,factor_ids,expires_at)
 values(auth.uid(),extensions.digest(ticket,'sha256'),factors,clock_timestamp()+interval '5 minutes');
 update admin_mfa_state set recovery_pending=true,setup_confirmed_at=null,
 min_iat=floor(extract(epoch from clock_timestamp()))::bigint+1 where user_id=auth.uid();
 insert into admin_mfa_audit(user_id,event) values(auth.uid(),'recovery_started');
 return jsonb_build_object('ok',true,'ticket',ticket);
end $$;
create function public.admin_mfa_recovery_factors(p_user uuid,p_ticket text) returns uuid[]
language sql stable security definer set search_path=pg_catalog,arena_private,extensions as $$
 select factor_ids from admin_mfa_recovery_tickets where user_id=p_user
 and ticket_hash=extensions.digest(p_ticket,'sha256') and expires_at>clock_timestamp() and completed_at is null;
$$;
create function public.finish_admin_mfa_recovery(p_user uuid,p_ticket text) returns void
language plpgsql security definer set search_path=pg_catalog,arena_private,extensions as $$
begin
 update admin_mfa_recovery_tickets set completed_at=clock_timestamp() where user_id=p_user
 and ticket_hash=extensions.digest(p_ticket,'sha256') and expires_at>clock_timestamp() and completed_at is null;
 if not found then raise exception 'INVALID_RECOVERY_TICKET' using errcode='42501';end if;
 insert into admin_mfa_audit(user_id,event) values(p_user,'old_factors_removed_reenrollment_required');
end $$;

revoke all on function arena_private.raw_admin(uuid),arena_private.admin_totp_verified(uuid),arena_private.admin_aal2(uuid) from public,anon,authenticated;
revoke all on function public.admin_mfa_setup_state(),public.generate_admin_recovery_codes(),public.confirm_admin_mfa_setup(boolean),public.begin_admin_mfa_recovery(text) from public,anon;
grant execute on function public.admin_mfa_setup_state(),public.generate_admin_recovery_codes(),public.confirm_admin_mfa_setup(boolean),public.begin_admin_mfa_recovery(text) to authenticated;
revoke all on function public.activate_admin_mfa(uuid),public.admin_mfa_recovery_factors(uuid,text),public.finish_admin_mfa_recovery(uuid,text) from public,anon,authenticated;
grant execute on function public.activate_admin_mfa(uuid),public.admin_mfa_recovery_factors(uuid,text),public.finish_admin_mfa_recovery(uuid,text) to service_role;
commit;
