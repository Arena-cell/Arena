begin;
create function public.payment_claim_session(p_order uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o checkout_orders%rowtype;begin
 select * into strict o from checkout_orders where id=p_order for update;
 if o.payment_method<>'card' or o.fulfillment_status<>'pending' then raise exception 'ORDER_NOT_PAYABLE';end if;
 if o.provider_creation_state='not_started' then
  update checkout_orders set provider_creation_state='creating',provider_attempted_at=now(),updated_at=now() where id=o.id;
  return to_jsonb(o)||jsonb_build_object('create_allowed',true);
 end if;
 return to_jsonb(o)||jsonb_build_object('create_allowed',false);
end $$;

create function public.payment_reconcile(p_order uuid,p_session text,p_reference text,p_currency text,p_amount bigint,p_status text,p_invoice text,p_event_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o checkout_orders%rowtype;err text;begin
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

create function public.request_payment_refund(p_order uuid,p_amount_baisa bigint,p_reason text,p_request_key uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare o checkout_orders%rowtype;r payment_refunds%rowtype;reserved bigint;begin
 if not public.is_platform_admin() then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
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

create function public.payment_confirm_refund(p_refund uuid,p_reference text,p_amount bigint,p_succeeded boolean)
returns void language plpgsql security definer set search_path=public as $$
declare r payment_refunds%rowtype;total bigint;begin
 select * into strict r from payment_refunds where id=p_refund;
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

create function public.create_participant_checkout(p_match uuid,p_request_key uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u uuid:=public.require_oman_user();m matches%rowtype;host_order checkout_orders%rowtype;o checkout_orders%rowtype;seat integer;prior jsonb;begin
 if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
 prior:=arena_private.begin_request(p_request_key,'participant',jsonb_build_object('match_id',p_match));
 select * into strict m from matches where id=p_match for update;
 if m.status='cancelled' or m.starts_at<=now() then raise exception 'MATCH_UNAVAILABLE';end if;
 if m.checkout_order_id is null then raise exception 'LEGACY_MATCH_USE_JOIN';end if;
 if not exists(select 1 from profiles where id=u and gender=m.gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
 if m.is_private and m.host_id<>u and not exists(select 1 from match_players where match_id=m.id and user_id=u and status in('invited','joined')) then raise exception 'INVITATION_REQUIRED';end if;
 select * into strict host_order from checkout_orders where id=m.checkout_order_id;
 if host_order.payment_status<>'paid' or host_order.fulfillment_status<>'fulfilled' then raise exception 'HOST_PAYMENT_REQUIRED';end if;
 select * into o from checkout_orders where match_id=m.id and user_id=u and fulfillment_status<>'cancelled';
 if found then return to_jsonb(o);end if;
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

-- Preserve historical matches, but require a server-verified financial entitlement
-- for all new financial matches, including legacy invite/accept RPCs.
create function public.enforce_match_payment_entitlement()
returns trigger language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;begin
 select * into strict m from matches where id=new.match_id;
 if m.checkout_order_id is null or new.status<>'joined' then return new;end if;
 if m.payment_mode='host_pays_all' and exists(select 1 from checkout_orders where id=m.checkout_order_id and payment_status='paid' and amount_due_baisa=m.total_amount_baisa) then
  new.covered_by_host:=true;return new;
 end if;
 if not exists(select 1 from checkout_orders where id=new.payment_order_id and user_id=new.user_id and payment_status='paid' and (match_id=m.id or id=m.checkout_order_id)) then raise exception 'PARTICIPANT_PAYMENT_REQUIRED';end if;
 new.covered_by_host:=false;return new;
end $$;
create trigger phase2_match_payment before insert or update on public.match_players for each row execute function public.enforce_match_payment_entitlement();

-- Old clients cannot create unpaid public matches or bypass the add-on catalog.
create or replace function public.create_arena_match(p_arena_id uuid,p_name text,p_description text,p_rules text,p_sport text,p_starts_at timestamptz,p_ends_at timestamptz,p_max_players integer,p_is_private boolean,p_show_joined_players boolean,p_payment_method text,p_idempotency_key uuid)
returns table(match_id uuid,court_id uuid,court_number integer) language plpgsql security definer set search_path=public as $$ begin raise exception 'CARD_CHECKOUT_REQUIRED';end $$;
create or replace function public.create_arena_booking_with_coupon(p_arena_id uuid,p_starts_at timestamptz,p_ends_at timestamptz,p_water_cartons integer,p_idempotency_key uuid,p_coupon_id uuid default null)
returns table(booking_id uuid,court_id uuid,court_number integer,total_price numeric,discount_amount numeric)
language plpgsql security definer set search_path=public as $$
declare addons jsonb:='[]';a uuid;o jsonb;b bookings%rowtype;begin
 if p_water_cartons is null or p_water_cartons<0 then raise exception 'INVALID_WATER_QUANTITY';end if;
 if p_water_cartons>0 then
  select id into a from arena_addons where arena_id=p_arena_id and addon_code='water' and enabled;
  if a is null then raise exception 'ADDON_UNAVAILABLE';end if;
  addons:=jsonb_build_array(jsonb_build_object('id',a,'quantity',p_water_cartons));
 end if;
 -- Retry of an existing Phase 1 request must still return its original result.
 select * into b from bookings where user_id=auth.uid() and idempotency_key=p_idempotency_key;
 if found then
  if (b.arena_id,b.starts_at,b.ends_at,b.coupon_id) is distinct from (p_arena_id,p_starts_at,p_ends_at,p_coupon_id) then raise exception 'IDEMPOTENCY_PAYLOAD_MISMATCH';end if;
 else
  o:=public.create_checkout(jsonb_build_object('purpose','booking','payment_method','cash','arena_id',p_arena_id,'starts_at',p_starts_at,'ends_at',p_ends_at,'addons',addons,'coupon_id',p_coupon_id),p_idempotency_key);
  select * into strict b from bookings where id=(o->>'booking_id')::uuid;
 end if;
 return query select b.id,b.court_id,c.court_number,b.total_price,b.discount_amount from arena_courts c where c.id=b.court_id;
end $$;

revoke all on function public.payment_claim_session(uuid),public.payment_reconcile(uuid,text,text,text,bigint,text,text,text),public.payment_confirm_refund(uuid,text,bigint,boolean),public.enforce_match_payment_entitlement(),public.request_payment_refund(uuid,bigint,text,uuid),public.create_participant_checkout(uuid,uuid) from public,anon,authenticated;
grant execute on function public.payment_claim_session(uuid),public.payment_reconcile(uuid,text,text,text,bigint,text,text,text),public.payment_confirm_refund(uuid,text,bigint,boolean) to service_role;
grant execute on function public.request_payment_refund(uuid,bigint,text,uuid),public.create_participant_checkout(uuid,uuid) to authenticated;
commit;
