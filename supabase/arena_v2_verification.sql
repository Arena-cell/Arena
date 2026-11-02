-- Transactional verification for Arena v2. This script intentionally ends in
-- ROLLBACK, so it never keeps test users, arenas, bookings, matches, or notices.
-- Run only after arena_v2_booking_system.sql on a disposable branch or SQL
-- Editor session with postgres privileges.

begin;

do $$
declare
  v_arena constant uuid := '00000000-0000-0000-0000-00000000a001';
  v_users constant uuid[] := array[
    '00000000-0000-0000-0000-000000000101'::uuid,
    '00000000-0000-0000-0000-000000000102'::uuid,
    '00000000-0000-0000-0000-000000000103'::uuid,
    '00000000-0000-0000-0000-000000000104'::uuid,
    '00000000-0000-0000-0000-000000000105'::uuid,
    '00000000-0000-0000-0000-000000000106'::uuid
  ];
  v_start timestamptz := date_trunc('day', now() + interval '40 days') + interval '10 hours';
  v_court integer;
  v_booking uuid;
  v_public_match uuid;
  v_total numeric;
  v_count integer;
  v_index integer;
  v_failed boolean;
  v_coupon uuid;
begin
  for v_index in 1..array_length(v_users, 1) loop
    insert into auth.users(
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) values (
      v_users[v_index], 'authenticated', 'authenticated',
      'arena-v2-' || v_index || '@invalid.example', '', now(),
      '{"provider":"phone","providers":["phone"]}'::jsonb,
      jsonb_build_object(
        'username', 'arena_test_' || v_index,
        'first_name', 'Arena', 'last_name', 'Test',
        'gender', case when v_index = 6 then 'women' else 'men' end
      ), now(), now()
    );
    update public.profiles
    set gender = case when v_index = 6 then 'women' else 'men' end,
        onboarding_complete = true
    where id = v_users[v_index];
  end loop;

  insert into public.arenas(
    id, owner_id, name, description, location, sports, audience_gender,
    price_per_hour, rating, opening_time, closing_time, court_count, is_active
  ) values (
    v_arena, v_users[1], 'Arena v2 rollback test', 'Transactional test',
    'Muscat', array['football'], 'men', 12.000, 0, '06:00', '23:59', 4, true
  );

  select count(*) into v_count from public.arena_courts
  where arena_id = v_arena and is_active and court_number between 1 and 4;
  if v_count <> 4 then raise exception 'TEST_FAILED: court_count did not create four units'; end if;

  if public.arena_accepts_time_range(
    v_arena,
    date_trunc('day', v_start) + interval '1 hour',
    date_trunc('day', v_start) + interval '2 hours'
  ) then
    raise exception 'TEST_FAILED: closed hours were reported as available';
  end if;

  -- Four allocations at the same interval must deterministically take 1..4.
  for v_index in 1..4 loop
    perform set_config('request.jwt.claim.sub', v_users[v_index]::text, true);
    select result.booking_id, result.court_number, result.total_price
      into v_booking, v_court, v_total
    from public.create_arena_booking(
      v_arena, v_start, v_start + interval '2 hours', 2, gen_random_uuid()
    ) result;
    if v_court <> v_index then
      raise exception 'TEST_FAILED: expected court %, received %', v_index, v_court;
    end if;
    if v_total <> 25.000 then
      raise exception 'TEST_FAILED: backend water/venue price was %', v_total;
    end if;
  end loop;

  -- A fifth request for the same full range must fail.
  perform set_config('request.jwt.claim.sub', v_users[5]::text, true);
  v_failed := false;
  begin
    perform * from public.create_arena_booking(
      v_arena, v_start, v_start + interval '2 hours', 0, gen_random_uuid()
    );
  exception when others then
    v_failed := sqlerrm like '%TIME_NO_LONGER_AVAILABLE%';
  end;
  if not v_failed then raise exception 'TEST_FAILED: fifth booking was not rejected'; end if;

  -- A unit with a future booking cannot be disabled by reducing court_count.
  v_failed := false;
  begin
    update public.arenas set court_count = 3 where id = v_arena;
  exception when others then
    v_failed := sqlerrm like '%COURT_COUNT_HAS_ACTIVE_BOOKINGS%';
  end;
  if not v_failed then raise exception 'TEST_FAILED: protected court reduction was allowed'; end if;

  -- The end boundary is open: 12:00 remains a new independent slot after a
  -- 10:00–12:00 booking. Cancelling court 1 returns it to availability.
  update public.bookings set status = 'cancelled'
  where id = (
    select b.id from public.bookings b
    join public.arena_courts c on c.id = b.court_id
    where b.arena_id = v_arena and b.starts_at = v_start and c.court_number = 1
  );
  perform set_config('request.jwt.claim.sub', v_users[5]::text, true);
  select result.court_number into v_court
  from public.create_arena_booking(
    v_arena, v_start + interval '2 hours', v_start + interval '3 hours',
    0, gen_random_uuid()
  ) result;
  if v_court <> 1 then raise exception 'TEST_FAILED: end slot incorrectly remained blocked'; end if;

  select result.court_number into v_court
  from public.create_arena_booking(
    v_arena, v_start, v_start + interval '2 hours', 0, gen_random_uuid()
  ) result;
  if v_court <> 1 then raise exception 'TEST_FAILED: cancellation did not restore court 1'; end if;

  -- Cross-gender booking remains blocked by the backend.
  perform set_config('request.jwt.claim.sub', v_users[6]::text, true);
  v_failed := false;
  begin
    perform * from public.create_arena_booking(
      v_arena, v_start + interval '6 hours', v_start + interval '7 hours',
      0, gen_random_uuid()
    );
  exception when others then
    v_failed := sqlerrm like '%GENDER_NOT_ALLOWED%';
  end;
  if not v_failed then raise exception 'TEST_FAILED: gender restriction was bypassed'; end if;

  -- Coupons are owned by one user and can be consumed only once.
  perform set_config('request.jwt.claim.sub', v_users[1]::text, true);
  insert into public.reward_coupons(user_id) values (v_users[1]) returning id into v_coupon;
  perform * from public.create_arena_booking_with_coupon(
    v_arena, v_start + interval '8 hours', v_start + interval '9 hours',
    0, gen_random_uuid(), v_coupon
  );
  v_failed := false;
  begin
    perform * from public.create_arena_booking_with_coupon(
      v_arena, v_start + interval '9 hours', v_start + interval '10 hours',
      0, gen_random_uuid(), v_coupon
    );
  exception when others then
    v_failed := sqlerrm like '%COUPON_NOT_AVAILABLE%';
  end;
  if not v_failed then raise exception 'TEST_FAILED: coupon was reused'; end if;

  -- A private match is invisible by direct id until the user is invited,
  -- requests access, joins, or owns it.
  insert into public.matches(
    arena_id, court_id, host_id, name, sport, starts_at, ends_at,
    max_players, price_per_player, is_private, gender, status
  ) values (
    v_arena,
    (select id from public.arena_courts where arena_id = v_arena and court_number = 1),
    v_users[1], 'Private rollback test', 'football',
    v_start + interval '1 day', v_start + interval '1 day 1 hour',
    8, 1.500, true, 'men', 'upcoming'
  ) returning id into v_booking;
  if public.can_view_match(v_booking, v_users[5]) then
    raise exception 'TEST_FAILED: direct private match access was allowed';
  end if;

  insert into public.matches(
    arena_id, court_id, host_id, name, sport, starts_at, ends_at,
    max_players, price_per_player, is_private, gender, status
  ) values (
    v_arena,
    (select id from public.arena_courts where arena_id = v_arena and court_number = 1),
    v_users[1], 'Public gender rollback test', 'football',
    v_start + interval '2 days', v_start + interval '2 days 1 hour',
    8, 1.500, false, 'men', 'upcoming'
  ) returning id into v_public_match;
  if public.can_view_match(v_public_match, v_users[6]) then
    raise exception 'TEST_FAILED: opposite gender direct access was allowed';
  end if;
  if not public.can_view_match(v_public_match, v_users[5]) then
    raise exception 'TEST_FAILED: eligible public match was hidden';
  end if;
  if not public.is_stadium_owner_of(v_arena, v_users[1]) or
     public.is_stadium_owner_of(v_arena, v_users[2]) then
    raise exception 'TEST_FAILED: stadium owner scope is incorrect';
  end if;

  -- Duplicate event keys result in one notification row only.
  insert into public.notifications(
    user_id, type, title, body, event_key
  ) values (
    v_users[1], 'points', 'Test', 'Test', 'arena-v2-duplicate-test'
  ) on conflict (user_id, event_key) where event_key is not null do nothing;
  insert into public.notifications(
    user_id, type, title, body, event_key
  ) values (
    v_users[1], 'points', 'Test', 'Test', 'arena-v2-duplicate-test'
  ) on conflict (user_id, event_key) where event_key is not null do nothing;
  select count(*) into v_count from public.notifications
  where user_id = v_users[1] and event_key = 'arena-v2-duplicate-test';
  if v_count <> 1 then raise exception 'TEST_FAILED: duplicate notification was stored'; end if;
end;
$$;

rollback;
