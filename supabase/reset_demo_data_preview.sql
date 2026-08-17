-- READ-ONLY PREVIEW. This file deliberately deletes nothing.
-- Run it first and review every returned row before authorizing cleanup.

select id, name, name_ar, name_en, location, audience_gender, created_at
from public.arenas
order by created_at, name;

select b.id, b.user_id, b.arena_id, a.name as arena_name,
       b.starts_at, b.ends_at, b.status, b.total_price, b.created_at
from public.bookings b
left join public.arenas a on a.id = b.arena_id
order by b.created_at;

select m.id, m.host_id, m.arena_id, a.name as arena_name,
       m.starts_at, m.ends_at, m.created_at
from public.matches m
left join public.arenas a on a.id = m.arena_id
order by m.created_at;

select c.id, c.arena_id, a.name as arena_name, c.court_number, c.is_active
from public.arena_courts c
join public.arenas a on a.id = c.arena_id
order by a.name, c.court_number;

-- No DELETE/TRUNCATE statements belong here. After the owner confirms exact
-- arena IDs, create a separate transaction-scoped cleanup script targeting
-- only those IDs and their dependent demo rows.
