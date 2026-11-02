begin;
-- Sessionless requests can be cancelled without touching a payment provider.
-- Once creation has been attempted, only verified provider state may cancel it.
create function public.cancel_unstarted_checkout(p_order uuid)
returns void language plpgsql security definer set search_path=public as $$ begin
 update checkout_orders set fulfillment_status='cancelled',payment_status='cancelled',updated_at=now()
 where id=p_order and user_id=auth.uid() and payment_method='card' and provider_creation_state='not_started' and payment_status='pending';
 if not found then raise exception 'PROVIDER_CANCELLATION_REQUIRED';end if;
end $$;
create function public.flag_cancelled_payment()
returns trigger language plpgsql security definer set search_path=public as $$ begin
 if new.status='cancelled' and old.status<>'cancelled' and new.checkout_order_id is not null then
  update checkout_orders set fulfillment_status=case when payment_status in('paid','partially_refunded') then 'refund_required' else 'cancelled' end,
   failure_code='RESERVATION_CANCELLED',updated_at=now()
  where id=new.checkout_order_id or (tg_table_name='matches' and match_id=new.id and purpose='participant');
 end if;return new;
end $$;
create trigger phase2_booking_cancel after update of status on bookings for each row execute function public.flag_cancelled_payment();
create trigger phase2_match_cancel after update of status on matches for each row execute function public.flag_cancelled_payment();

create or replace function public.respond_match_join_request(p_match_id uuid,p_user_id uuid,p_accept boolean)
returns void language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;begin
 perform public.require_oman_user();
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
revoke all on function public.cancel_unstarted_checkout(uuid),public.flag_cancelled_payment() from public,anon,authenticated;
grant execute on function public.cancel_unstarted_checkout(uuid) to authenticated;
grant select on public.checkout_orders,public.payment_refunds to service_role;
commit;
