-- Staging ONLY: gtcrijikfaglqcwqozel. Temporary tables, no persistent mutations.
-- Executes the exact existing migration backfill block with pg_temp shadow tables.
begin;
set local search_path=pg_temp,public,extensions;
create temporary table bookings (like public.bookings including defaults including constraints including indexes) on commit drop;
create temporary table matches (like public.matches including defaults including constraints including indexes) on commit drop;
create temporary table arena_courts (like public.arena_courts including defaults including constraints including indexes) on commit drop;
create temporary table court_reservations (like public.court_reservations including defaults including constraints including indexes) on commit drop;
create temporary table inventory_migration_issues (like public.inventory_migration_issues including defaults including constraints including indexes) on commit drop;
create temporary table blocked_slots (like public.blocked_slots including defaults including constraints including indexes) on commit drop;
insert into arena_courts(arena_id,court_number) values
 ('a2000000-0000-4000-8000-000000000001',1),('a2000000-0000-4000-8000-000000000001',2);
insert into bookings(arena_id,starts_at,ends_at,total_price,status)
select 'a2000000-0000-4000-8000-000000000001','2035-02-01 10:00+04','2035-02-01 11:00+04',10,'upcoming' from generate_series(1,3);
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
do $$ begin
 if (select count(*) from bookings)<>3
 or (select count(*) from bookings where court_id is not null)<>2
 or (select count(*) from inventory_migration_issues where resolved_at is null)<>1
 or (select count(*) from court_reservations)<>2 then
 raise exception 'BACKFILL_PROBE_FAILED';end if;
end $$;
select 'PASS' result,(select count(*) from bookings) preserved_bookings,
 (select count(*) from bookings where court_id is not null) assigned_courts,
 (select count(*) from inventory_migration_issues where resolved_at is null) preserved_conflicts;
rollback;
