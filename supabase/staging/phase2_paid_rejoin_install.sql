-- Staging gtcrijikfaglqcwqozel only
begin;
-- Preserve paid entitlements after leaving/rejoining; never charge twice.

create or replace function public.create_participant_checkout(p_match uuid,p_request_key uuid)
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

create or replace function public.enforce_match_payment_entitlement()
returns trigger language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;begin
 select * into strict m from matches where id=new.match_id;
 if m.checkout_order_id is null or new.status<>'joined' then return new;end if;
 if m.payment_mode='host_pays_all' and exists(select 1 from checkout_orders where id=m.checkout_order_id and payment_status='paid' and amount_due_baisa=m.total_amount_baisa) then
  new.covered_by_host:=true;return new;
 end if;
 if new.payment_order_id is null then
  select id into new.payment_order_id from checkout_orders where match_id=m.id and user_id=new.user_id and payment_status='paid' and fulfillment_status='fulfilled' order by created_at limit 1;
 end if;
 if not exists(select 1 from checkout_orders where id=new.payment_order_id and user_id=new.user_id and payment_status='paid' and (match_id=m.id or id=m.checkout_order_id)) then raise exception 'PARTICIPANT_PAYMENT_REQUIRED';end if;
 new.covered_by_host:=false;return new;
end $$;

insert into arena_private.staging_installation(version,source_sha256) values('202610050001','f9b25a0db9242377a9cbb2505949e2666075ef45228246e0f3bf10c9201d01b1');
commit;
select version from arena_private.staging_installation where version='202610050001';