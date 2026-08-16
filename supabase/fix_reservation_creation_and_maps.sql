-- Run once in Supabase SQL Editor.
-- Fixes match creation on databases where the shared conflict trigger tries
-- to access bookings.status while processing a matches row.

alter table public.arenas
  add column if not exists google_maps_url text;

create or replace function public.prevent_arena_time_conflict()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name = 'bookings' then
    if coalesce(new.status, 'upcoming') = 'cancelled' then
      return new;
    end if;

    if exists (
      select 1 from public.bookings b
      where b.arena_id = new.arena_id
        and b.id is distinct from new.id
        and coalesce(b.status, 'upcoming') <> 'cancelled'
        and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) or exists (
      select 1 from public.matches m
      where m.arena_id = new.arena_id
        and tstzrange(m.starts_at, m.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) then
      raise exception 'This stadium is already booked for the selected time.';
    end if;
  elsif tg_table_name = 'matches' then
    if exists (
      select 1 from public.matches m
      where m.arena_id = new.arena_id
        and m.id is distinct from new.id
        and tstzrange(m.starts_at, m.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) or exists (
      select 1 from public.bookings b
      where b.arena_id = new.arena_id
        and coalesce(b.status, 'upcoming') <> 'cancelled'
        and tstzrange(b.starts_at, b.ends_at, '[)') && tstzrange(new.starts_at, new.ends_at, '[)')
    ) then
      raise exception 'This stadium is already booked for the selected time.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists bookings_prevent_arena_time_conflict on public.bookings;
create trigger bookings_prevent_arena_time_conflict
before insert or update of arena_id, starts_at, ends_at, status on public.bookings
for each row execute function public.prevent_arena_time_conflict();

drop trigger if exists matches_prevent_arena_time_conflict on public.matches;
create trigger matches_prevent_arena_time_conflict
before insert or update of arena_id, starts_at, ends_at on public.matches
for each row execute function public.prevent_arena_time_conflict();
