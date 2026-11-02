-- Host-pays-all creator cancellation. Ordinary 150-minute policy unchanged.
begin;
alter table public.matches add column cancelled_at timestamptz;
alter table public.matches add column cancelled_by uuid references auth.users(id);
alter table public.match_players drop constraint match_players_status_check;
alter table public.match_players add constraint match_players_status_check check(status in('invited','requested','joined','rejected','cancelled'));

create function arena_private.host_match_cancel_allowed(p_start timestamptz,p_now timestamptz)
returns boolean language sql immutable as $$ select p_now<p_start-interval '90 minutes' $$;

-- Reuse bounded refund ledger; only actual electronically captured funds qualify.
create or replace function arena_private.require_cancelled_match_refund(p_order uuid) returns void
language plpgsql set search_path=public as $$
declare o checkout_orders%rowtype;reason text;begin
 select * into strict o from checkout_orders where id=p_order for update;
 if o.payment_method<>'card' or o.payment_status not in('paid','partially_refunded') then return;end if;
 select cancellation_reason into reason from matches where id=o.match_id;
 perform arena_private.require_policy_refund(o.id,case when reason='HOST_PAYS_ALL_CREATOR_CANCELLED' then 'Host cancelled entire match: 100% electronic payment refund including add-ons' else 'Match cancelled: 100% remaining electronic payment refund' end);
 update checkout_orders set failure_code='MATCH_CANCELLED_REFUND_REQUIRED',updated_at=now() where id=o.id and failure_code is distinct from 'MATCH_CANCELLED_REFUND_REQUIRED';
end $$;

create function public.cancel_host_paid_match(p_match uuid) returns void
language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;n bigint;oid uuid;stamp timestamptz;begin
 perform public.require_oman_user();
 perform arena_private.lock_match(p_match);
 select * into strict m from matches where id=p_match;
 if m.host_id is distinct from auth.uid() or m.payment_mode is distinct from 'host_pays_all' then raise exception 'HOST_PAYS_ALL_CREATOR_ONLY';end if;
 if m.status='cancelled' and m.cancellation_reason='HOST_PAYS_ALL_CREATOR_CANCELLED' then return;end if;
 if m.decision_outcome='confirmed' then raise exception 'WITHDRAWAL_LOCKED_AFTER_CONFIRMATION';end if;
 if m.decision_outcome<>'pending' or not arena_private.host_match_cancel_allowed(m.starts_at,clock_timestamp()) then raise exception 'MATCH_WITHDRAWAL_DEADLINE_PASSED';end if;
 n:=arena_private.eligible_match_players(m.id);stamp:=clock_timestamp();
 -- Same final decision ledger/guard as scheduled 90/80 decision; one atomic outcome.
 insert into arena_private.match_decisions(match_id,outcome,joined_count,max_players,decision_at,processed_at)
 values(m.id,'cancelled',n,m.max_players,m.decision_at,stamp);
 update matches set status='cancelled',decision_outcome='cancelled',decided_at=stamp,decision_joined_count=n,
 cancellation_reason='HOST_PAYS_ALL_CREATOR_CANCELLED',cancelled_at=stamp,cancelled_by=auth.uid() where id=m.id;
 -- Preserve every original payer, including independently paid participant orders.
 for oid in select id from checkout_orders where id=m.checkout_order_id or match_id=m.id order by id loop
  update checkout_orders set cancellation_requested_at=coalesce(cancellation_requested_at,stamp),
   cancellation_requested_by=coalesce(cancellation_requested_by,auth.uid()),cancellation_policy_reason='HOST_PAYS_ALL_CREATOR_CANCELLED',
   entitlement_revoked_at=coalesce(entitlement_revoked_at,stamp),
   fulfillment_status=case when payment_status in('paid','partially_refunded') then 'refund_required' else 'cancelled' end,updated_at=stamp where id=oid;
  perform arena_private.release_policy_addons(oid);
  perform arena_private.require_cancelled_match_refund(oid);
 end loop;
 -- Keep participation history. Notification trigger above sees recipients before this update.
 update match_players set status='cancelled' where match_id=m.id and status<>'cancelled';
end $$;

create or replace function public.phase3_policy_withdrawal() returns trigger
language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;oid uuid;begin
 if tg_op='UPDATE' and (old.status<>'joined' or new.status='joined') then return new;end if;
 perform arena_private.lock_match(old.match_id);
 select * into strict m from matches where id=old.match_id;
 if m.decision_outcome='confirmed' then raise exception 'WITHDRAWAL_LOCKED_AFTER_CONFIRMATION';end if;
 -- Full cancellation already settled each order once; don't manufacture withdrawals/refunds.
 if m.status='cancelled' then if tg_op='DELETE' then return old;else return new;end if;end if;
 if clock_timestamp()>=m.decision_at then raise exception 'MATCH_WITHDRAWAL_DEADLINE_PASSED';end if;
 if old.user_id=m.host_id and m.payment_mode='host_pays_all' then raise exception 'HOST_PAYS_ALL_USE_MATCH_CANCELLATION';end if;
 for oid in select id from checkout_orders where match_id=m.id and user_id=old.user_id and entitlement_revoked_at is null order by id loop
  update checkout_orders set entitlement_revoked_at=clock_timestamp(),cancellation_requested_at=clock_timestamp(),
   cancellation_requested_by=auth.uid(),cancellation_policy_reason='MATCH_WITHDRAWAL_FULL_REFUND',
   fulfillment_status=case when payment_status in('paid','partially_refunded') then 'refund_required' else 'cancelled' end where id=oid;
  perform arena_private.require_policy_refund(oid,'Participant withdrawal before 90-minute decision: 100% electronic payment refund');
 end loop;
 if tg_op='DELETE' then return old;end if;return new;
end $$;

create or replace function public.leave_match(match_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;begin
 perform public.require_oman_user();perform arena_private.lock_match(leave_match.match_id);
 select * into strict m from matches where id=leave_match.match_id;
 if m.host_id=auth.uid() and m.payment_mode='host_pays_all' then perform public.cancel_host_paid_match(m.id);return;end if;
 perform arena_private.decide_match(m.id);
 select * into strict m from matches where id=leave_match.match_id;
 if m.decision_outcome='confirmed' then raise exception 'WITHDRAWAL_LOCKED_AFTER_CONFIRMATION';end if;
 if m.status='cancelled' then return;end if;
 if clock_timestamp()>=m.decision_at then raise exception 'MATCH_WITHDRAWAL_DEADLINE_PASSED';end if;
 delete from match_players where match_players.match_id=leave_match.match_id and user_id=auth.uid();
end $$;

-- Pending checkout has no match until verified fulfillment. Cancel its entitlement safely.
create function public.cancel_pending_host_match_checkout(p_order uuid) returns void
language plpgsql security definer set search_path=public as $$
declare o checkout_orders%rowtype;begin
 perform public.require_oman_user();perform arena_private.lock_payment_match(p_order);
 select * into strict o from checkout_orders where id=p_order for update;
 if o.user_id is distinct from auth.uid() or o.purpose<>'match' or o.payment_mode is distinct from 'host_pays_all' then raise exception 'HOST_PAYS_ALL_CREATOR_ONLY';end if;
 if o.match_id is not null then perform public.cancel_host_paid_match(o.match_id);return;end if;
 if o.cancellation_requested_at is not null then return;end if;
 if not arena_private.host_match_cancel_allowed(o.starts_at,clock_timestamp()) then raise exception 'MATCH_WITHDRAWAL_DEADLINE_PASSED';end if;
 update checkout_orders set cancellation_requested_at=clock_timestamp(),cancellation_requested_by=auth.uid(),
 cancellation_policy_reason='HOST_PAYS_ALL_CREATOR_CANCELLED',entitlement_revoked_at=clock_timestamp(),
 fulfillment_status=case when payment_status in('paid','partially_refunded') then 'refund_required' else 'cancelled' end where id=o.id;
 perform arena_private.release_policy_addons(o.id);
 perform arena_private.require_policy_refund(o.id,'Host cancelled pending match: 100% captured electronic payment refund');
end $$;

create or replace function public.cancel_unstarted_checkout(p_order uuid) returns void
language plpgsql security definer set search_path=public as $$
declare o checkout_orders%rowtype;begin
 select * into strict o from checkout_orders where id=p_order;
 if o.user_id is distinct from auth.uid() then raise exception 'CANCELLATION_NOT_ALLOWED';end if;
 if o.purpose='booking' then perform public.cancel_pending_booking_checkout(p_order);return;end if;
 if o.purpose='match' and o.payment_mode='host_pays_all' then perform public.cancel_pending_host_match_checkout(p_order);return;end if;
 update checkout_orders set fulfillment_status='cancelled',payment_status='cancelled',updated_at=now()
 where id=p_order and user_id=auth.uid() and payment_method='card' and provider_creation_state='not_started' and payment_status='pending';
 if not found then raise exception 'PROVIDER_CANCELLATION_REQUIRED';end if;
end $$;

create or replace function public.my_match_withdrawal_summary(p_match uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;host_cancel boolean;begin
 select * into strict m from matches where id=p_match;
 if auth.uid() is null or not public.can_view_match(p_match,auth.uid()) then raise exception 'NOT_AUTHORIZED';end if;
 host_cancel:=m.host_id=auth.uid() and m.payment_mode='host_pays_all';
 return jsonb_build_object('allowed',m.status<>'cancelled' and m.decision_outcome='pending' and arena_private.host_match_cancel_allowed(m.starts_at,clock_timestamp())
 and (host_cancel or exists(select 1 from match_players where match_id=m.id and user_id=auth.uid() and status='joined')),
 'host_policy_required',false,'cancels_entire_match',coalesce(host_cancel,false),'deadline',m.decision_at,'server_now',clock_timestamp(),
 'expected_refund_baisa',(select coalesce(sum(amount_due_baisa-refunded_amount_baisa),0) from checkout_orders where (match_id=m.id or id=m.checkout_order_id) and user_id=auth.uid() and payment_method='card' and payment_status in('paid','partially_refunded') and entitlement_revoked_at is null));
end $$;

create or replace function public.phase3_match_notification() returns trigger
language plpgsql security definer set search_path=public as $$
declare u uuid;t text;host_cancel boolean;begin
 if tg_op='INSERT' then
  perform arena_private.notify(new.host_id,'match_created','match-created:'||new.id,jsonb_build_object('match_id',new.id),'Your match has been created.','تم إنشاء مباراتك.');
 elsif new.decision_outcome is distinct from old.decision_outcome and new.decision_outcome in('confirmed','cancelled') then
  t:='match_'||new.decision_outcome;host_cancel:=new.cancellation_reason='HOST_PAYS_ALL_CREATOR_CANCELLED';
  for u in select new.host_id union select user_id from match_players where match_id=new.id loop
   perform arena_private.notify(u,t,'match-decision:'||new.id,jsonb_build_object('match_id',new.id),
   case when t='match_confirmed' then 'Match confirmed. Withdrawal is now locked.' when host_cancel then 'The host cancelled the match for everyone. Any eligible refund awaits provider confirmation.' else 'Match cancelled: minimum participation was not reached. Any required refund is pending provider processing.' end,
   case when t='match_confirmed' then 'تأكدت المباراة. لا يمكن الانسحاب الآن.' when host_cancel then 'ألغى المنشئ المباراة للجميع. أي استرداد مستحق ينتظر تأكيد مزود الدفع.' else 'أُلغيت المباراة لعدم اكتمال العدد المطلوب. أي استرداد مستحق ينتظر معالجة مزود الدفع.' end);
  end loop;
 end if;return new;
end $$;

-- A failed refund may be retried, but confirmed totals must never exceed capture.
create or replace function public.payment_confirm_refund(p_refund uuid,p_reference text,p_amount bigint,p_succeeded boolean)
returns void language plpgsql security definer set search_path=public as $$
declare r payment_refunds%rowtype;o checkout_orders%rowtype;total bigint;begin
 select * into strict r from payment_refunds where id=p_refund;
 perform arena_private.lock_payment_match(r.order_id);
 select * into strict o from checkout_orders where id=r.order_id for update;
 select * into strict r from payment_refunds where id=p_refund for update;
 if r.status='succeeded' then
  if r.provider_reference is distinct from p_reference or r.amount_baisa<>p_amount then raise exception 'REFUND_VERIFICATION_MISMATCH';end if;return;
 end if;
 if r.amount_baisa<>p_amount or nullif(p_reference,'') is null then raise exception 'REFUND_VERIFICATION_MISMATCH';end if;
 select coalesce(sum(amount_baisa),0) into total from payment_refunds where order_id=r.order_id and status='succeeded' and id<>r.id;
 if p_succeeded and (o.payment_method<>'card' or total+p_amount>o.amount_due_baisa) then raise exception 'REFUND_EXCEEDS_CAPTURE';end if;
 update payment_refunds set status=case when p_succeeded then 'succeeded' else 'failed' end,provider_reference=p_reference,updated_at=now() where id=r.id;
 select coalesce(sum(amount_baisa),0) into total from payment_refunds where order_id=r.order_id and status='succeeded';
 update checkout_orders set refunded_amount_baisa=total,payment_status=case when total=amount_due_baisa then 'refunded' when total>0 then 'partially_refunded' else payment_status end,updated_at=now() where id=r.order_id;
 update bookings b set payment_status=c.payment_status from checkout_orders c where c.id=r.order_id and b.id=c.booking_id;
end $$;

revoke all on function arena_private.host_match_cancel_allowed(timestamptz,timestamptz),public.cancel_host_paid_match(uuid),public.cancel_pending_host_match_checkout(uuid) from public,anon,authenticated;
grant execute on function public.cancel_host_paid_match(uuid),public.cancel_pending_host_match_checkout(uuid) to authenticated;
commit;
