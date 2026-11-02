-- PHASE 1 / 2. One inventory for bookings, matches, manual bookings and blocks.
begin;
create extension if not exists btree_gist;
lock table public.arenas,public.arena_courts,public.bookings,public.matches in access exclusive mode;
create table if not exists public.blocked_slots(
  id uuid primary key default gen_random_uuid(),arena_id uuid not null references arenas(id),
  starts_at timestamptz not null,ends_at timestamptz not null check(ends_at>starts_at),
  reason text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now()
);
alter table blocked_slots add column if not exists court_id uuid references arena_courts(id);
alter table blocked_slots add column if not exists cancelled_at timestamptz;
lock table public.blocked_slots in access exclusive mode;
alter table bookings alter column user_id drop not null;
alter table bookings add column if not exists booking_type text not null default 'online';
alter table bookings add column if not exists customer_name text;
alter table bookings add column if not exists customer_phone text;
alter table bookings add column if not exists notes text;
alter table bookings drop constraint if exists bookings_status_check;
alter table bookings add constraint bookings_status_check check(status in('pending','confirmed','completed','upcoming','current','previous','cancelled'));
create table public.court_reservations(
  id uuid primary key default gen_random_uuid(),arena_id uuid not null references arenas(id),
  court_id uuid not null references arena_courts(id),source_type text not null check(source_type in('booking','match','block')),
  source_id uuid not null,starts_at timestamptz not null,ends_at timestamptz not null check(ends_at>starts_at),
  unique(source_type,source_id,court_id),
  constraint court_reservations_no_overlap exclude using gist(court_id with =,tstzrange(starts_at,ends_at,'[)') with &&)
);
create index court_reservations_arena_time_idx on court_reservations(arena_id,starts_at,ends_at);
create table public.inventory_migration_issues(
  source_type text not null,source_id uuid not null,arena_id uuid not null references arenas(id),
  starts_at timestamptz not null,ends_at timestamptz not null,reason text not null,
  created_at timestamptz not null default now(),resolved_at timestamptz,
  primary key(source_type,source_id)
);
create index inventory_issues_open_idx on inventory_migration_issues(arena_id,starts_at,ends_at) where resolved_at is null;
-- Unresolved legacy conflicts block the arena conservatively for ONLY their interval.
-- Operators must review them; no data is discarded and no extra courts are invented.
drop trigger if exists bookings_enforce_cross_inventory on bookings;
drop trigger if exists matches_enforce_cross_inventory on matches;
drop trigger if exists bookings_prevent_arena_time_conflict on bookings;
drop trigger if exists matches_prevent_arena_time_conflict on matches;
do $$ declare r record;c record;v_court uuid;v_ok boolean; begin
  for r in select 'booking'::text kind,id,arena_id,court_id,starts_at,ends_at from bookings where status<>'cancelled'
    union all select 'match',id,arena_id,court_id,starts_at,ends_at from matches where status<>'cancelled'
    order by starts_at,id loop
    select ac.id into v_court from arena_courts ac where ac.arena_id=r.arena_id
      and (ac.id=r.court_id or (r.court_id is null and ac.is_active))
      and not exists(select 1 from court_reservations x where x.court_id=ac.id and x.starts_at<r.ends_at and x.ends_at>r.starts_at)
      order by ac.court_number limit 1;
    if v_court is null then
      insert into inventory_migration_issues values(r.kind,r.id,r.arena_id,r.starts_at,r.ends_at,'NO_NON_OVERLAPPING_COURT',now(),null);
    else
      insert into court_reservations(arena_id,court_id,source_type,source_id,starts_at,ends_at)
        values(r.arena_id,v_court,r.kind,r.id,r.starts_at,r.ends_at);
      if r.kind='booking' then update bookings set court_id=v_court where id=r.id and court_id is null;
      else update matches set court_id=v_court where id=r.id and court_id is null; end if;
    end if;
  end loop;
  for r in select * from blocked_slots where cancelled_at is null order by starts_at,id loop
    v_ok:=false;
    begin
      for c in select id from arena_courts where arena_id=r.arena_id and ((r.court_id is null and is_active) or id=r.court_id) loop
        insert into court_reservations(arena_id,court_id,source_type,source_id,starts_at,ends_at)
          values(r.arena_id,c.id,'block',r.id,r.starts_at,r.ends_at);
        v_ok:=true;
      end loop;
      if not v_ok then raise exception 'NO_COURTS'; end if;
    exception when exclusion_violation or raise_exception then
      insert into inventory_migration_issues values('block',r.id,r.arena_id,r.starts_at,r.ends_at,'BLOCK_REQUIRES_REVIEW',now(),null);
    end;
  end loop;
end $$;

create or replace function public.arena_accepts_time_range(p_arena_id uuid,p_starts_at timestamptz,p_ends_at timestamptz)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare a arenas%rowtype;s timestamp:=p_starts_at at time zone 'Asia/Muscat';e timestamp:=p_ends_at at time zone 'Asia/Muscat';ws timestamp;we timestamp;
begin
  if p_starts_at is null or p_ends_at is null or p_ends_at<=p_starts_at or p_ends_at-p_starts_at>interval '12 hours' then return false; end if;
  select * into a from arenas where id=p_arena_id and is_active;
  if not found or a.opening_time is null or a.closing_time is null then return false; end if;
  if a.opening_time=a.closing_time then return true; end if;
  ws:=s::date+a.opening_time;we:=s::date+a.closing_time;
  if a.closing_time<a.opening_time then
    if s::time<a.closing_time then ws:=ws-interval '1 day';else we:=we+interval '1 day';end if;
  end if;
  return s>=ws and e<=we;
end $$;

create or replace function public.arena_has_available_court(p_arena_id uuid,p_starts_at timestamptz,p_ends_at timestamptz)
returns boolean language sql stable security definer set search_path=public as $$
  select p_starts_at>now() and public.arena_accepts_time_range(p_arena_id,p_starts_at,p_ends_at)
    and not exists(select 1 from inventory_migration_issues i where i.arena_id=p_arena_id and i.resolved_at is null and i.starts_at<p_ends_at and i.ends_at>p_starts_at)
    and exists(select 1 from arena_courts c where c.arena_id=p_arena_id and c.is_active
      and not exists(select 1 from court_reservations r where r.court_id=c.id and r.starts_at<p_ends_at and r.ends_at>p_starts_at));
$$;

create function public.arena_availability(p_arena_id uuid,p_from date,p_to date)
returns table(starts_at timestamptz,ends_at timestamptz,available boolean)
language plpgsql stable security definer set search_path=public as $$
begin
  if p_to<=p_from or p_to-p_from>32 then raise exception 'INVALID_AVAILABILITY_WINDOW';end if;
  return query select s,s+interval '30 minutes',public.arena_has_available_court(p_arena_id,s,s+interval '30 minutes')
    from generate_series(p_from::timestamp at time zone 'Asia/Muscat',p_to::timestamp at time zone 'Asia/Muscat'-interval '30 minutes',interval '30 minutes') s;
end $$;
-- Compatibility: raw occupied intervals, without destructive hour rounding.
-- Updated apps use arena_availability + whole-range arena_has_available_court.
create or replace function public.arena_busy_intervals(p_arena_id uuid,p_from timestamptz,p_to timestamptz)
returns table(starts_at timestamptz,ends_at timestamptz)
language sql stable security definer set search_path=public as $$
  select s,s+interval '30 minutes' from generate_series(p_from,least(p_to,p_from+interval '32 days')-interval '30 minutes',interval '30 minutes') s
  where not public.arena_has_available_court(p_arena_id,s,s+interval '30 minutes');
$$;

create function arena_private.allocate_court(p_arena uuid,p_start timestamptz,p_end timestamptz)
returns uuid language plpgsql set search_path=public as $$
declare v_id uuid;begin
  perform pg_advisory_xact_lock(hashtextextended(p_arena::text,0));
  perform 1 from arenas where id=p_arena for share;
  if not public.arena_has_available_court(p_arena,p_start,p_end) then raise exception 'TIME_NO_LONGER_AVAILABLE';end if;
  select c.id into v_id from arena_courts c where c.arena_id=p_arena and c.is_active
    and not exists(select 1 from court_reservations r where r.court_id=c.id and r.starts_at<p_end and r.ends_at>p_start)
    order by c.court_number limit 1 for update;
  return v_id;
end $$;

create function public.sync_court_inventory()
returns trigger language plpgsql security definer set search_path=public as $$
declare kind text;v_active boolean;c record;v_found boolean:=false;begin
  kind:=case tg_table_name when 'bookings' then 'booking' when 'matches' then 'match' else 'block' end;
  if tg_op='DELETE' then
    perform pg_advisory_xact_lock(hashtextextended(old.arena_id::text,0));
    delete from court_reservations where source_type=kind and source_id=old.id;
    update inventory_migration_issues set resolved_at=now() where source_type=kind and source_id=old.id;
    return old;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(new.arena_id::text,0));
  if kind='block' then v_active:=new.cancelled_at is null;else v_active:=new.status<>'cancelled';end if;
  delete from court_reservations where source_type=kind and source_id=new.id;
  if v_active then
    if kind<>'block' and new.court_id is null then raise exception 'COURT_REQUIRED';end if;
    for c in select * from arena_courts where arena_id=new.arena_id and ((kind='block' and new.court_id is null and is_active) or id=new.court_id) loop
      insert into court_reservations(arena_id,court_id,source_type,source_id,starts_at,ends_at)
        values(new.arena_id,c.id,kind,new.id,new.starts_at,new.ends_at);
      v_found:=true;
    end loop;
    if not v_found then raise exception 'INVALID_COURT';end if;
  end if;
  update inventory_migration_issues set resolved_at=now() where source_type=kind and source_id=new.id and resolved_at is null;
  return new;
end $$;
create trigger phase1_booking_inventory after insert or update of arena_id,court_id,starts_at,ends_at,status on bookings for each row execute function sync_court_inventory();
create trigger phase1_match_inventory after insert or update of arena_id,court_id,starts_at,ends_at,status on matches for each row execute function sync_court_inventory();
create trigger phase1_block_inventory after insert or update of arena_id,court_id,starts_at,ends_at,cancelled_at on blocked_slots for each row execute function sync_court_inventory();
create trigger phase1_booking_inventory_delete after delete on bookings for each row execute function sync_court_inventory();
create trigger phase1_match_inventory_delete after delete on matches for each row execute function sync_court_inventory();
create trigger phase1_block_inventory_delete after delete on blocked_slots for each row execute function sync_court_inventory();

create table arena_private.requests(
  user_id uuid not null,request_key uuid not null,operation text not null,payload jsonb not null,result jsonb,
  primary key(user_id,request_key)
);
create function arena_private.begin_request(p_key uuid,p_operation text,p_payload jsonb)
returns jsonb language plpgsql set search_path=public as $$
declare r arena_private.requests%rowtype;begin
  if auth.uid() is null or p_key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':'||p_key::text,0));
  select * into r from arena_private.requests where user_id=auth.uid() and request_key=p_key;
  if found then
    if r.operation<>p_operation or r.payload<>p_payload then raise exception 'IDEMPOTENCY_PAYLOAD_MISMATCH';end if;
    return r.result;
  end if;
  insert into arena_private.requests values(auth.uid(),p_key,p_operation,p_payload,null);
  return null;
end $$;

create or replace function public.create_arena_booking_with_coupon(
  p_arena_id uuid,p_starts_at timestamptz,p_ends_at timestamptz,p_water_cartons integer,p_idempotency_key uuid,p_coupon_id uuid default null
) returns table(booking_id uuid,court_id uuid,court_number integer,total_price numeric,discount_amount numeric)
language plpgsql security definer set search_path=public as $$
declare v_user uuid:=public.require_oman_user();v_court uuid;v_number integer;v_price numeric;v_total numeric;v_discount numeric:=0;v_id uuid;v_coupon reward_coupons%rowtype;v_result jsonb;v_old bookings%rowtype;
begin
  if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
  v_result:=arena_private.begin_request(p_idempotency_key,'booking',jsonb_build_array(p_arena_id,p_starts_at,p_ends_at,p_water_cartons,p_coupon_id));
  if v_result is not null then return query select * from jsonb_to_record(v_result) as x(booking_id uuid,court_id uuid,court_number integer,total_price numeric,discount_amount numeric);return;end if;
  -- Backwards-compatible retry for an operation committed before this migration.
  select * into v_old from bookings b where b.user_id=v_user and b.idempotency_key=p_idempotency_key;
  if found then
    if (v_old.arena_id,v_old.starts_at,v_old.ends_at,v_old.water_cartons,v_old.coupon_id) is distinct from (p_arena_id,p_starts_at,p_ends_at,p_water_cartons,p_coupon_id) then raise exception 'IDEMPOTENCY_PAYLOAD_MISMATCH';end if;
    return query select v_old.id,v_old.court_id,c.court_number,v_old.total_price,v_old.discount_amount from arena_courts c where c.id=v_old.court_id;return;
  end if;
  if p_water_cartons is null or p_water_cartons<0 then raise exception 'INVALID_WATER_QUANTITY';end if;
  if not exists(select 1 from profiles p join arenas a on a.id=p_arena_id where p.id=v_user and p.gender=a.audience_gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
  v_court:=arena_private.allocate_court(p_arena_id,p_starts_at,p_ends_at);
  select a.price_per_hour,c.court_number into v_price,v_number from arenas a join arena_courts c on c.arena_id=a.id where c.id=v_court;
  v_total:=round(v_price*extract(epoch from(p_ends_at-p_starts_at))/3600+p_water_cartons*0.500,3);
  if p_coupon_id is not null then
    select * into v_coupon from reward_coupons where id=p_coupon_id and user_id=v_user and status='available' for update;
    if not found then raise exception 'COUPON_NOT_AVAILABLE';end if;
    v_discount:=least(v_total,v_coupon.value_omr);v_total:=v_total-v_discount;
  end if;
  insert into bookings(user_id,arena_id,court_id,starts_at,ends_at,total_price,status,water_cartons,water_unit_price,idempotency_key,coupon_id,discount_amount)
    values(v_user,p_arena_id,v_court,p_starts_at,p_ends_at,v_total,'upcoming',p_water_cartons,0.500,p_idempotency_key,p_coupon_id,v_discount) returning id into v_id;
  if p_coupon_id is not null then update reward_coupons set status='used',used_booking_id=v_id,used_at=now() where id=p_coupon_id;end if;
  v_result:=jsonb_build_object('booking_id',v_id,'court_id',v_court,'court_number',v_number,'total_price',v_total,'discount_amount',v_discount);
  update arena_private.requests set result=v_result where user_id=v_user and request_key=p_idempotency_key;
  return query select v_id,v_court,v_number,v_total,v_discount;
end $$;
create or replace function public.create_arena_booking(p_arena_id uuid,p_starts_at timestamptz,p_ends_at timestamptz,p_water_cartons integer default 0,p_idempotency_key uuid default gen_random_uuid())
returns table(booking_id uuid,court_id uuid,court_number integer,total_price numeric)
language sql security definer set search_path=public as $$
  select booking_id,court_id,court_number,total_price from public.create_arena_booking_with_coupon(p_arena_id,p_starts_at,p_ends_at,p_water_cartons,p_idempotency_key,null);
$$;

create or replace function public.create_arena_match(p_arena_id uuid,p_name text,p_description text,p_rules text,p_sport text,p_starts_at timestamptz,p_ends_at timestamptz,p_max_players integer,p_is_private boolean,p_show_joined_players boolean,p_payment_method text,p_idempotency_key uuid)
returns table(match_id uuid,court_id uuid,court_number integer)
language plpgsql security definer set search_path=public as $$
declare v_user uuid:=public.require_oman_user();v_court uuid;v_number integer;v_id uuid;v_gender text;v_price numeric;v_result jsonb;
begin
  if not public.my_profile_complete() then raise exception 'PROFILE_INCOMPLETE';end if;
  v_result:=arena_private.begin_request(p_idempotency_key,'match',jsonb_build_array(p_arena_id,p_name,p_description,p_rules,p_sport,p_starts_at,p_ends_at,p_max_players,p_is_private,p_show_joined_players,p_payment_method));
  if v_result is not null then return query select * from jsonb_to_record(v_result) as x(match_id uuid,court_id uuid,court_number integer);return;end if;
  if nullif(trim(p_name),'') is null or p_max_players is null or p_max_players<2 or p_payment_method is null or p_payment_method not in('cash','card') then raise exception 'INVALID_MATCH';end if;
  select gender into v_gender from profiles where id=v_user;
  if not exists(select 1 from arenas where id=p_arena_id and audience_gender=v_gender) then raise exception 'GENDER_NOT_ALLOWED';end if;
  v_court:=arena_private.allocate_court(p_arena_id,p_starts_at,p_ends_at);
  select a.price_per_hour,c.court_number into v_price,v_number from arenas a join arena_courts c on c.arena_id=a.id where c.id=v_court;
  insert into matches(arena_id,court_id,host_id,name,description,rules,sport,starts_at,ends_at,max_players,price_per_player,gender,payment_method,show_joined_players,is_private,status,idempotency_key)
    values(p_arena_id,v_court,v_user,trim(p_name),p_description,p_rules,p_sport,p_starts_at,p_ends_at,p_max_players,round(v_price*extract(epoch from(p_ends_at-p_starts_at))/3600/p_max_players,3),v_gender,p_payment_method,p_show_joined_players,p_is_private,'upcoming',p_idempotency_key) returning id into v_id;
  insert into match_players(match_id,user_id,status) values(v_id,v_user,'joined');
  v_result:=jsonb_build_object('match_id',v_id,'court_id',v_court,'court_number',v_number);
  update arena_private.requests set result=v_result where user_id=v_user and request_key=p_idempotency_key;
  return query select v_id,v_court,v_number;
end $$;

create function public.owner_reserve(p_arena uuid,p_start timestamptz,p_end timestamptz,p_name text,p_phone text,p_notes text,p_block boolean,p_request_key uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_court uuid;v_id uuid;v_result jsonb;begin
  if not public.is_arena_operator(p_arena) then raise exception 'NOT_AUTHORIZED' using errcode='42501';end if;
  v_result:=arena_private.begin_request(p_request_key,'owner_reserve',jsonb_build_array(p_arena,p_start,p_end,p_name,p_phone,p_notes,p_block));
  if v_result is not null then return (v_result->>'id')::uuid;end if;
  v_court:=arena_private.allocate_court(p_arena,p_start,p_end);
  if p_block then
    if nullif(trim(p_notes),'') is null then raise exception 'REASON_REQUIRED';end if;
    insert into blocked_slots(arena_id,court_id,starts_at,ends_at,reason,created_by) values(p_arena,v_court,p_start,p_end,p_notes,auth.uid()) returning id into v_id;
  else
    if nullif(trim(p_name),'') is null then raise exception 'CUSTOMER_NAME_REQUIRED';end if;
    insert into bookings(arena_id,court_id,starts_at,ends_at,total_price,status,booking_type,customer_name,customer_phone,notes,idempotency_key)
      select p_arena,v_court,p_start,p_end,round(price_per_hour*extract(epoch from(p_end-p_start))/3600,3),'confirmed','manual',p_name,p_phone,p_notes,p_request_key from arenas where id=p_arena returning id into v_id;
  end if;
  update arena_private.requests set result=jsonb_build_object('id',v_id) where user_id=auth.uid() and request_key=p_request_key;
  return v_id;
end $$;
create or replace function public.owner_create_manual_booking(p_arena uuid,p_start timestamptz,p_end timestamptz,p_name text,p_phone text,p_notes text default null)
returns uuid language sql security definer set search_path=public as $$ select public.owner_reserve(p_arena,p_start,p_end,p_name,p_phone,p_notes,false,gen_random_uuid()); $$;
-- Old owner "block time" meant the entire arena. Keep that meaning safely.
create or replace function public.owner_block_slot(p_arena uuid,p_start timestamptz,p_end timestamptz,p_reason text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;begin
  if not public.is_arena_operator(p_arena) then raise exception 'NOT_AUTHORIZED';end if;
  perform pg_advisory_xact_lock(hashtextextended(p_arena::text,0));
  if p_start<=now() or not public.arena_accepts_time_range(p_arena,p_start,p_end) then raise exception 'INVALID_TIME_RANGE';end if;
  if exists(select 1 from inventory_migration_issues where arena_id=p_arena and resolved_at is null and starts_at<p_end and ends_at>p_start) then raise exception 'INVENTORY_REQUIRES_REVIEW';end if;
  insert into blocked_slots(arena_id,starts_at,ends_at,reason,created_by) values(p_arena,p_start,p_end,p_reason,auth.uid()) returning id into v_id;return v_id;
end $$;
create or replace function public.owner_cancel_booking(p_booking uuid,p_reason text)
returns void language sql security definer set search_path=public as $$ select public.cancel_arena_booking(p_booking,p_reason); $$;
create function public.owner_cancel_block(p_block uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  update blocked_slots set cancelled_at=now() where id=p_block and public.is_arena_operator(arena_id);
  if not found then raise exception 'NOT_AUTHORIZED';end if;
end $$;
create function public.resolve_inventory_issue(p_type text,p_id uuid,p_court uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_platform_admin() then raise exception 'ADMIN_ONLY';end if;
  if p_type='booking' then update bookings set court_id=p_court where id=p_id;
  elsif p_type='match' then update matches set court_id=p_court where id=p_id;
  elsif p_type='block' then update blocked_slots set court_id=p_court where id=p_id;
  else raise exception 'INVALID_SOURCE';end if;
end $$;

alter table court_reservations enable row level security;
alter table inventory_migration_issues enable row level security;
alter table blocked_slots enable row level security;
do $$ declare r record;begin for r in select policyname from pg_policies where schemaname='public' and tablename='blocked_slots' loop execute format('drop policy %I on blocked_slots',r.policyname);end loop;end $$;
revoke all on court_reservations,inventory_migration_issues,blocked_slots from public,anon,authenticated;
grant select on court_reservations,inventory_migration_issues,blocked_slots to authenticated;
create policy phase1_inventory_staff on court_reservations for select to authenticated using(public.is_arena_operator(arena_id));
create policy phase1_inventory_issues on inventory_migration_issues for select to authenticated using(public.is_platform_admin());
create policy phase1_blocks_staff on blocked_slots for select to authenticated using(public.is_arena_operator(arena_id));
revoke all on all tables in schema arena_private from public,anon,authenticated;
revoke all on all functions in schema arena_private from public,anon,authenticated;
revoke all on function public.arena_availability(uuid,date,date),public.owner_reserve(uuid,timestamptz,timestamptz,text,text,text,boolean,uuid),public.owner_cancel_block(uuid),public.resolve_inventory_issue(text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.arena_availability(uuid,date,date),public.arena_has_available_court(uuid,timestamptz,timestamptz) to anon,authenticated;
grant execute on function public.owner_reserve(uuid,timestamptz,timestamptz,text,text,text,boolean,uuid),public.owner_cancel_block(uuid),public.resolve_inventory_issue(text,uuid,uuid) to authenticated;
commit;
