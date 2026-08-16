-- Exposes only occupied time ranges, never booking owners or private details.
-- The existing prevent_arena_time_conflict trigger remains the final atomic
-- protection against two users booking the same time concurrently.

create or replace function public.arena_busy_intervals(
  p_arena_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns table (starts_at timestamptz, ends_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select b.starts_at, b.ends_at
  from public.bookings b
  where b.arena_id = p_arena_id
    and coalesce(b.status, 'upcoming') <> 'cancelled'
    and b.starts_at < p_to
    and b.ends_at > p_from
  union all
  select m.starts_at, m.ends_at
  from public.matches m
  where m.arena_id = p_arena_id
    and m.starts_at < p_to
    and m.ends_at > p_from;
$$;

revoke all on function public.arena_busy_intervals(uuid, timestamptz, timestamptz) from public;
grant execute on function public.arena_busy_intervals(uuid, timestamptz, timestamptz) to anon, authenticated;
