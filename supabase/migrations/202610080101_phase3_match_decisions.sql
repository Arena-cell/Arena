-- Phase 3: one final 90/80 decision, financial safety and legacy-path guards.
-- Existing ended matches are retained as historical, without retrospective decisions.
begin;
alter table public.matches add column decision_at timestamptz;
alter table public.matches add column decision_outcome text not null default 'pending'
  check(decision_outcome in('pending','confirmed','cancelled','historical'));
alter table public.matches add column decided_at timestamptz;
alter table public.matches add column decision_joined_count integer;
alter table public.matches add column cancellation_reason text;
update public.matches set decision_at=starts_at-interval '90 minutes',
 decision_outcome=case when starts_at<=now() or status='cancelled' then 'historical' else 'pending' end;
alter table public.matches alter column decision_at set not null;
alter table public.matches drop constraint matches_status_check;
alter table public.matches add constraint matches_status_check
 check(status in('upcoming','confirmed','current','previous','cancelled'));
create index phase3_due_matches on public.matches(decision_at) where decision_outcome='pending';
create table arena_private.match_decisions(
 match_id uuid primary key references public.matches(id),
 outcome text not null check(outcome in('confirmed','cancelled')),
 joined_count integer not null, max_players integer not null,
 decision_at timestamptz not null, processed_at timestamptz not null default clock_timestamp());

-- Same arena lock already used by Phase 1 inventory and Phase 2 fulfillment.
-- Take arena -> match -> financial order, never the reverse.
create function arena_private.lock_match(p_match uuid) returns void
language plpgsql set search_path=public as $$
declare a uuid;begin
 select arena_id into a from matches where id=p_match;
 if a is null then raise exception 'MATCH_NOT_FOUND';end if;
 perform pg_advisory_xact_lock(hashtextextended(a::text,0));
 perform 1 from matches where id=p_match for update;
end $$;
create function arena_private.lock_payment_match(p_order uuid) returns void
language plpgsql set search_path=public as $$
declare o checkout_orders%rowtype;begin
 select * into strict o from checkout_orders where id=p_order;
 perform pg_advisory_xact_lock(hashtextextended(o.arena_id::text,0));
 if o.match_id is not null then perform arena_private.lock_match(o.match_id);end if;
end $$;
create function arena_private.eligible_match_players(p_match uuid) returns bigint
language sql stable set search_path=public as $$
 select count(*) from match_players mp join matches m on m.id=mp.match_id
 join profiles p on p.id=mp.user_id join auth.users u on u.id=p.id
 where m.id=p_match and mp.status='joined' and p.profile_version=1 and p.onboarding_complete
 and nullif(trim(p.display_name),'') is not null and p.username ~ '^[a-z][a-z0-9_]{3,31}$'
 and p.date_of_birth is not null and p.gender=m.gender and u.phone ~ '^\+?968[0-9]{8}$'
 and u.phone_confirmed_at is not null and (
 m.checkout_order_id is null or
 (m.payment_mode='host_pays_all' and mp.covered_by_host and exists(
   select 1 from checkout_orders o where o.id=m.checkout_order_id and o.payment_status='paid'
   and o.fulfillment_status='fulfilled' and o.amount_due_baisa=m.total_amount_baisa)) or
 (m.payment_mode='pay_individually' and exists(select 1 from checkout_orders o
   where o.id=mp.payment_order_id and o.user_id=mp.user_id and o.payment_status='paid'
   and o.fulfillment_status='fulfilled' and (o.match_id=m.id or o.id=m.checkout_order_id))) );
$$;

-- A deterministic request key and order lock prevent duplicate cancellation refunds.
create function arena_private.require_cancelled_match_refund(p_order uuid) returns void
language plpgsql set search_path=public as $$
declare o checkout_orders%rowtype;reserved bigint;remaining bigint;begin
 select * into strict o from checkout_orders where id=p_order for update;
 if o.payment_method<>'card' or o.payment_status not in('paid','partially_refunded') then return;end if;
 select coalesce(sum(amount_baisa),0) into reserved from payment_refunds where order_id=o.id and status<>'failed';
 remaining:=o.amount_due_baisa-reserved;
 update checkout_orders set fulfillment_status='refund_required',failure_code='MATCH_CANCELLED_REFUND_REQUIRED',updated_at=now() where id=o.id;
 if remaining>0 then
  insert into payment_refunds(order_id,request_key,original_amount_baisa,amount_baisa,reason)
  values(o.id,md5('phase3-match-cancel:'||o.id::text)::uuid,o.amount_due_baisa,remaining,'Match cancelled: minimum confirmed participation not reached')
  on conflict(request_key) do nothing;
 end if;
end $$;

create function arena_private.decide_match(p_match uuid) returns text
language plpgsql set search_path=public as $$
declare m matches%rowtype;n bigint;outcome text;o record;begin
 perform arena_private.lock_match(p_match);
 select * into strict m from matches where id=p_match;
 if m.decision_outcome<>'pending' then return m.decision_outcome;end if;
 if m.decision_at>clock_timestamp() then return 'pending';end if;
 if m.status='cancelled' then return 'cancelled';end if;
 -- The host row is created during fulfillment before its order is finalized.
 if m.checkout_order_id is not null and not exists(select 1 from checkout_orders
   where id=m.checkout_order_id and fulfillment_status='fulfilled' and payment_status='paid') then return 'pending';end if;
 n:=arena_private.eligible_match_players(m.id);
 outcome:=case when n*5>=m.max_players::bigint*4 then 'confirmed' else 'cancelled' end;
 insert into arena_private.match_decisions(match_id,outcome,joined_count,max_players,decision_at)
 values(m.id,outcome,n,m.max_players,m.decision_at);
 update matches set decision_outcome=outcome,decided_at=clock_timestamp(),decision_joined_count=n,
  status=outcome,cancellation_reason=case when outcome='cancelled' then 'MINIMUM_PARTICIPATION_NOT_REACHED' end where id=m.id;
 if outcome='cancelled' then
  for o in select id from checkout_orders where id=m.checkout_order_id or match_id=m.id order by id loop
   perform arena_private.require_cancelled_match_refund(o.id);
  end loop;
 end if;
 return outcome;
end $$;

create function public.phase3_guard_match() returns trigger
language plpgsql security definer set search_path=public as $$
declare d arena_private.match_decisions%rowtype;begin
 if tg_op='DELETE' then
  if old.decision_outcome in('confirmed','cancelled') then raise exception 'FINAL_MATCH_DECISION';end if;
  return old;
 end if;
 if tg_op='INSERT' then
  new.decision_at:=new.starts_at-interval '90 minutes';
  new.decision_outcome:='pending';new.decided_at:=null;new.decision_joined_count:=null;
  if new.status='confirmed' then raise exception 'SERVER_DECISION_REQUIRED';end if;
  return new;
 end if;
 select * into d from arena_private.match_decisions where match_id=old.id;
 if found then
  if new.decision_outcome<>d.outcome or new.decision_joined_count<>d.joined_count
   or new.decided_at is null or new.decision_at<>d.decision_at
   or (new.arena_id,new.court_id,new.starts_at,new.ends_at,new.max_players,new.checkout_order_id,new.payment_mode)
      is distinct from (old.arena_id,old.court_id,old.starts_at,old.ends_at,old.max_players,old.checkout_order_id,old.payment_mode)
   or (d.outcome='cancelled' and new.status<>'cancelled')
   or (d.outcome='confirmed' and new.status not in('confirmed','current','previous'))
   then raise exception 'FINAL_MATCH_DECISION';end if;
 elsif new.decision_outcome<>old.decision_outcome or new.status='confirmed' then
  raise exception 'SERVER_DECISION_REQUIRED';
 else new.decision_at:=new.starts_at-interval '90 minutes';
 end if;
 return new;
end $$;
create trigger phase3_match_guard before insert or update or delete on public.matches
 for each row execute function public.phase3_guard_match();

create function public.phase3_guard_membership() returns trigger
language plpgsql security definer set search_path=public as $$
declare mid uuid;m matches%rowtype;begin
 mid:=case when tg_op='DELETE' then old.match_id else new.match_id end;
 if tg_op='UPDATE' and (new.match_id,new.user_id) is distinct from (old.match_id,old.user_id) then raise exception 'MEMBERSHIP_ID_IMMUTABLE';end if;
 perform arena_private.lock_match(mid);
 perform arena_private.decide_match(mid);
 select * into strict m from matches where id=mid;
 if tg_op='DELETE' or (tg_op='UPDATE' and old.status='joined' and new.status<>'joined') then
  if m.decision_outcome='confirmed' then raise exception 'WITHDRAWAL_LOCKED_AFTER_CONFIRMATION';end if;
 elsif (tg_op='INSERT' or old.status is distinct from new.status) and new.status in('joined','requested','invited') then
  if m.status='cancelled' or m.starts_at<=clock_timestamp() then raise exception 'MATCH_UNAVAILABLE';end if;
 end if;
 if tg_op='DELETE' then return old;else return new;end if;
end $$;
create trigger phase3_membership_guard before insert or update or delete on public.match_players
 for each row execute function public.phase3_guard_membership();

-- Catch host creation at/after the cutoff and late verified captures.
create function public.phase3_financial_lifecycle() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if new.match_id is not null then
  if exists(select 1 from matches where id=new.match_id and status='cancelled') then
   if new.fulfillment_status<>'refund_required' and new.payment_status in('paid','partially_refunded') then
    perform arena_private.require_cancelled_match_refund(new.id);
   end if;
  elsif new.purpose='match' and new.fulfillment_status='fulfilled' and new.payment_status='paid'
    and (old.fulfillment_status is distinct from new.fulfillment_status or old.match_id is distinct from new.match_id) then
   perform arena_private.decide_match(new.match_id);
  end if;
 end if;
 return new;
end $$;
create trigger phase3_financial_lifecycle after update on public.checkout_orders
 for each row execute function public.phase3_financial_lifecycle();

revoke all on function arena_private.lock_match(uuid),arena_private.lock_payment_match(uuid),
 arena_private.eligible_match_players(uuid),arena_private.require_cancelled_match_refund(uuid),arena_private.decide_match(uuid),
 public.phase3_guard_match(),public.phase3_guard_membership(),public.phase3_financial_lifecycle() from public,anon,authenticated;
commit;
