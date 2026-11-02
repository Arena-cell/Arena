-- Staging gtcrijikfaglqcwqozel only
begin;
do $$ begin if (select count(*) from arena_private.staging_installation where version between '202610040001' and '202610040004')<>4 then raise exception 'PHASE2_BASE_REQUIRED';end if;end $$;

create function public.match_payment_summary(p_match uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare m matches%rowtype;covered boolean;seat integer;begin
 if not public.can_view_match(p_match,auth.uid()) then raise exception 'MATCH_NOT_FOUND';end if;
 select * into strict m from matches where id=p_match;
 if m.checkout_order_id is null then return jsonb_build_object('legacy',true);end if;
 covered:=m.payment_mode='host_pays_all' and exists(select 1 from checkout_orders where id=m.checkout_order_id and payment_status='paid' and fulfillment_status='fulfilled' and amount_due_baisa=m.total_amount_baisa);
 select s into seat from generate_series(1,m.max_players-1)s where not exists(select 1 from checkout_orders o where o.match_id=m.id and o.seat_index=s and o.fulfillment_status<>'cancelled') order by s limit 1;
 return jsonb_build_object('payment_mode',m.payment_mode,'covered_by_host',covered,'total_amount_baisa',m.total_amount_baisa,'next_share_baisa',case when covered then 0 when seat is not null then arena_private.share_baisa(m.total_amount_baisa,m.max_players,seat) else null end);
end $$;
revoke all on function public.match_payment_summary(uuid) from public,anon,authenticated;
grant execute on function public.match_payment_summary(uuid) to authenticated;

insert into arena_private.staging_installation(version,source_sha256) values('202610040005','94611a6061c1ebf90c61124fc368b13411da1544efe890b79a060421bf0f6b88');
commit;
select version from arena_private.staging_installation where version='202610040005';