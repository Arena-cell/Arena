-- PHASE 1 / 3. Complete RPC authorization and legacy compatibility.
begin;
create or replace function public.join_match(match_id uuid,target_user_id uuid default auth.uid())
returns void language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;v_status text;v_user uuid:=public.require_oman_user();begin
  if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
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
  update match_players set status=case when p_accept then 'joined' else 'rejected' end,joined_at=now()
    where match_id=p_match_id and user_id=p_user_id and status='requested';
  if not found then raise exception 'JOIN_REQUEST_NOT_FOUND';end if;
end $$;
create or replace function public.leave_match(match_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.require_oman_user();
  perform 1 from matches where id=leave_match.match_id for update;
  delete from match_players where match_players.match_id=leave_match.match_id and user_id=auth.uid();
end $$;

-- Inventory-aware reduction, including maintenance blocks and migration issues.
create or replace function public.sync_arena_courts_from_count()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(new.id::text,0));
  if tg_op='UPDATE' and new.court_count<old.court_count and (
    exists(select 1 from court_reservations r join arena_courts c on c.id=r.court_id
      where c.arena_id=new.id and c.court_number>new.court_count and r.ends_at>now())
    or exists(select 1 from inventory_migration_issues where arena_id=new.id and resolved_at is null and ends_at>now())
  ) then raise exception 'COURT_COUNT_HAS_ACTIVE_BOOKINGS';end if;
  insert into arena_courts(arena_id,court_number,label_ar,label_en,is_active)
    select new.id,n,'الملعب رقم '||n,'Court '||n,true from generate_series(1,new.court_count) n
    on conflict(arena_id,court_number) do update set is_active=true;
  update arena_courts set is_active=false where arena_id=new.id and court_number>new.court_count;
  -- Legacy arena-wide maintenance also covers newly activated courts.
  update blocked_slots set court_id=null where arena_id=new.id and court_id is null
    and cancelled_at is null and ends_at>now();
  return new;
end $$;

create or replace function public.notify_booking_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_court_number integer;
begin
  if new.user_id is null then return new; end if;
  select court_number into v_court_number from public.arena_courts where id = new.court_id;
  if tg_op = 'INSERT' then
    insert into public.notifications(
      user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
    ) values (
      new.user_id, 'booking_confirmation', 'Booking confirmed', 'Your Arena booking is confirmed.',
      'تم تأكيد الحجز', 'Booking confirmed',
      'تم تأكيد حجزك في الملعب رقم ' || coalesce(v_court_number::text, '1') || '.',
      'Your booking is confirmed on Court ' || coalesce(v_court_number::text, '1') || '.',
      jsonb_build_object('booking_id', new.id, 'arena_id', new.arena_id, 'court_number', v_court_number),
      'booking-confirmed:' || new.id::text
    ) on conflict (user_id, event_key) where event_key is not null do nothing;
  elsif new.status is distinct from old.status then
    insert into public.notifications(
      user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
    ) values (
      new.user_id,
      case when new.status = 'cancelled' then 'booking_cancellation' else 'booking_status' end,
      case when new.status = 'cancelled' then 'Booking cancelled' else 'Booking status updated' end,
      case when new.status = 'cancelled' then 'Your Arena booking was cancelled.' else 'Your Arena booking status changed.' end,
      case when new.status = 'cancelled' then 'تم إلغاء الحجز' else 'تم تحديث حالة الحجز' end,
      case when new.status = 'cancelled' then 'Booking cancelled' else 'Booking status updated' end,
      case when new.status = 'cancelled' then 'تم إلغاء حجزك.' else 'تغيرت حالة حجزك.' end,
      case when new.status = 'cancelled' then 'Your Arena booking was cancelled.' else 'Your Arena booking status changed.' end,
      jsonb_build_object('booking_id', new.id, 'arena_id', new.arena_id, 'status', new.status),
      'booking-status:' || new.id::text || ':' || new.status
    ) on conflict (user_id, event_key) where event_key is not null do nothing;
  end if;
  return new;
end;
$$;
create or replace function public.award_completed_booking_points()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_balance integer; v_coupon_id uuid;
begin
  if new.user_id is null then return new; end if;
  if new.status = 'previous' and old.status is distinct from 'previous' then
    insert into public.point_transactions(user_id, booking_id, points, reason)
    values (new.user_id, new.id, 10, 'completed_booking')
    on conflict (booking_id) where booking_id is not null and reason = 'completed_booking'
    do nothing;

    select coalesce(sum(points), 0) into v_balance
    from public.point_transactions where user_id = new.user_id;
    while v_balance >= 100 loop
      insert into public.reward_coupons(user_id) values (new.user_id)
      returning id into v_coupon_id;
      insert into public.point_transactions(user_id, booking_id, points, reason)
      values (new.user_id, new.id, -100, 'coupon_created:' || v_coupon_id::text);
      v_balance := v_balance - 100;
    end loop;
  end if;
  return new;
end;
$$;

-- Remove default PUBLIC execute from every exposed definer/invoker function.
-- Existing app RPCs and policy helpers are explicitly allowlisted below.
do $$ declare r record;begin
  for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f'
      and not exists(select 1 from pg_depend d where d.objid=p.oid and d.deptype='e') loop
    execute format('revoke all on function %s from public,anon,authenticated',r.signature);
  end loop;
  for r in select p.oid::regprocedure signature,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=any(array[
      'is_platform_admin_user','is_platform_admin','is_stadium_owner_of','is_arena_operator',
      'can_view_match','can_view_match_players','can_view_match_player_row','is_chat_group_member',
      'my_staff_access','my_profile_complete','complete_my_profile','arena_availability','arena_busy_intervals',
      'arena_has_available_court','create_arena_booking','create_arena_booking_with_coupon','create_arena_match',
      'owner_reserve','owner_create_manual_booking','owner_block_slot','owner_cancel_booking','owner_cancel_block',
      'cancel_arena_booking','resolve_inventory_issue','join_match','request_match_join','respond_match_join_request',
      'leave_match','create_booking_review','moderate_arena_review','finalize_my_completed_events',
      'nearby_arenas','create_group_chat','consume_arena_assistant_rate_limit'
    ]) loop execute format('grant execute on function %s to authenticated',r.signature);end loop;
  for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=any(array['is_platform_admin_user','is_platform_admin','is_stadium_owner_of',
      'is_arena_operator','can_view_match','can_view_match_players','can_view_match_player_row',
      'arena_availability','arena_busy_intervals','arena_has_available_court']) loop
    execute format('grant execute on function %s to anon',r.signature);
  end loop;
end $$;
grant execute on function public.before_user_created_oman(jsonb) to supabase_auth_admin;
commit;
