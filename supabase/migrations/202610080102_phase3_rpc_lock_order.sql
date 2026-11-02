-- Phase 3: retain Phase 1/2 contracts, enforce arena -> match -> order lock order.
begin;
create or replace function public.join_match(match_id uuid,target_user_id uuid default auth.uid())
returns void language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;v_status text;v_user uuid:=public.require_oman_user();begin
  if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
  perform arena_private.lock_match(join_match.match_id);
 perform arena_private.decide_match(join_match.match_id);
 select * into m from matches where id=join_match.match_id and status<>'cancelled' and starts_at>now() for update;
  if not found then raise exception 'MATCH_NOT_FOUND';end if;
  if target_user_id is null or (target_user_id<>v_user and m.host_id<>v_user) then raise exception 'HOST_ONLY_INVITE';end if;
  if not exists(select 1 from profiles where id=target_user_id and gender=m.gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
  select status into v_status from match_players where match_players.match_id=join_match.match_id and user_id=target_user_id;
  if v_status='joined' then return;end if;
  if target_user_id=v_user and m.is_private and m.host_id<>v_user and coalesce(v_status,'')<>'invited' then raise exception 'INVITATION_REQUIRED';end if;
  if (select count(*) from match_players where match_players.match_id=join_match.match_id and status='joined')>=m.max_players then raise exception 'MATCH_FULL';end if;
  insert into match_players(match_id,user_id,status) values(m.id,target_user_id,case when target_user_id=v_user then 'joined' else 'invited' end)
    on conflict on constraint match_players_pkey do update set status=excluded.status;
end $$;

create or replace function public.request_match_join(p_match_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;v_status text;v_user uuid:=public.require_oman_user();begin
  if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
  perform arena_private.lock_match(p_match_id);
 perform arena_private.decide_match(p_match_id);
 select * into m from matches where id=p_match_id and status<>'cancelled' and starts_at>now() for update;
  if not found then raise exception 'MATCH_NOT_FOUND';end if;
  select status into v_status from match_players where match_id=p_match_id and user_id=v_user;
  if v_status='joined' then return 'joined';end if;
  if not exists(select 1 from profiles where id=v_user and gender=m.gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
  if not m.is_private or m.host_id=v_user or v_status='invited' then
    perform public.join_match(p_match_id,v_user);return 'joined';
  end if;
  insert into match_players(match_id,user_id,status) values(p_match_id,v_user,'requested')
    on conflict on constraint match_players_pkey do update set status='requested';return 'requested';
end $$;

create or replace function public.leave_match(match_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.require_oman_user();
 perform arena_private.lock_match(leave_match.match_id);
 perform arena_private.decide_match(leave_match.match_id);
  perform 1 from matches where id=leave_match.match_id for update;
  delete from match_players where match_players.match_id=leave_match.match_id and user_id=auth.uid();
end $$;

create or replace function public.respond_match_join_request(p_match_id uuid,p_user_id uuid,p_accept boolean)
returns void language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;begin
 perform public.require_oman_user();
 perform arena_private.lock_match(p_match_id);
 perform arena_private.decide_match(p_match_id);
 select * into m from matches where id=p_match_id and status<>'cancelled' and starts_at>now() for update;
 if not found or m.host_id<>auth.uid() then raise exception 'HOST_ONLY';end if;
 if p_accept then
  if not exists(select 1 from profiles where id=p_user_id and gender=m.gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
  if (select count(*) from match_players where match_id=p_match_id and status='joined')>=m.max_players then raise exception 'MATCH_FULL';end if;
 end if;
 update match_players set status=case when not p_accept then 'rejected' when m.checkout_order_id is not null and m.payment_mode='pay_individually' then 'invited' else 'joined' end,joined_at=now()
 where match_id=p_match_id and user_id=p_user_id and status='requested';
 if not found then raise exception 'JOIN_REQUEST_NOT_FOUND';end if;
end $$;

create or replace function public.create_participant_checkout(p_match uuid,p_request_key uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid:=public.require_oman_user();m matches%rowtype;host_order checkout_orders%rowtype;o checkout_orders%rowtype;seat integer;prior jsonb;begin
 if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
 prior:=arena_private.begin_request(p_request_key,'participant',jsonb_build_object('match_id',p_match));
 perform arena_private.lock_match(p_match);
 perform arena_private.decide_match(p_match);
 select * into strict m from matches where id=p_match for update;
 if m.status='cancelled' or m.starts_at<=now() then raise exception 'MATCH_UNAVAILABLE';end if;
 if m.checkout_order_id is null then raise exception 'LEGACY_MATCH_USE_JOIN';end if;
 if not exists(select 1 from profiles where id=u and gender=m.gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
 if m.is_private and m.host_id<>u and not exists(select 1 from match_players where match_id=m.id and user_id=u and status in('invited','joined')) then raise exception 'INVITATION_REQUIRED';end if;
 select * into strict host_order from checkout_orders where id=m.checkout_order_id;
 if host_order.payment_status<>'paid' or host_order.fulfillment_status<>'fulfilled' then raise exception 'HOST_PAYMENT_REQUIRED';end if;
 select * into o from checkout_orders where match_id=m.id and user_id=u and fulfillment_status<>'cancelled';
 if found then
  if o.fulfillment_status='fulfilled' and o.payment_status='paid' then perform public.join_match(p_match,u);end if;
  return to_jsonb(o);
 end if;
 if m.payment_mode='host_pays_all' then
  if not exists(select 1 from match_players where match_id=m.id and user_id=u and status='joined') and (select count(*) from match_players where match_id=m.id and status='joined')>=m.max_players then raise exception 'MATCH_FULL';end if;
  insert into match_players(match_id,user_id,status,covered_by_host) values(m.id,u,'joined',true) on conflict on constraint match_players_pkey do update set status='joined',covered_by_host=true;
  return jsonb_build_object('covered_by_host',true,'fulfillment_status','fulfilled','match_id',m.id);
 end if;
 select s into seat from generate_series(1,m.max_players-1) s where not exists(select 1 from checkout_orders x where x.match_id=m.id and x.seat_index=s and x.fulfillment_status<>'cancelled') order by s limit 1;
 if seat is null then raise exception 'MATCH_FULL';end if;
 insert into checkout_orders(user_id,arena_id,request_key,request_payload,purpose,payment_method,payment_status,base_amount_baisa,total_amount_baisa,amount_due_baisa,starts_at,ends_at,payment_mode,seat_index,match_id)
 values(u,m.arena_id,p_request_key,jsonb_build_object('match_id',m.id),'participant','card','pending',host_order.base_amount_baisa,m.total_amount_baisa,arena_private.share_baisa(m.total_amount_baisa,m.max_players,seat),m.starts_at,m.ends_at,m.payment_mode,seat,m.id) returning * into o;
 if o.amount_due_baisa<100 then raise exception 'CARD_MINIMUM_100_BAISA';end if;
 update arena_private.requests set result=jsonb_build_object('id',o.id) where user_id=u and request_key=p_request_key;
 return to_jsonb(o);
end $$;

create or replace function public.payment_reconcile(p_order uuid,p_session text,p_reference text,p_currency text,p_amount bigint,p_status text,p_invoice text,p_event_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o checkout_orders%rowtype;err text;begin
 perform arena_private.lock_payment_match(p_order);
 select * into strict o from checkout_orders where id=p_order for update;
 if o.payment_method<>'card' or p_reference<>o.id::text or p_currency<>'OMR' or p_amount<>o.amount_due_baisa or nullif(p_session,'') is null or p_status not in('paid','unpaid','cancelled') or p_status is null then raise exception 'PROVIDER_VERIFICATION_MISMATCH';end if;
 if o.provider_session_id is not null and o.provider_session_id<>p_session then raise exception 'PROVIDER_SESSION_MISMATCH';end if;
 insert into arena_private.payment_events(event_key,order_id,verified_status) values(p_event_key,o.id,p_status) on conflict do nothing;
 update checkout_orders set provider_session_id=p_session,provider_invoice=p_invoice,provider_creation_state='ready',updated_at=now() where id=o.id;
 -- A stale unpaid/cancel event cannot reverse captured funds or refunds.
 if o.payment_status in('paid','refunded','partially_refunded') then
  select * into o from checkout_orders where id=o.id;return to_jsonb(o);
 end if;
 if p_status='paid' then
  update checkout_orders set payment_status='paid' where id=o.id;
  begin
   perform arena_private.fulfill_order(o.id);
  exception when others then
   get stacked diagnostics err=message_text;
   update checkout_orders set fulfillment_status='refund_required',failure_code=left(err,200) where id=o.id;
  end;
 elsif p_status='cancelled' then
  update checkout_orders set payment_status='cancelled',fulfillment_status='cancelled' where id=o.id;
 end if;
 select * into o from checkout_orders where id=o.id;return to_jsonb(o);
end $$;

create or replace function public.request_payment_refund(p_order uuid,p_amount_baisa bigint,p_reason text,p_request_key uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare o checkout_orders%rowtype;r payment_refunds%rowtype;reserved bigint;begin
 if not public.is_platform_admin() then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 perform arena_private.lock_payment_match(p_order);
 select * into strict o from checkout_orders where id=p_order for update;
 select * into r from payment_refunds where request_key=p_request_key;
 if found then
  if (r.order_id,r.amount_baisa,r.reason) is distinct from (p_order,p_amount_baisa,p_reason) then raise exception 'IDEMPOTENCY_PAYLOAD_MISMATCH';end if;
  return r.id;
 end if;
 if o.payment_method<>'card' or o.payment_status not in('paid','partially_refunded') then raise exception 'REFUND_NOT_ALLOWED';end if;
 select coalesce(sum(amount_baisa),0) into reserved from payment_refunds where order_id=o.id and status<>'failed';
 if p_amount_baisa is null or p_amount_baisa<=0 or reserved+p_amount_baisa>o.amount_due_baisa then raise exception 'REFUND_EXCEEDS_PAYMENT';end if;
 insert into payment_refunds(order_id,request_key,original_amount_baisa,amount_baisa,reason,requested_by) values(o.id,p_request_key,o.amount_due_baisa,p_amount_baisa,p_reason,auth.uid()) returning id into r.id;
 return r.id;
end $$;

create or replace function public.payment_confirm_refund(p_refund uuid,p_reference text,p_amount bigint,p_succeeded boolean)
returns void language plpgsql security definer set search_path=public as $$
declare r payment_refunds%rowtype;total bigint;begin
 select * into strict r from payment_refunds where id=p_refund;
 perform arena_private.lock_payment_match(r.order_id);
 perform 1 from checkout_orders where id=r.order_id for update;
 select * into strict r from payment_refunds where id=p_refund for update;
 if r.status='succeeded' then
  if r.provider_reference is distinct from p_reference or r.amount_baisa<>p_amount then raise exception 'REFUND_VERIFICATION_MISMATCH';end if;return;
 end if;
 if r.amount_baisa<>p_amount or nullif(p_reference,'') is null then raise exception 'REFUND_VERIFICATION_MISMATCH';end if;
 update payment_refunds set status=case when p_succeeded then 'succeeded' else 'failed' end,provider_reference=p_reference,updated_at=now() where id=r.id;
 select coalesce(sum(amount_baisa),0) into total from payment_refunds where order_id=r.order_id and status='succeeded';
 update checkout_orders set refunded_amount_baisa=total,payment_status=case when total=amount_due_baisa then 'refunded' when total>0 then 'partially_refunded' else payment_status end,updated_at=now() where id=r.order_id;
 update bookings b set payment_status=o.payment_status from checkout_orders o where o.id=r.order_id and b.id=o.booking_id;
end $$;
create or replace function public.finalize_my_completed_events()
returns void language plpgsql security definer set search_path=public as $$
declare r record;begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 update bookings set status='previous' where user_id=auth.uid() and status in('upcoming','current') and ends_at<=now();
 for r in select id from matches where host_id=auth.uid() and status in('upcoming','confirmed','current') and ends_at<=now() order by arena_id,id loop
  perform arena_private.lock_match(r.id);
  perform arena_private.decide_match(r.id);
  update matches set status='previous' where id=r.id and status<>'cancelled';
 end loop;
end $$;
commit;
