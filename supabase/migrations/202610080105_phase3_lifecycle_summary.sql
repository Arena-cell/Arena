-- Safe aggregate lifecycle visibility; count eligible confirmed seats on the server.
begin;
create function public.match_lifecycle_summary(p_match uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare m matches%rowtype;begin
 if not public.can_view_match(p_match,auth.uid()) then raise exception 'MATCH_NOT_VISIBLE' using errcode='42501';end if;
 select * into strict m from matches where id=p_match;
 return jsonb_build_object('confirmed_players',arena_private.eligible_match_players(m.id),
  'max_players',m.max_players,'confirmation_threshold',(m.max_players::bigint*4+4)/5,
  'decision_at',m.decision_at,'decision_outcome',m.decision_outcome,
  'decision_joined_count',m.decision_joined_count,'cancellation_reason',m.cancellation_reason,
  'withdrawal_locked',m.decision_outcome='confirmed','status',m.status);
end $$;
revoke all on function public.match_lifecycle_summary(uuid) from public,anon,authenticated;
grant execute on function public.match_lifecycle_summary(uuid) to authenticated,anon;
commit;
