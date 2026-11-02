-- Additive policy: ordinary bookings 150 minutes; matches retain 90 minutes.
begin;
alter table public.checkout_orders add column cancellation_requested_at timestamptz;
alter table public.checkout_orders add column cancellation_requested_by uuid references auth.users(id);
alter table public.checkout_orders add column cancellation_policy_reason text;
alter table public.checkout_orders add column entitlement_revoked_at timestamptz;
alter table public.booking_addons add column inventory_tracked boolean not null default false;
alter table public.booking_addons add column stock_debited_quantity integer not null default 0 check(stock_debited_quantity>=0 and stock_debited_quantity<=quantity);
alter table public.booking_addons add column delivered_quantity integer check(delivered_quantity>=0 and delivered_quantity<=quantity);
alter table public.booking_addons add column restored_quantity integer not null default 0 check(restored_quantity>=0 and restored_quantity<=stock_debited_quantity);
alter table public.booking_addons add column released_at timestamptz;
alter table public.booking_addons add column delivery_recorded_at timestamptz;
alter table public.booking_addons add column delivery_recorded_by uuid references auth.users(id);
-- Historical consumption/delivery is unknown. Never infer stock debit or delivery.
drop index public.checkout_participant_once;
create unique index checkout_participant_once on public.checkout_orders(match_id,user_id)
 where purpose='participant' and fulfillment_status<>'cancelled' and entitlement_revoked_at is null;

create function arena_private.booking_cancel_allowed(p_start timestamptz,p_now timestamptz)
returns boolean language sql immutable as $$ select p_start>=p_now+interval '150 minutes' $$;

create function arena_private.require_policy_refund(p_order uuid,p_reason text) returns void
language plpgsql set search_path=public as $$
declare o checkout_orders%rowtype;reserved bigint;remaining bigint;begin
 select * into strict o from checkout_orders where id=p_order for update;
 if o.payment_method<>'card' or o.payment_status not in('paid','partially_refunded') then return;end if;
 select coalesce(sum(amount_baisa),0) into reserved from payment_refunds where order_id=o.id and status<>'failed';
 remaining:=least(o.amount_due_baisa-o.refunded_amount_baisa,o.amount_due_baisa-reserved);
 if o.fulfillment_status<>'refund_required' then
  update checkout_orders set fulfillment_status='refund_required',updated_at=now() where id=o.id;
 end if;
 if remaining>0 then
  insert into payment_refunds(order_id,request_key,original_amount_baisa,amount_baisa,reason,requested_by)
  values(o.id,md5('phase3-policy-refund:'||o.id::text||':'||reserved::text)::uuid,o.amount_due_baisa,remaining,p_reason,o.cancellation_requested_by)
  on conflict(request_key) do nothing;
 end if;
end $$;

create function arena_private.release_policy_addons(p_order uuid) returns void
language plpgsql set search_path=public as $$
declare b booking_addons%rowtype;o checkout_orders%rowtype;n integer;begin
 select * into strict o from checkout_orders where id=p_order;
 perform pg_advisory_xact_lock(hashtextextended(o.arena_id::text,0));
 for b in select * from booking_addons where order_id=p_order order by arena_addon_id for update loop
  if b.released_at is not null then continue;end if;
  n:=0;
  if b.kind='consumable' and b.inventory_tracked and b.delivered_quantity is not null then
   n:=greatest(0,least(b.stock_debited_quantity,b.quantity-b.delivered_quantity)-b.restored_quantity);
   if n>0 then
    update arena_addons set stock=stock+n,updated_at=now() where id=b.arena_addon_id and stock is not null;
    if not found then raise exception 'STOCK_TRACKING_REQUIRES_REVIEW';end if;
   end if;
  end if;
  update booking_addons set released_at=clock_timestamp(),restored_quantity=restored_quantity+n where id=b.id;
 end loop;
end $$;

create function public.phase3_policy_booking_guard() returns trigger
language plpgsql security definer set search_path=public as $$ begin
 if new.status='cancelled' and old.status<>'cancelled' then
  perform pg_advisory_xact_lock(hashtextextended(old.arena_id::text,0));
  if auth.uid() is not null and not public.is_arena_operator(old.arena_id) then
   if old.user_id is distinct from auth.uid() or old.booking_type='manual' then raise exception 'CANCELLATION_NOT_ALLOWED';end if;
   if not arena_private.booking_cancel_allowed(old.starts_at,clock_timestamp()) then raise exception 'BOOKING_CANCELLATION_DEADLINE_PASSED';end if;
  end if;
 end if;return new;
end $$;
create trigger phase3_policy_booking_guard before update of status on public.bookings
 for each row execute function public.phase3_policy_booking_guard();

create function public.phase3_policy_booking_cancel() returns trigger
language plpgsql security definer set search_path=public as $$ begin
 if new.status='cancelled' and old.status<>'cancelled' and new.checkout_order_id is not null then
  update checkout_orders set cancellation_requested_at=coalesce(cancellation_requested_at,new.cancelled_at,clock_timestamp()),
   cancellation_requested_by=coalesce(cancellation_requested_by,new.cancelled_by),
   cancellation_policy_reason='BOOKING_CANCELLED_FULL_REFUND',entitlement_revoked_at=coalesce(entitlement_revoked_at,clock_timestamp()) where id=new.checkout_order_id;
  perform arena_private.release_policy_addons(new.checkout_order_id);
  perform arena_private.require_policy_refund(new.checkout_order_id,'Ordinary booking cancelled: 100% electronic payment refund including add-ons');
 end if;return new;
end $$;
create trigger phase3_policy_booking_cancel after update of status on public.bookings
 for each row execute function public.phase3_policy_booking_cancel();

create or replace function public.cancel_arena_booking(p_booking_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare b bookings%rowtype;a uuid;begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if nullif(trim(p_reason),'') is null then raise exception 'CANCELLATION_REASON_REQUIRED';end if;
 select arena_id into a from bookings where id=p_booking_id;
 if a is null then raise exception 'BOOKING_NOT_FOUND';end if;
 perform pg_advisory_xact_lock(hashtextextended(a::text,0));
 select * into strict b from bookings where id=p_booking_id for update;
 if not public.is_arena_operator(a) and (b.user_id is distinct from auth.uid() or b.booking_type='manual') then raise exception 'CANCELLATION_NOT_ALLOWED';end if;
 if b.status='cancelled' then return;end if;
 update bookings set status='cancelled',cancelled_by=auth.uid(),cancelled_at=clock_timestamp(),cancellation_reason=trim(p_reason) where id=b.id;
end $$;

create function public.cancel_pending_booking_checkout(p_order uuid) returns void
language plpgsql security definer set search_path=public as $$
declare o checkout_orders%rowtype;begin
 perform arena_private.lock_payment_match(p_order);
 select * into strict o from checkout_orders where id=p_order for update;
 if o.user_id is distinct from auth.uid() or o.purpose<>'booking' then raise exception 'CANCELLATION_NOT_ALLOWED';end if;
 if o.booking_id is not null then perform cancel_arena_booking(o.booking_id,'User cancelled ordinary booking');return;end if;
 if o.cancellation_requested_at is not null then return;end if;
 if not arena_private.booking_cancel_allowed(o.starts_at,clock_timestamp()) then raise exception 'BOOKING_CANCELLATION_DEADLINE_PASSED';end if;
 update checkout_orders set cancellation_requested_at=clock_timestamp(),cancellation_requested_by=auth.uid(),
  cancellation_policy_reason='BOOKING_CANCELLED_FULL_REFUND',entitlement_revoked_at=clock_timestamp(),
  fulfillment_status=case when payment_status in('paid','partially_refunded') then 'refund_required' else 'cancelled' end where id=o.id;
 perform arena_private.release_policy_addons(o.id);
 perform arena_private.require_policy_refund(o.id,'Ordinary booking cancelled: 100% electronic payment refund including add-ons');
end $$;

create function public.phase3_policy_order_lifecycle() returns trigger
language plpgsql security definer set search_path=public as $$ begin
 if new.fulfillment_status='fulfilled' and old.fulfillment_status='pending' then
  update booking_addons b set inventory_tracked=true,delivered_quantity=0,
   stock_debited_quantity=case when b.kind='consumable' and a.stock is not null then b.quantity else 0 end
   from arena_addons a where b.order_id=new.id and b.arena_addon_id=a.id;
 end if;
 if new.cancellation_requested_at is not null and new.payment_status in('paid','partially_refunded')
  and (old.payment_status is distinct from new.payment_status or old.cancellation_requested_at is null) then
  perform arena_private.require_policy_refund(new.id,'Cancelled/withdrawn entitlement: 100% electronic payment refund');
 end if;return new;
end $$;
-- Track the committed fulfillment debit before the existing decision trigger can cancel a newly-created match.
create trigger phase0_policy_order_lifecycle after update on public.checkout_orders for each row execute function public.phase3_policy_order_lifecycle();

create function public.phase3_policy_match_addons() returns trigger
language plpgsql security definer set search_path=public as $$ begin
 if new.status='cancelled' and old.status<>'cancelled' and new.checkout_order_id is not null then
  perform arena_private.release_policy_addons(new.checkout_order_id);
 end if;return new;
end $$;
create trigger phase3_policy_match_addons after update of status on public.matches for each row execute function public.phase3_policy_match_addons();

create function public.phase3_policy_withdrawal() returns trigger
language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;oid uuid;begin
 if tg_op='UPDATE' and (old.status<>'joined' or new.status='joined') then return new;end if;
 perform arena_private.lock_match(old.match_id);
 select * into strict m from matches where id=old.match_id;
 if m.decision_outcome='confirmed' then raise exception 'WITHDRAWAL_LOCKED_AFTER_CONFIRMATION';end if;
 if m.decision_outcome<>'cancelled' and clock_timestamp()>=m.decision_at then raise exception 'MATCH_WITHDRAWAL_DEADLINE_PASSED';end if;
 if old.user_id=m.host_id and m.payment_mode='host_pays_all' and m.checkout_order_id is not null then raise exception 'HOST_PAYS_ALL_WITHDRAWAL_REQUIRES_POLICY_DECISION';end if;
 for oid in select id from checkout_orders where match_id=m.id and user_id=old.user_id and entitlement_revoked_at is null order by id loop
  update checkout_orders set entitlement_revoked_at=clock_timestamp(),cancellation_requested_at=clock_timestamp(),
   cancellation_requested_by=auth.uid(),cancellation_policy_reason='MATCH_WITHDRAWAL_FULL_REFUND',
   fulfillment_status=case when payment_status in('paid','partially_refunded') then 'refund_required' else 'cancelled' end where id=oid;
  perform arena_private.require_policy_refund(oid,'Participant withdrawal before 90-minute decision: 100% electronic payment refund');
 end loop;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
create trigger phase3_policy_withdrawal before delete or update of status on public.match_players for each row execute function public.phase3_policy_withdrawal();

create or replace function public.leave_match(match_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;begin
 perform public.require_oman_user();
 perform arena_private.lock_match(leave_match.match_id);
 perform arena_private.decide_match(leave_match.match_id);
 select * into strict m from matches where id=leave_match.match_id;
 if m.decision_outcome='confirmed' then raise exception 'WITHDRAWAL_LOCKED_AFTER_CONFIRMATION';end if;
 if m.status='cancelled' then return;end if;
 if clock_timestamp()>=m.decision_at then raise exception 'MATCH_WITHDRAWAL_DEADLINE_PASSED';end if;
 delete from match_players where match_players.match_id=leave_match.match_id and user_id=auth.uid();
end $$;

create function public.admin_record_addon_delivery(p_addon uuid,p_delivered integer) returns void
language plpgsql security definer set search_path=public as $$
declare b booking_addons%rowtype;a uuid;begin
 if not public.is_platform_admin() then raise exception 'ADMIN_ONLY';end if;
 select o.arena_id into a from booking_addons x join checkout_orders o on o.id=x.order_id where x.id=p_addon;
 perform pg_advisory_xact_lock(hashtextextended(a::text,0));
 select * into strict b from booking_addons where id=p_addon for update;
 if not b.inventory_tracked or b.released_at is not null or b.kind<>'consumable' or p_delivered is null or p_delivered<coalesce(b.delivered_quantity,0) or p_delivered>b.quantity then raise exception 'INVALID_DELIVERY_RECORD';end if;
 update booking_addons set delivered_quantity=p_delivered,delivery_recorded_at=clock_timestamp(),delivery_recorded_by=auth.uid() where id=b.id;
end $$;

create function public.booking_cancellation_summary(p_booking uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare b bookings%rowtype;o checkout_orders%rowtype;begin
 select * into strict b from bookings where id=p_booking;
 if b.user_id is distinct from auth.uid() and not public.is_arena_operator(b.arena_id) then raise exception 'CANCELLATION_NOT_ALLOWED';end if;
 select * into o from checkout_orders where id=b.checkout_order_id;
 return jsonb_build_object('allowed',b.user_id=auth.uid() and b.booking_type<>'manual' and b.status<>'cancelled' and arena_private.booking_cancel_allowed(b.starts_at,clock_timestamp()),
  'deadline',b.starts_at-interval '150 minutes','server_now',clock_timestamp(),'status',b.status,
  'expected_refund_baisa',case when o.payment_method='card' and o.payment_status in('paid','partially_refunded') then o.amount_due_baisa-o.refunded_amount_baisa else 0 end,
  'order',to_jsonb(o),'refunds',coalesce((select jsonb_agg(to_jsonb(r)) from payment_refunds r where r.order_id=o.id),'[]'::jsonb),
  'addons',coalesce((select jsonb_agg(to_jsonb(x)) from booking_addons x where x.order_id=o.id),'[]'::jsonb));
end $$;
create function public.ordinary_order_cancellation_summary(p_order uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare o checkout_orders%rowtype;begin
 select * into strict o from checkout_orders where id=p_order;
 if o.user_id is distinct from auth.uid() or o.purpose<>'booking' then raise exception 'CANCELLATION_NOT_ALLOWED';end if;
 if o.booking_id is not null then return public.booking_cancellation_summary(o.booking_id);end if;
 return jsonb_build_object('allowed',o.cancellation_requested_at is null and arena_private.booking_cancel_allowed(o.starts_at,clock_timestamp()),'status',case when o.cancellation_requested_at is not null then 'cancelled' else 'pending' end,
 'expected_refund_baisa',case when o.payment_status in('paid','partially_refunded') then o.amount_due_baisa-o.refunded_amount_baisa else 0 end,
 'refunds',coalesce((select jsonb_agg(to_jsonb(r)) from payment_refunds r where r.order_id=o.id),'[]'::jsonb));
end $$;
create or replace function public.cancel_unstarted_checkout(p_order uuid) returns void
language plpgsql security definer set search_path=public as $$
declare o checkout_orders%rowtype;begin
 select * into strict o from checkout_orders where id=p_order;
 if o.user_id is distinct from auth.uid() then raise exception 'CANCELLATION_NOT_ALLOWED';end if;
 if o.purpose='booking' then perform public.cancel_pending_booking_checkout(p_order);return;end if;
 update checkout_orders set fulfillment_status='cancelled',payment_status='cancelled',updated_at=now()
 where id=p_order and user_id=auth.uid() and payment_method='card' and provider_creation_state='not_started' and payment_status='pending';
 if not found then raise exception 'PROVIDER_CANCELLATION_REQUIRED';end if;
end $$;
create function public.my_match_withdrawal_summary(p_match uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;host_blocked boolean;begin
 select * into strict m from matches where id=p_match;
 if auth.uid() is null or not public.can_view_match(p_match,auth.uid()) then raise exception 'NOT_AUTHORIZED';end if;
 host_blocked:=m.host_id=auth.uid() and m.payment_mode='host_pays_all' and m.checkout_order_id is not null;
 return jsonb_build_object('allowed',not coalesce(host_blocked,false) and m.decision_outcome='pending' and clock_timestamp()<m.decision_at and exists(select 1 from match_players where match_id=m.id and user_id=auth.uid() and status='joined'),
 'host_policy_required',host_blocked,'expected_refund_baisa',(select coalesce(sum(amount_due_baisa-refunded_amount_baisa),0) from checkout_orders where match_id=m.id and user_id=auth.uid() and payment_method='card' and payment_status in('paid','partially_refunded') and entitlement_revoked_at is null));
end $$;
revoke all on function public.ordinary_order_cancellation_summary(uuid),public.my_match_withdrawal_summary(uuid) from public,anon,authenticated;
grant execute on function public.ordinary_order_cancellation_summary(uuid),public.my_match_withdrawal_summary(uuid) to authenticated;
revoke all on function arena_private.booking_cancel_allowed(timestamptz,timestamptz),arena_private.require_policy_refund(uuid,text),arena_private.release_policy_addons(uuid),public.phase3_policy_booking_guard(),public.phase3_policy_booking_cancel(),public.phase3_policy_order_lifecycle(),public.phase3_policy_match_addons(),public.phase3_policy_withdrawal(),public.admin_record_addon_delivery(uuid,integer),public.cancel_pending_booking_checkout(uuid),public.booking_cancellation_summary(uuid) from public,anon,authenticated;
grant execute on function public.cancel_pending_booking_checkout(uuid),public.booking_cancellation_summary(uuid),public.admin_record_addon_delivery(uuid,integer) to authenticated;
commit;
