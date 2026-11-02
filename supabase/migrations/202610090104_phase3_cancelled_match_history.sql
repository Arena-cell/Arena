-- Retain former participant read access after whole-match cancellation.
-- No financial, inventory or decision rules change; do not backfill unknown history.
begin;
alter table public.match_players add column cancelled_from_status text
 check(cancelled_from_status in('invited','requested','joined','rejected'));
create function public.phase3_record_cancelled_membership() returns trigger
language plpgsql set search_path=public as $$ begin
 if new.status='cancelled' and old.status<>'cancelled' then new.cancelled_from_status:=old.status;
 else new.cancelled_from_status:=old.cancelled_from_status;end if;
 return new;
end $$;
create trigger phase3_record_cancelled_membership before update of status on public.match_players
for each row execute function public.phase3_record_cancelled_membership();
revoke all on function public.phase3_record_cancelled_membership() from public,anon,authenticated;

create or replace function public.can_view_match(p_match_id uuid,p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from matches m where m.id=p_match_id and (
  (not m.is_private and (p_user_id is null or exists(select 1 from profiles viewer where viewer.id=p_user_id and viewer.gender=m.gender)))
  or m.host_id=p_user_id or public.is_platform_admin_user(p_user_id) or public.is_stadium_owner_of(m.arena_id,p_user_id)
  or exists(select 1 from match_players mp where mp.match_id=m.id and mp.user_id=p_user_id and
   (mp.status in('invited','requested','joined') or
    (m.status='cancelled' and mp.status='cancelled' and mp.cancelled_from_status in('invited','requested','joined'))))
 ));
$$;
create or replace function public.can_view_match_players(p_match_id uuid,p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from matches m where m.id=p_match_id and (
  public.is_platform_admin_user(p_user_id) or public.is_stadium_owner_of(m.arena_id,p_user_id) or m.host_id=p_user_id
  or exists(select 1 from match_players own where own.match_id=m.id and own.user_id=p_user_id and
   (own.status in('invited','requested','joined') or
    (m.status='cancelled' and own.status='cancelled' and own.cancelled_from_status in('invited','requested','joined'))))
  or (not m.is_private and coalesce(m.show_joined_players,true))
 ));
$$;
-- Existing execute grants and row-specific player privacy rules are retained.
commit;
