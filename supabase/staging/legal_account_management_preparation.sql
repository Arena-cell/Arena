-- LOCAL PREPARATION ONLY. Not in migrations; do not apply to hosted environments.
begin;
create table arena_private.legal_versions (
 version text primary key check(length(version) between 1 and 80),
 body jsonb not null,
 state text not null default 'draft' check(state in ('draft','published')),
 effective_at timestamptz,
 created_by uuid not null,
 published_by uuid,
 created_at timestamptz not null default clock_timestamp(),
 check(state='draft' or (effective_at is not null and published_by is not null))
);
create table arena_private.legal_acceptances (
 user_id uuid not null,version text not null references arena_private.legal_versions(version),
 accepted_at timestamptz not null default clock_timestamp(),
 primary key(user_id,version)
);
create table arena_private.account_deletion_requests (
 id uuid primary key default gen_random_uuid(),user_id uuid not null,
 requested_at timestamptz not null default clock_timestamp(),
 state text not null default 'requested' check(state in ('requested','reviewing','blocked_obligations','verified','processing','completed','failed')),
 accepted_at timestamptz,completed_at timestamptz,
 check(state<>'completed' or completed_at is not null)
);
create unique index legal_one_pending_deletion on arena_private.account_deletion_requests(user_id) where state<>'completed';
create table arena_private.legal_audit (
 id bigint generated always as identity primary key,actor uuid,event text not null,
 reference text not null,created_at timestamptz not null default clock_timestamp()
);
create table arena_private.legal_controls (
 singleton boolean primary key default true check(singleton),
 requests_enabled boolean not null default false,
 execution_enabled boolean not null default false
);
insert into arena_private.legal_controls default values;
revoke all on arena_private.legal_versions,arena_private.legal_acceptances,arena_private.account_deletion_requests,arena_private.legal_audit,arena_private.legal_controls from public,anon,authenticated,service_role;
alter table arena_private.legal_versions enable row level security;
alter table arena_private.legal_acceptances enable row level security;
alter table arena_private.account_deletion_requests enable row level security;
alter table arena_private.legal_audit enable row level security;
alter table arena_private.legal_controls enable row level security;

create function arena_private.guard_legal_version() returns trigger language plpgsql set search_path=pg_catalog as $$
begin
 if old.state='published' then raise exception 'PUBLISHED_POLICY_IMMUTABLE' using errcode='42501';end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
create trigger legal_version_immutable before update or delete on arena_private.legal_versions for each row execute function arena_private.guard_legal_version();
create function public.current_legal_policy() returns jsonb language sql stable security definer set search_path=pg_catalog,arena_private as $$
 select jsonb_build_object('version',version,'body',body,'effective_at',effective_at) from arena_private.legal_versions where state='published' and effective_at<=clock_timestamp() order by effective_at desc,created_at desc limit 1;
$$;
create function public.admin_save_legal_draft(p_version text,p_body jsonb) returns void language plpgsql security definer set search_path=pg_catalog,arena_private,public as $$
begin
 if not public.is_platform_admin_user(auth.uid()) then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 if jsonb_typeof(p_body)<>'object' or jsonb_typeof(p_body->'policies')<>'array' or jsonb_array_length(p_body->'policies')<>8 then raise exception 'INVALID_POLICY_BUNDLE';end if;
 if exists(select 1 from jsonb_array_elements(p_body->'policies') p where coalesce(p->>'ar','')='' or coalesce(p->>'en','')='') then raise exception 'BILINGUAL_TEXT_REQUIRED';end if;
 insert into arena_private.legal_versions(version,body,created_by) values(p_version,p_body,auth.uid())
 on conflict(version) do update set body=excluded.body;
 insert into arena_private.legal_audit(actor,event,reference) values(auth.uid(),'draft_saved',p_version);
end $$;
-- No publication RPC until outstanding legal decisions and contact details are approved.
create function public.accept_legal_policy(p_version text) returns timestamptz language plpgsql security definer set search_path=pg_catalog,arena_private,public as $$
declare accepted timestamptz;current_version text;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='42501';end if;
 select version into current_version from arena_private.legal_versions where state='published' and effective_at<=clock_timestamp() order by effective_at desc,created_at desc limit 1 for share;
 if current_version is null or p_version is distinct from current_version then raise exception 'CURRENT_PUBLISHED_POLICY_REQUIRED';end if;
 insert into arena_private.legal_acceptances(user_id,version) values(auth.uid(),p_version) on conflict do nothing;
 select accepted_at into accepted from arena_private.legal_acceptances where user_id=auth.uid() and version=p_version;return accepted;
end $$;
create function public.my_deletion_requests() returns jsonb language sql stable security definer set search_path=pg_catalog,arena_private as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'state',state,'requested_at',requested_at,'accepted_at',accepted_at,'completed_at',completed_at) order by requested_at desc),'[]'::jsonb) from arena_private.account_deletion_requests where user_id=auth.uid();
$$;
create function public.request_account_deletion() returns uuid language plpgsql security definer set search_path=pg_catalog,arena_private,public as $$
declare claims jsonb;request_id uuid;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='42501';end if;
 if not (select requests_enabled from arena_private.legal_controls where singleton) then raise exception 'DELETION_POLICY_NOT_ENABLED';end if;
 claims:=coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb);
 if not exists(select 1 from jsonb_array_elements(coalesce(claims->'amr','[]'::jsonb)) a where a->>'method'='otp' and (a->>'timestamp')::numeric between extract(epoch from clock_timestamp())-300 and extract(epoch from clock_timestamp())+5) then raise exception 'RECENT_PHONE_VERIFICATION_REQUIRED' using errcode='42501';end if;
 -- Signed JWT identifies the subject. Caller cannot pass a different account id.
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,260026));
 select id into request_id from arena_private.account_deletion_requests where user_id=auth.uid() and state<>'completed';
 if request_id is null then
  insert into arena_private.account_deletion_requests(user_id) values(auth.uid()) returning id into request_id;
  insert into arena_private.legal_audit(actor,event,reference) values(auth.uid(),'deletion_requested',request_id::text);
 end if;return request_id;
end $$;
create function public.admin_legal_overview() returns jsonb language plpgsql stable security definer set search_path=pg_catalog,arena_private,public as $$
begin
 if not public.is_platform_admin_user(auth.uid()) then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 return jsonb_build_object('versions',(select coalesce(jsonb_agg(to_jsonb(v)),'[]'::jsonb) from arena_private.legal_versions v),
 'requests',(select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) from arena_private.account_deletion_requests r),
 'audit',(select coalesce(jsonb_agg(to_jsonb(a)),'[]'::jsonb) from (select * from arena_private.legal_audit order by id desc limit 100)a));
end $$;
revoke all on function public.current_legal_policy(),public.admin_save_legal_draft(text,jsonb),public.accept_legal_policy(text),public.my_deletion_requests(),public.request_account_deletion(),public.admin_legal_overview(),arena_private.guard_legal_version() from public,anon,authenticated,service_role;
grant execute on function public.current_legal_policy() to anon,authenticated;
grant execute on function public.admin_save_legal_draft(text,jsonb),public.accept_legal_policy(text),public.my_deletion_requests(),public.request_account_deletion(),public.admin_legal_overview() to authenticated;
commit;
