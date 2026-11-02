-- LOCAL DRAFT ONLY. Not a migration; no automatic application or hook switch.
-- Requires explicit approval and migration version assignment before staging rollout.
begin;
create table public.arena_sms_allowlist (
 phone_hash text primary key check(phone_hash ~ '^[a-f0-9]{64}$'),
 enabled boolean not null default false
);
create table public.arena_sms_attempts (
 event_hash text primary key check(event_hash ~ '^[a-f0-9]{64}$'),
 phone_hash text not null check(phone_hash ~ '^[a-f0-9]{64}$'),
 created_at timestamptz not null default clock_timestamp(),
 state text not null default 'reserved' check(state in ('reserved','accepted','uncertain'))
);
create index arena_sms_phone_time on public.arena_sms_attempts(phone_hash,created_at);
create index arena_sms_time on public.arena_sms_attempts(created_at);
alter table public.arena_sms_allowlist enable row level security;
alter table public.arena_sms_attempts enable row level security;
revoke all on public.arena_sms_allowlist,public.arena_sms_attempts from public,anon,authenticated,service_role;
create function public.arena_sms_reserve(p_event text,p_phone text) returns text
language plpgsql security definer set search_path=pg_catalog,public as $$
declare t timestamptz; existing text;
begin
 if p_event is null or p_phone is null or p_event !~ '^[a-f0-9]{64}$' or p_phone !~ '^[a-f0-9]{64}$' then return 'deny';end if;
 -- Serializes all quotas and reservation checks across concurrent Edge workers.
 perform pg_advisory_xact_lock(726103260001::bigint);t:=clock_timestamp();
 if not exists(select 1 from public.arena_sms_allowlist where phone_hash=p_phone and enabled) then return 'deny';end if;
 select state into existing from public.arena_sms_attempts where event_hash=p_event and phone_hash=p_phone;
 if found then return case when existing='accepted' then 'accepted' else 'deny' end;end if;
 if exists(select 1 from public.arena_sms_attempts where phone_hash=p_phone and created_at>t-interval '60 seconds')
 or (select count(*) from public.arena_sms_attempts where phone_hash=p_phone and created_at>t-interval '1 hour')>=5
 or (select count(*) from public.arena_sms_attempts where phone_hash=p_phone and created_at>t-interval '24 hours')>=10
 or (select count(*) from public.arena_sms_attempts where created_at>t-interval '1 hour')>=30
 or (select count(*) from public.arena_sms_attempts where created_at>t-interval '24 hours')>=100 then return 'deny';end if;
 insert into public.arena_sms_attempts(event_hash,phone_hash) values(p_event,p_phone);return 'send';
end $$;
create function public.arena_sms_finish(p_event text,p_state text) returns void
language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 if p_state not in ('accepted','uncertain') or p_state is null then raise exception 'INVALID_STATE';end if;
 update public.arena_sms_attempts set state=p_state where event_hash=p_event and state='reserved';
end $$;
revoke all on function public.arena_sms_reserve(text,text),public.arena_sms_finish(text,text) from public,anon,authenticated;
grant execute on function public.arena_sms_reserve(text,text),public.arena_sms_finish(text,text) to service_role;
commit;
