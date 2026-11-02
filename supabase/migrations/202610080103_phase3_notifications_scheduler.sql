-- Extend existing notification and delivery infrastructure; no parallel inbox.
begin;
alter table public.notifications add column due_at timestamptz not null default now();
alter table public.notifications add column processed_at timestamptz not null default now();
alter table public.notifications add column attempt_count integer not null default 0;
alter table public.notifications add column next_attempt_at timestamptz not null default now();
alter table public.notifications add column delivery_status text not null default 'pending'
 check(delivery_status in('pending','sending','sent','failed','no_device','exhausted'));
-- Never replay historical notifications as new push messages.
update public.notifications set delivery_status='sent';
alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check check(type in(
 'match_invitation','booking_confirmation','booking_cancellation','booking_status','booking_reminder',
 'match_reminder','player_joined','players_complete','join_request','join_accepted','join_rejected',
 'message','points','coupons','stadium_update','match_created','match_confirmed','match_cancelled',
 'participation_updated','payment_confirmed','payment_failed','refund_pending','refund_completed'));
revoke insert,delete,update on public.notifications from anon,authenticated;
grant update(read_at) on public.notifications to authenticated;
create policy "users mark own notifications read" on public.notifications for update to authenticated
 using(user_id=auth.uid()) with check(user_id=auth.uid());
create index phase3_notification_due on notifications(next_attempt_at) where delivery_status in('pending','failed');

create function arena_private.notify(p_user uuid,p_type text,p_key text,p_data jsonb,p_en text,p_ar text)
returns void language sql set search_path=public as $$
 insert into notifications(user_id,type,event_key,data,title,body,title_en,body_en,title_ar,body_ar)
 select p_user,p_type,p_key,p_data,'Arena',p_en,'Arena',p_en,'أرينا',p_ar where p_user is not null
 on conflict(user_id,event_key) where event_key is not null do nothing;
$$;
create function public.phase3_match_notification() returns trigger
language plpgsql security definer set search_path=public as $$
declare u uuid;t text;begin
 if tg_op='INSERT' then
  perform arena_private.notify(new.host_id,'match_created','match-created:'||new.id,
   jsonb_build_object('match_id',new.id),'Your match has been created.','تم إنشاء مباراتك.');
 elsif new.decision_outcome is distinct from old.decision_outcome and new.decision_outcome in('confirmed','cancelled') then
  t:='match_'||new.decision_outcome;
  for u in select new.host_id union select user_id from match_players where match_id=new.id loop
   perform arena_private.notify(u,t,'match-decision:'||new.id,jsonb_build_object('match_id',new.id),
    case when t='match_confirmed' then 'Match confirmed. Withdrawal is now locked.' else 'Match cancelled: minimum participation was not reached. Any required refund is pending provider processing.' end,
    case when t='match_confirmed' then 'تأكدت المباراة. لا يمكن الانسحاب الآن.' else 'أُلغيت المباراة لعدم اكتمال العدد المطلوب. أي استرداد مستحق ينتظر معالجة مزود الدفع.' end);
  end loop;
 end if;return new;
end $$;
create trigger phase3_match_notification after insert or update on matches
 for each row execute function phase3_match_notification();

create function public.phase3_payment_notification() returns trigger
language plpgsql security definer set search_path=public as $$
declare t text;u uuid;oid uuid;d jsonb;begin
 if tg_table_name='checkout_orders' then
  if new.payment_status is not distinct from old.payment_status then return new;end if;
  t:=case new.payment_status when 'paid' then 'payment_confirmed' when 'failed' then 'payment_failed' end;
  if t is null then return new;end if;
  perform arena_private.notify(new.user_id,t,t||':'||new.id,jsonb_build_object('order_id',new.id,'match_id',new.match_id,'booking_id',new.booking_id),
   case when t='payment_confirmed' then 'Payment verified. Open Arena to view your reservation status.' else 'Payment failure verified. Open Arena to review the request.' end,
   case when t='payment_confirmed' then 'تم التحقق من الدفع. افتح أرينا لمعرفة حالة الحجز.' else 'تم التحقق من فشل الدفع. افتح أرينا لمراجعة الطلب.' end);
 else
  oid:=new.order_id;select user_id into u from checkout_orders where id=oid;
  d:=jsonb_build_object('order_id',oid);
  if tg_op='INSERT' then
   perform arena_private.notify(u,'refund_pending','refund-request:'||new.id,d,
    'Refund requested. It has not been completed yet.','تم طلب الاسترداد ولم يكتمل بعد.');
  elsif new.status='succeeded' and old.status<>'succeeded' then
   perform arena_private.notify(u,'refund_completed','refund-completed:'||new.id,d,
    'The payment provider confirmed your refund.','أكد مزود الدفع اكتمال الاسترداد.');
  end if;
 end if;return new;
end $$;
create trigger phase3_payment_notification after update on checkout_orders for each row execute function phase3_payment_notification();
create trigger phase3_refund_notification after insert or update on payment_refunds for each row execute function phase3_payment_notification();

create function public.phase3_membership_notification() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if tg_op='DELETE' then
  perform arena_private.notify(old.user_id,'participation_updated','participation-left:'||old.match_id||':'||old.user_id||':'||old.joined_at,
   jsonb_build_object('match_id',old.match_id),'You left the match. Any existing payment remains recorded.','غادرت المباراة. يظل أي دفع سابق محفوظاً في السجل.');
  return old;
 end if;
 if old.status='requested' and new.status='invited' then
  perform arena_private.notify(new.user_id,'join_accepted','join-accepted:'||new.match_id||':'||new.user_id,
   jsonb_build_object('match_id',new.match_id),'Request accepted. Complete the required payment to confirm your seat.','تم قبول الطلب. أكمل الدفع المطلوب لتأكيد مقعدك.');
 end if;return new;
end $$;
create trigger phase3_membership_notification after update or delete on match_players for each row execute function phase3_membership_notification();

-- Catch up due reminders after outages, without a 10-minute selection window.
create or replace function public.enqueue_due_event_reminders() returns integer
language plpgsql security definer set search_path=public as $$
declare r record;n integer:=0;before_count bigint;begin
 select count(*) into before_count from notifications;
 for r in select id,arena_id,user_id,starts_at from bookings where user_id is not null
  and status not in('cancelled','completed','previous') and starts_at-interval '60 minutes'<=clock_timestamp() and ends_at>clock_timestamp() loop
  perform arena_private.notify(r.user_id,'booking_reminder','booking-reminder:'||r.id,
   jsonb_build_object('booking_id',r.id,'arena_id',r.arena_id),'Booking reminder. Check the start time in Arena.','تذكير بالحجز. تحقق من موعد البداية في أرينا.');
  update notifications set due_at=r.starts_at-interval '60 minutes' where user_id=r.user_id and event_key='booking-reminder:'||r.id;
 end loop;
 for r in select m.id,m.arena_id,mp.user_id,m.starts_at from matches m join match_players mp on mp.match_id=m.id and mp.status='joined'
  where m.status<>'cancelled' and m.decision_outcome='confirmed' and m.starts_at-interval '60 minutes'<=clock_timestamp() and m.ends_at>clock_timestamp() loop
  perform arena_private.notify(r.user_id,'match_reminder','match-reminder:'||r.id||':'||r.user_id,
   jsonb_build_object('match_id',r.id,'arena_id',r.arena_id),'Match reminder. Check the start time in Arena.','تذكير بالمباراة. تحقق من موعد البداية في أرينا.');
  update notifications set due_at=r.starts_at-interval '60 minutes' where user_id=r.user_id and event_key='match-reminder:'||r.id||':'||r.user_id;
 end loop;
 select count(*)-before_count into n from notifications;return n;
end $$;

create table public.arena_scheduled_job_runs(
 id uuid primary key default gen_random_uuid(),started_at timestamptz not null default clock_timestamp(),
 processed_at timestamptz,outcome text not null check(outcome in('running','succeeded','failed')),
 decision_count integer not null default 0,reminder_count integer not null default 0,last_error text);
alter table public.arena_scheduled_job_runs enable row level security;
create policy "admin scheduled job visibility" on public.arena_scheduled_job_runs for select to authenticated using(public.is_platform_admin());
revoke all on public.arena_scheduled_job_runs from public,anon,authenticated;
grant select on public.arena_scheduled_job_runs to authenticated;
create function public.process_arena_scheduled_events() returns jsonb
language plpgsql security definer set search_path=public as $$
declare r record;j uuid;d integer:=0;n integer:=0;err text;begin
 if not pg_try_advisory_xact_lock(hashtextextended('arena-phase3-scheduler',0)) then return jsonb_build_object('busy',true);end if;
 insert into arena_scheduled_job_runs(outcome) values('running') returning id into j;
 begin
  for r in select id from matches where decision_outcome='pending' and status<>'cancelled'
   and decision_at<=clock_timestamp() order by decision_at,id loop
   if arena_private.decide_match(r.id)<>'pending' then d:=d+1;end if;
  end loop;
  n:=enqueue_due_event_reminders();
  update arena_scheduled_job_runs set outcome='succeeded',processed_at=clock_timestamp(),decision_count=d,reminder_count=n where id=j;
 exception when others then
  get stacked diagnostics err=message_text;
  update arena_scheduled_job_runs set outcome='failed',processed_at=clock_timestamp(),last_error=left(err,200) where id=j;
  return jsonb_build_object('job_id',j,'failed',true);
 end;
 -- Bound routine idle logs; failures remain available for investigation.
 delete from arena_scheduled_job_runs where outcome='succeeded' and started_at<now()-interval '7 days';
 return jsonb_build_object('job_id',j,'decisions',d,'reminders',n);
end $$;
create function public.admin_retry_arena_scheduler() returns jsonb
language plpgsql security definer set search_path=public as $$ begin
 if not public.is_platform_admin() then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 return public.process_arena_scheduled_events();
end $$;

revoke all on function arena_private.notify(uuid,text,text,jsonb,text,text),public.phase3_match_notification(),public.phase3_payment_notification(),
 public.phase3_membership_notification(),public.process_arena_scheduled_events(),public.admin_retry_arena_scheduler(),public.enqueue_due_event_reminders() from public,anon,authenticated;
grant execute on function public.process_arena_scheduled_events(),public.enqueue_due_event_reminders() to service_role;
grant execute on function public.admin_retry_arena_scheduler() to authenticated;
commit;
