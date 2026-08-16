-- Run this migration in the shared PlayOn Supabase project.
-- It removes the ambiguous `match_id` reference that prevents a new game
-- from adding its host to match_players.
create or replace function public.join_match(
  match_id uuid,
  target_user_id uuid default auth.uid()
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_capacity integer;
  v_joined_count integer;
  v_host uuid;
begin
  select m.max_players, m.host_id
    into v_capacity, v_host
  from public.matches as m
  where m.id = $1
  for update;

  if v_capacity is null then
    raise exception 'Match not found';
  end if;

  if $2 <> auth.uid() and v_host <> auth.uid() then
    raise exception 'Only the host can invite players';
  end if;

  select count(*)
    into v_joined_count
  from public.match_players as mp
  where mp.match_id = $1
    and mp.status = 'joined';

  if v_joined_count >= v_capacity then
    raise exception 'Match is full';
  end if;

  insert into public.match_players (match_id, user_id, status)
  values (
    $1,
    $2,
    case when $2 = auth.uid() then 'joined' else 'invited' end
  )
  on conflict (match_id, user_id)
  do update set status = excluded.status;
end;
$$;

grant execute on function public.join_match(uuid, uuid) to authenticated;
