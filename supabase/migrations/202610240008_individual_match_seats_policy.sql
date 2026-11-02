-- New individual matches only. Existing orders/matches and host-pays-all retain 90/80.
-- No provider outcome is manufactured here. All money remains integer baisa.
begin;
alter table public.checkout_orders add column individual_policy text not null default 'legacy_90_80'
 check(individual_policy in('legacy_90_80','seats_24h_2h_v1'));
alter table public.checkout_orders add column seat_quantity integer not null default 1 check(seat_quantity between 1 and 3);
alter table public.checkout_orders add column seat_indices integer[];
alter table public.checkout_orders add column seats_confirmed_at timestamptz;
alter table public.matches add column individual_policy text not null default 'legacy_90_80'
 check(individual_policy in('legacy_90_80','seats_24h_2h_v1'));
alter table public.matches add column precheck_at timestamptz;
alter table public.matches add column precheck_outcome text check(precheck_outcome in('passed','cancelled'));
alter table public.match_players add column seat_quantity integer not null default 1 check(seat_quantity between 1 and 3);
create table arena_private.individual_match_checkpoints(
 match_id uuid not null references public.matches(id),checkpoint text not null check(checkpoint in('24h','2h')),
 outcome text not null check(outcome in('passed','confirmed','cancelled')),paid_seats integer not null,
 due_at timestamptz not null,processed_at timestamptz not null default clock_timestamp(),primary key(match_id,checkpoint));
revoke all on arena_private.individual_match_checkpoints from public,anon,authenticated;
create index individual_precheck_due on public.matches(precheck_at)
 where individual_policy='seats_24h_2h_v1' and precheck_outcome is null and decision_outcome='pending';

-- Preserve exact installed legacy implementations. No old migration is rewritten.
do $$ declare signature text;name text;d text;begin
 foreach signature in array array['arena_private.decide_match(uuid)','arena_private.eligible_match_players(uuid)',
 'arena_private.fulfill_order(uuid)','public.create_participant_checkout(uuid,uuid)',
 'public.payment_reconcile(uuid,text,text,text,bigint,text,text,text)','public.process_arena_scheduled_events()',
 'public.match_lifecycle_summary(uuid)','public.match_payment_summary(uuid)','public.my_match_withdrawal_summary(uuid)'] loop
  name:=split_part(split_part(signature,'(',1),'.',2);
  d:=pg_get_functiondef(signature::regprocedure);
  d:=replace(d,'FUNCTION '||split_part(signature,'(',1)||'(','FUNCTION arena_private.'||name||'_before_seats(');
  if position('FUNCTION arena_private.'||name||'_before_seats(' in d)=0 then raise exception 'SOURCE_ANCHOR_MISMATCH';end if;
  execute d;
 end loop;
end $$;

-- Server clock only. No request header, JWT, config setting or client time is read.
create function arena_private.match_decision_clock() returns timestamptz
language sql volatile set search_path=pg_catalog as $$select clock_timestamp()$$;
create function arena_private.seat_total(p_total bigint,p_capacity integer,p_indices integer[])
returns bigint language plpgsql immutable set search_path=public,pg_temp as $$
declare n bigint;begin
 if p_indices is null or cardinality(p_indices) not between 1 and 3 or p_capacity<2
 or exists(select 1 from unnest(p_indices) i where i<0 or i>=p_capacity or i is null)
 or cardinality(p_indices)<>(select count(distinct i) from unnest(p_indices) i) then raise exception 'INVALID_SEAT_QUANTITY';end if;
 select sum(arena_private.share_baisa(p_total,p_capacity,i)) into n from unnest(p_indices) i;return n;
end$$;
create function arena_private.individual_paid_seats(p_match uuid,p_at timestamptz default null)
returns bigint language sql stable set search_path=public,pg_temp as $$
 select coalesce(sum(o.seat_quantity),0) from checkout_orders o join matches m on m.id=p_match
 join profiles p on p.id=o.user_id join auth.users u on u.id=p.id
 where o.match_id=m.id and o.individual_policy='seats_24h_2h_v1'
 and o.seats_confirmed_at is not null and (p_at is null or o.seats_confirmed_at<=p_at)
 and (o.entitlement_revoked_at is null or (p_at is not null and o.entitlement_revoked_at>p_at))
 and (p_at is not null or (o.payment_status='paid' and o.fulfillment_status='fulfilled'
  and exists(select 1 from match_players mp where mp.match_id=m.id and mp.user_id=o.user_id and mp.status='joined' and mp.payment_order_id=o.id)))
 and not exists(select 1 from payment_refunds r where r.order_id=o.id and (p_at is null or r.created_at<=p_at) and r.status<>'failed')
 and p.profile_version=1 and p.onboarding_complete and nullif(trim(p.display_name),'') is not null
 and p.username ~ '^[a-z][a-z0-9_]{3,31}$' and p.date_of_birth is not null and p.gender=m.gender
 and u.phone ~ '^\+?968[0-9]{8}$' and u.phone_confirmed_at is not null;
$$;
create or replace function arena_private.eligible_match_players(p_match uuid) returns bigint
language plpgsql stable set search_path=public,pg_temp as $$begin
 if exists(select 1 from matches where id=p_match and individual_policy='seats_24h_2h_v1') then
  return arena_private.individual_paid_seats(p_match,null);
 end if;return arena_private.eligible_match_players_before_seats(p_match);
end$$;

create function arena_private.cancel_individual_match(p_match uuid,p_checkpoint text,p_count integer) returns void
language plpgsql set search_path=public,pg_temp as $$
declare m matches%rowtype;oid uuid;stamp timestamptz:=arena_private.match_decision_clock();begin
 select * into strict m from matches where id=p_match for update;
 if m.decision_outcome<>'pending' then return;end if;
 insert into arena_private.match_decisions(match_id,outcome,joined_count,max_players,decision_at,processed_at)
 values(m.id,'cancelled',p_count,m.max_players,m.decision_at,stamp);
 update matches set status='cancelled',decision_outcome='cancelled',decided_at=stamp,decision_joined_count=p_count,
 cancellation_reason=case p_checkpoint when '24h' then 'PAID_SEATS_BELOW_80_AT_24H' else 'PAID_SEATS_NOT_FULL_AT_2H' end,
 cancelled_at=stamp where id=m.id;
 for oid in select id from checkout_orders where id=m.checkout_order_id or match_id=m.id order by id loop
  update checkout_orders set cancellation_requested_at=coalesce(cancellation_requested_at,stamp),
   cancellation_policy_reason='INDIVIDUAL_MATCH_AUTO_CANCELLED',entitlement_revoked_at=coalesce(entitlement_revoked_at,stamp),
   fulfillment_status=case when payment_status in('paid','partially_refunded') then 'refund_required' else 'cancelled' end where id=oid;
  perform arena_private.release_policy_addons(oid);
  perform arena_private.require_cancelled_match_refund(oid);
 end loop;
 update match_players set status='cancelled' where match_id=m.id and status<>'cancelled';
end$$;
create or replace function arena_private.decide_match(p_match uuid) returns text
language plpgsql set search_path=public,pg_temp as $$
declare m matches%rowtype;n bigint;stamp timestamptz;begin
 perform arena_private.lock_match(p_match);select * into strict m from matches where id=p_match;
 if m.individual_policy<>'seats_24h_2h_v1' then return arena_private.decide_match_before_seats(p_match);end if;
 if m.decision_outcome<>'pending' then return m.decision_outcome;end if;
 stamp:=arena_private.match_decision_clock();
 if m.precheck_at>stamp then return 'pending';end if;
 -- Historical cutoff accounting prevents late scheduler/payment from rescuing a failed checkpoint.
 if m.precheck_outcome is null then
  n:=arena_private.individual_paid_seats(m.id,m.precheck_at);
  insert into arena_private.individual_match_checkpoints(match_id,checkpoint,outcome,paid_seats,due_at,processed_at)
   values(m.id,'24h',case when n*5>=m.max_players::bigint*4 then 'passed' else 'cancelled' end,n,m.precheck_at,stamp);
  update matches set precheck_outcome=case when n*5>=m.max_players::bigint*4 then 'passed' else 'cancelled' end where id=m.id;
  if n*5<m.max_players::bigint*4 then perform arena_private.cancel_individual_match(m.id,'24h',n::integer);return 'cancelled';end if;
 end if;
 if m.decision_at>stamp then return 'pending';end if;
 n:=arena_private.individual_paid_seats(m.id,m.decision_at);
 insert into arena_private.individual_match_checkpoints(match_id,checkpoint,outcome,paid_seats,due_at,processed_at)
 values(m.id,'2h',case when n=m.max_players then 'confirmed' else 'cancelled' end,n,m.decision_at,stamp);
 if n<>m.max_players then perform arena_private.cancel_individual_match(m.id,'2h',n::integer);return 'cancelled';end if;
 insert into arena_private.match_decisions(match_id,outcome,joined_count,max_players,decision_at,processed_at)
 values(m.id,'confirmed',n,m.max_players,m.decision_at,stamp);
 update matches set status='confirmed',decision_outcome='confirmed',decided_at=stamp,decision_joined_count=n where id=m.id;
 return 'confirmed';
end$$;

create or replace function public.phase3_guard_match() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare d arena_private.match_decisions%rowtype;policy text;begin
 if tg_op='DELETE' then if old.decision_outcome in('confirmed','cancelled') then raise exception 'FINAL_MATCH_DECISION';end if;return old;end if;
 if tg_op='INSERT' then
  select individual_policy into policy from checkout_orders where id=new.checkout_order_id;
  new.individual_policy:=case when new.payment_mode='pay_individually' and policy='seats_24h_2h_v1' then policy else 'legacy_90_80' end;
  new.decision_at:=new.starts_at-case when new.individual_policy='seats_24h_2h_v1' then interval '2 hours' else interval '90 minutes' end;
  new.precheck_at:=case when new.individual_policy='seats_24h_2h_v1' then new.starts_at-interval '24 hours' end;
  new.precheck_outcome:=null;new.decision_outcome:='pending';new.decided_at:=null;new.decision_joined_count:=null;
  if new.status='confirmed' then raise exception 'SERVER_DECISION_REQUIRED';end if;return new;
 end if;
 if new.individual_policy<>old.individual_policy then raise exception 'MATCH_POLICY_IMMUTABLE';end if;
 if old.individual_policy='seats_24h_2h_v1' then
  if (new.arena_id,new.court_id,new.starts_at,new.ends_at,new.max_players,new.checkout_order_id,new.payment_mode,new.decision_at,new.precheck_at)
   is distinct from (old.arena_id,old.court_id,old.starts_at,old.ends_at,old.max_players,old.checkout_order_id,old.payment_mode,old.decision_at,old.precheck_at) then raise exception 'MATCH_SCHEDULE_IMMUTABLE';end if;
  if new.precheck_outcome is distinct from old.precheck_outcome and not exists(select 1 from arena_private.individual_match_checkpoints
    where match_id=old.id and checkpoint='24h' and outcome=new.precheck_outcome) then raise exception 'SERVER_DECISION_REQUIRED';end if;
  if new.decision_outcome is distinct from old.decision_outcome and not exists(select 1 from arena_private.individual_match_checkpoints
   where match_id=old.id and outcome=new.decision_outcome and (new.decision_outcome='cancelled' or (checkpoint='2h' and paid_seats=old.max_players))) then raise exception 'SERVER_DECISION_REQUIRED';end if;
 end if;
 select * into d from arena_private.match_decisions where match_id=old.id;
 if found then
  if new.decision_outcome<>d.outcome or new.decision_joined_count<>d.joined_count or new.decided_at is null or new.decision_at<>d.decision_at
   or (new.arena_id,new.court_id,new.starts_at,new.ends_at,new.max_players,new.checkout_order_id,new.payment_mode)
      is distinct from (old.arena_id,old.court_id,old.starts_at,old.ends_at,old.max_players,old.checkout_order_id,old.payment_mode)
   or (d.outcome='cancelled' and new.status<>'cancelled') or(d.outcome='confirmed' and new.status not in('confirmed','current','previous')) then raise exception 'FINAL_MATCH_DECISION';end if;
 elsif new.decision_outcome<>old.decision_outcome or new.status='confirmed' then raise exception 'SERVER_DECISION_REQUIRED';
 elsif old.individual_policy='legacy_90_80' then new.decision_at:=new.starts_at-interval '90 minutes';end if;
 return new;
end$$;

create function public.individual_order_seats_guard() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare m matches%rowtype;capacity integer;quantity integer;begin
 if tg_op='INSERT' then
  if new.purpose='match' and new.payment_mode='pay_individually' then
   if new.starts_at<=arena_private.match_decision_clock()+interval '24 hours' then raise exception 'INDIVIDUAL_MATCH_REQUIRES_24_HOURS';end if;
   quantity:=coalesce((new.request_payload->>'seat_quantity')::integer,1);capacity:=(new.request_payload->>'capacity')::integer;
   if quantity not between 1 and 3 or quantity>capacity then raise exception 'INVALID_SEAT_QUANTITY';end if;
   new.individual_policy:='seats_24h_2h_v1';new.seat_quantity:=quantity;
   select array_agg(i order by i) into new.seat_indices from generate_series(0,quantity-1) i;
   new.amount_due_baisa:=arena_private.seat_total(new.total_amount_baisa,capacity,new.seat_indices);
  elsif new.purpose='participant' then
   perform arena_private.lock_match(new.match_id);select * into strict m from matches where id=new.match_id;
   if m.individual_policy='seats_24h_2h_v1' then
    new.individual_policy:=m.individual_policy;capacity:=m.max_players;
    if new.seat_quantity not between 1 and 3 or cardinality(new.seat_indices)<>new.seat_quantity then raise exception 'INVALID_SEAT_QUANTITY';end if;
    if new.amount_due_baisa<>arena_private.seat_total(m.total_amount_baisa,capacity,new.seat_indices) then raise exception 'SEAT_PRICE_MISMATCH';end if;
    if exists(select 1 from checkout_orders o where o.match_id=m.id and o.entitlement_revoked_at is null
      and o.fulfillment_status in('pending','fulfilled') and coalesce(o.seat_indices,array[o.seat_index])&&new.seat_indices) then raise exception 'SEAT_UNAVAILABLE';end if;
   else new.individual_policy:='legacy_90_80';new.seat_quantity:=1;new.seat_indices:=null;end if;
  else new.individual_policy:='legacy_90_80';new.seat_quantity:=1;new.seat_indices:=null;end if;
  new.seats_confirmed_at:=null;
 else
  if (new.individual_policy,new.seat_quantity,new.seat_indices) is distinct from (old.individual_policy,old.seat_quantity,old.seat_indices)
   or (old.individual_policy='seats_24h_2h_v1' and (new.amount_due_baisa,new.user_id) is distinct from (old.amount_due_baisa,old.user_id)) then raise exception 'SEAT_ENTITLEMENT_IMMUTABLE';end if;
  if new.seats_confirmed_at is distinct from old.seats_confirmed_at then raise exception 'SEAT_ENTITLEMENT_IMMUTABLE';end if;
  if old.seats_confirmed_at is null and new.individual_policy='seats_24h_2h_v1' and new.payment_status='paid' and new.fulfillment_status='fulfilled' then
   new.seats_confirmed_at:=arena_private.match_decision_clock();
  end if;
 end if;return new;
end$$;
create trigger individual_order_seats_guard before insert or update on public.checkout_orders for each row execute function public.individual_order_seats_guard();

create or replace function arena_private.fulfill_order(p_id uuid) returns void
language plpgsql set search_path=public,pg_temp as $$
declare o checkout_orders%rowtype;m matches%rowtype;begin
 -- Caller already owns arena -> match -> order locks through payment_reconcile.
 select * into strict o from checkout_orders where id=p_id;
 if o.individual_policy='seats_24h_2h_v1' and o.fulfillment_status<>'fulfilled' then
  if o.purpose='match' and o.starts_at<=arena_private.match_decision_clock()+interval '24 hours' then raise exception 'INDIVIDUAL_MATCH_CREATION_DEADLINE_PASSED';end if;
  if o.purpose='participant' then
   perform arena_private.lock_match(o.match_id);perform arena_private.decide_match(o.match_id);
   select * into strict m from matches where id=o.match_id;
   if m.status='cancelled' or arena_private.match_decision_clock()>=m.decision_at then raise exception 'INDIVIDUAL_MATCH_JOIN_CLOSED';end if;
  end if;
 end if;
 perform arena_private.fulfill_order_before_seats(p_id);
end$$;

create function public.create_match_seat_checkout(p_match uuid,p_request_key uuid,p_seat_quantity integer)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=public.require_oman_user();m matches%rowtype;o checkout_orders%rowtype;h checkout_orders%rowtype;indices integer[];prior jsonb;begin
 if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
 if p_seat_quantity is null or p_seat_quantity not between 1 and 3 then raise exception 'INVALID_SEAT_QUANTITY';end if;
 perform arena_private.lock_match(p_match);select * into strict m from matches where id=p_match;
 if m.individual_policy<>'seats_24h_2h_v1' then
  if p_seat_quantity<>1 then raise exception 'LEGACY_MATCH_ONE_SEAT_ONLY';end if;
  return arena_private.create_participant_checkout_before_seats(p_match,p_request_key);
 end if;
 prior:=arena_private.begin_request(p_request_key,'participant',jsonb_build_object('match_id',p_match,'seat_quantity',p_seat_quantity));
 if prior is not null then select * into strict o from checkout_orders where id=(prior->>'id')::uuid and user_id=u;return to_jsonb(o);end if;
 perform arena_private.decide_match(p_match);select * into strict m from matches where id=p_match;
 if m.status='cancelled' or arena_private.match_decision_clock()>=m.decision_at then raise exception 'MATCH_UNAVAILABLE';end if;
 if not exists(select 1 from profiles where id=u and gender=m.gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
 if m.is_private and m.host_id<>u and not exists(select 1 from match_players where match_id=m.id and user_id=u and status in('invited','joined')) then raise exception 'INVITATION_REQUIRED';end if;
 select * into strict h from checkout_orders where id=m.checkout_order_id;
 if not ((h.payment_status='paid' and h.fulfillment_status='fulfilled') or (h.entitlement_revoked_at is not null and h.cancellation_policy_reason='MATCH_WITHDRAWAL_FULL_REFUND')) then raise exception 'HOST_PAYMENT_REQUIRED';end if;
 select * into o from checkout_orders where match_id=m.id and user_id=u and fulfillment_status in('pending','fulfilled') and entitlement_revoked_at is null;
 if found then
  if o.seat_quantity<>p_seat_quantity then raise exception 'SEAT_QUANTITY_ALREADY_RESERVED';end if;
 else
  select array_agg(s order by s) into indices from (select s from generate_series(0,m.max_players-1) s where not exists(
   select 1 from checkout_orders x where x.match_id=m.id and x.fulfillment_status in('pending','fulfilled') and x.entitlement_revoked_at is null
   and s=any(coalesce(x.seat_indices,array[x.seat_index]))) order by s limit p_seat_quantity) slots;
  if coalesce(cardinality(indices),0)<>p_seat_quantity then raise exception 'MATCH_FULL';end if;
  insert into checkout_orders(user_id,arena_id,request_key,request_payload,purpose,payment_method,payment_status,base_amount_baisa,total_amount_baisa,amount_due_baisa,
   starts_at,ends_at,payment_mode,seat_index,match_id,individual_policy,seat_quantity,seat_indices)
  values(u,m.arena_id,p_request_key,jsonb_build_object('match_id',m.id,'seat_quantity',p_seat_quantity),'participant','card','pending',h.base_amount_baisa,m.total_amount_baisa,
   arena_private.seat_total(m.total_amount_baisa,m.max_players,indices),m.starts_at,m.ends_at,m.payment_mode,indices[1],m.id,m.individual_policy,p_seat_quantity,indices) returning * into o;
 end if;
 update arena_private.requests set result=jsonb_build_object('id',o.id) where user_id=u and request_key=p_request_key;return to_jsonb(o);
end$$;
create or replace function public.create_participant_checkout(p_match uuid,p_request_key uuid) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$begin
 if exists(select 1 from matches where id=p_match and individual_policy='seats_24h_2h_v1') then return public.create_match_seat_checkout(p_match,p_request_key,1);end if;
 return arena_private.create_participant_checkout_before_seats(p_match,p_request_key);
end$$;

-- Bind membership quantity to the verified order, including the host's initial seats.
create or replace function public.enforce_match_payment_entitlement() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare m matches%rowtype;o checkout_orders%rowtype;begin
 select * into strict m from matches where id=new.match_id;
 if m.individual_policy='seats_24h_2h_v1' and new.status='joined' then
  select * into o from checkout_orders where id=new.payment_order_id and user_id=new.user_id and match_id in(m.id)
   and payment_status='paid' and entitlement_revoked_at is null and not exists(select 1 from payment_refunds where order_id=checkout_orders.id and status<>'failed');
  -- Host match_id is bound only at the end of fulfillment.
  if not found and new.user_id=m.host_id then select * into o from checkout_orders where id=m.checkout_order_id and id=new.payment_order_id and user_id=new.user_id and payment_status='paid' and entitlement_revoked_at is null;end if;
  if o.id is null or o.individual_policy<>'seats_24h_2h_v1' or o.amount_due_baisa<>arena_private.seat_total(m.total_amount_baisa,m.max_players,o.seat_indices) then raise exception 'PARTICIPANT_PAYMENT_REQUIRED';end if;
  if (select coalesce(sum(x.seat_quantity),0) from match_players x where x.match_id=m.id and x.status='joined' and x.user_id<>new.user_id)+o.seat_quantity>m.max_players then raise exception 'MATCH_FULL';end if;
  new.seat_quantity:=o.seat_quantity;new.covered_by_host:=false;return new;
 end if;
 new.seat_quantity:=1;
 if m.checkout_order_id is null or new.status<>'joined' then return new;end if;
 if m.payment_mode='host_pays_all' and exists(select 1 from checkout_orders where id=m.checkout_order_id and payment_status='paid' and amount_due_baisa=m.total_amount_baisa) then new.covered_by_host:=true;return new;end if;
 if not exists(select 1 from checkout_orders where id=new.payment_order_id and user_id=new.user_id and payment_status='paid' and entitlement_revoked_at is null and not exists(select 1 from payment_refunds r where r.order_id=checkout_orders.id and r.status<>'failed') and (match_id=m.id or id=m.checkout_order_id)) then raise exception 'PARTICIPANT_PAYMENT_REQUIRED';end if;
 new.covered_by_host:=false;return new;
end$$;

create or replace function public.phase3_policy_withdrawal() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare m matches%rowtype;oid uuid;stamp timestamptz;begin
 if tg_op='UPDATE' and (old.status<>'joined' or new.status='joined') then return new;end if;
 perform arena_private.lock_match(old.match_id);select * into strict m from matches where id=old.match_id;
 stamp:=case when m.individual_policy='seats_24h_2h_v1' then arena_private.match_decision_clock() else clock_timestamp() end;
 if m.decision_outcome='confirmed' then raise exception 'WITHDRAWAL_LOCKED_AFTER_CONFIRMATION';end if;
 if m.status='cancelled' then if tg_op='DELETE' then return old;else return new;end if;end if;
 if (case when m.individual_policy='seats_24h_2h_v1' then arena_private.match_decision_clock() else clock_timestamp() end)>=m.decision_at then raise exception 'MATCH_WITHDRAWAL_DEADLINE_PASSED';end if;
 if old.user_id=m.host_id and m.payment_mode='host_pays_all' then raise exception 'HOST_PAYS_ALL_USE_MATCH_CANCELLATION';end if;
 for oid in select id from checkout_orders where match_id=m.id and user_id=old.user_id and entitlement_revoked_at is null order by id loop
  update checkout_orders set entitlement_revoked_at=stamp,cancellation_requested_at=stamp,cancellation_requested_by=auth.uid(),cancellation_policy_reason='MATCH_WITHDRAWAL_FULL_REFUND',
   fulfillment_status=case when payment_status in('paid','partially_refunded') then 'refund_required' else 'cancelled' end where id=oid;
  perform arena_private.require_policy_refund(oid,'Participant withdrawal before decision: full refund for all paid seats');
 end loop;
 if tg_op='DELETE' then return old;end if;return new;
end$$;

create or replace function public.payment_reconcile(p_order uuid,p_session text,p_reference text,p_currency text,p_amount bigint,p_status text,p_invoice text,p_event_key text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare result jsonb;o checkout_orders%rowtype;begin
 result:=arena_private.payment_reconcile_before_seats(p_order,p_session,p_reference,p_currency,p_amount,p_status,p_invoice,p_event_key);
 select * into strict o from checkout_orders where id=p_order;
 -- Fulfillment failures use a subtransaction. Re-evaluate outside it so a due
 -- cancellation is committed even when that particular payment cannot join.
 if o.individual_policy='seats_24h_2h_v1' and o.match_id is not null then
  perform arena_private.decide_match(o.match_id);select * into strict o from checkout_orders where id=p_order;
 end if;
 if o.individual_policy='seats_24h_2h_v1' and o.payment_status in('paid','partially_refunded') and o.fulfillment_status='refund_required' then
  perform arena_private.require_policy_refund(o.id,'Individual match cannot fulfill: full refund of captured seats');
 end if;
 return to_jsonb(o);
end$$;

create or replace function public.process_arena_scheduled_events() returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare r record;err text;result jsonb;processed integer:=0;errors integer:=0;terminals integer:=0;outcome text;begin
 if not pg_try_advisory_xact_lock(hashtextextended('arena-phase3-scheduler',0)) then return jsonb_build_object('busy',true);end if;
 for r in select id from matches where individual_policy='seats_24h_2h_v1' and decision_outcome='pending'
  and ((precheck_outcome is null and precheck_at<=arena_private.match_decision_clock()) or decision_at<=arena_private.match_decision_clock())
  and decision_next_attempt_at<=clock_timestamp() order by arena_id,id limit 200 loop
  begin outcome:=arena_private.decide_match(r.id);processed:=processed+1;if outcome<>'pending' then terminals:=terminals+1;end if;
  exception when others then
   get stacked diagnostics err=message_text;errors:=errors+1;
   update matches set decision_attempt_count=decision_attempt_count+1,decision_last_error=left(err,200),decision_next_attempt_at=clock_timestamp()+interval '30 seconds' where id=r.id;
   insert into arena_scheduled_job_runs(outcome,processed_at,failed_match_id,last_error) values('failed',clock_timestamp(),r.id,left(err,200));
  end;
 end loop;
 result:=arena_private.process_arena_scheduled_events_before_seats();
 if processed>0 or errors>0 then
  insert into arena_scheduled_job_runs(outcome,processed_at,decision_count,last_error)
  values(case when errors>0 then 'failed' else 'succeeded' end,clock_timestamp(),terminals,
   case when errors>0 then 'INDIVIDUAL_CHECKPOINT_FAILURE: see per-match records' end);
 end if;
 return result||jsonb_build_object('decisions',coalesce((result->>'decisions')::integer,0)+terminals,
  'individual_prechecks',processed,'individual_precheck_errors',errors);
end$$;

revoke all on function public.individual_order_seats_guard() from public,anon,authenticated;
revoke all on function public.create_match_seat_checkout(uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.create_match_seat_checkout(uuid,uuid,integer) to authenticated;
revoke all on all functions in schema arena_private from public,anon,authenticated;
commit;
