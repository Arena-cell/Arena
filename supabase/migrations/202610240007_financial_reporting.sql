begin;
create function public.admin_financial_report(p_from timestamptz,p_to timestamptz,p_arena uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare r record;p jsonb;rows jsonb:='[]';arenas_json jsonb;payment_verified bigint;settlement_net bigint;fees bigint;fee_returns bigint;
 transferred_period bigint;company_funding bigint;booking_count bigint;booking_value bigint;unknown_matches bigint;pending_count bigint;manual_count bigint;manual_value bigint;
 gross bigint:=0;discounts bigint:=0;arena_discounts bigint:=0;owner_discounts bigint:=0;commissions bigint:=0;
 captured bigint:=0;refunded bigint:=0;owner_due bigint:=0;transferred bigint:=0;held bigint:=0;actual_fee bigint:=0;actual_fee_known integer:=0;
 remaining_arena_discount bigint:=0;remaining_owner_discount bigint:=0;fee_returned_service bigint:=0;gateway_budget bigint:=0;arena_budget bigint:=0;
begin
 if not public.is_platform_admin() then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 if p_from is null or p_to is null or p_to<=p_from or p_to-p_from>interval '367 days' then raise exception 'INVALID_REPORT_PERIOD';end if;
 if (select count(*) from booking_financial_snapshots s join checkout_orders o on o.id=s.origin_order_id
  where o.starts_at>=p_from and o.starts_at<p_to and (p_arena is null or s.arena_id=p_arena))>10000 then raise exception 'REPORT_RANGE_TOO_LARGE';end if;
 for r in select s.id,s.arena_id,s.owner_id,s.created_at,o.id order_id,o.booking_id,o.match_id,o.starts_at,o.ends_at,
 a.name_ar,a.name_en,a.name,pr.display_name owner_name,
 coalesce(b.court_id,m.court_id) court_id,c.court_number,m.sport,
 coalesce(b.status,m.status) status
 from booking_financial_snapshots s join checkout_orders o on o.id=s.origin_order_id join arenas a on a.id=s.arena_id
 left join profiles pr on pr.id=s.owner_id left join bookings b on b.id=o.booking_id left join matches m on m.id=o.match_id
 left join arena_courts c on c.id=coalesce(b.court_id,m.court_id)
 where o.starts_at>=p_from and o.starts_at<p_to and (p_arena is null or s.arena_id=p_arena)
 and (o.booking_id is not null or o.match_id is not null) order by o.starts_at,s.id loop
  p:=arena_private.booking_financial_position(r.id);
  rows:=rows||jsonb_build_object('arena_id',r.arena_id,'owner_id',r.owner_id,'owner_name',r.owner_name,
   'name_ar',r.name_ar,'name_en',r.name_en,'name',r.name,'booking_id',r.booking_id,'match_id',r.match_id,
   'starts_at',r.starts_at,'ends_at',r.ends_at,'court_id',r.court_id,'court_number',r.court_number,'sport',r.sport,'booking_status',r.status)||'[]'::jsonb;
  -- Attach the accounting position to the last newly constructed row, rather
  -- than exposing mutable order payloads or any full bank account.
  rows:=jsonb_set(rows,array[(jsonb_array_length(rows)-1)::text],(rows->(jsonb_array_length(rows)-1))||p);
  gross:=gross+(p->>'gross_baisa')::bigint;discounts:=discounts+(p->>'discount_baisa')::bigint;
  arena_discounts:=arena_discounts+(p->>'arena_discount_baisa')::bigint;owner_discounts:=owner_discounts+(p->>'owner_discount_baisa')::bigint;
  commissions:=commissions+(p->>'commission_baisa')::bigint;captured:=captured+(p->>'collected_baisa')::bigint;
  remaining_arena_discount:=remaining_arena_discount+(p->>'remaining_arena_discount_baisa')::bigint;
  remaining_owner_discount:=remaining_owner_discount+(p->>'owner_discount_baisa')::bigint-(p->>'owner_discount_reversed_baisa')::bigint;
  gateway_budget:=gateway_budget+(p->>'internal_gateway_allocation_baisa')::bigint;
  arena_budget:=arena_budget+(p->>'internal_arena_allocation_baisa')::bigint;
  fee_returned_service:=fee_returned_service+coalesce((p->>'gateway_fee_refunded_baisa')::bigint,0);
  refunded:=refunded+(p->>'refunded_baisa')::bigint;owner_due:=owner_due+(p->>'owner_net_baisa')::bigint;
  transferred:=transferred+(p->>'transferred_baisa')::bigint;
  if p->>'hold_reason' is not null then held:=held+(p->>'untransferred_baisa')::bigint;end if;
  if p->>'actual_gateway_fee_baisa' is not null then
   actual_fee:=actual_fee+(p->>'actual_gateway_fee_baisa')::bigint;
   if (p->>'settled_gross_baisa')::bigint>=(p->>'collected_baisa')::bigint and (p->>'collected_baisa')::bigint>0 then actual_fee_known:=actual_fee_known+1;end if;
  end if;
 end loop;
 select coalesce(jsonb_agg(jsonb_build_object('arena_id',a.id,'name_ar',a.name_ar,'name_en',a.name_en,'name',a.name,
 'owner_id',a.owner_id,'owner_name',pr.display_name,
 'governorate',to_jsonb(a)->>'governorate_code','wilayat',to_jsonb(a)->>'wilayat_code','area_ar',a.area_ar,'area_en',a.area_en,
 'bookings',(select count(*) from bookings b where b.arena_id=a.id and b.starts_at>=p_from and b.starts_at<p_to)
 +(select count(*) from matches m where m.arena_id=a.id and m.starts_at>=p_from and m.starts_at<p_to),
 'manual_bookings',(select count(*) from bookings b where b.arena_id=a.id and b.booking_type='manual' and b.starts_at>=p_from and b.starts_at<p_to),
 'accounted_bookings',(select count(*) from jsonb_array_elements(rows) x where x->>'arena_id'=a.id::text),
 'gross_baisa',(select coalesce(sum((x->>'gross_baisa')::bigint),0) from jsonb_array_elements(rows) x where x->>'arena_id'=a.id::text),
 'commission_baisa',(select coalesce(sum((x->>'commission_baisa')::bigint),0) from jsonb_array_elements(rows) x where x->>'arena_id'=a.id::text),
 'owner_net_baisa',(select coalesce(sum((x->>'owner_net_baisa')::bigint),0) from jsonb_array_elements(rows) x where x->>'arena_id'=a.id::text),
 'transferred_baisa',(select coalesce(sum((x->>'transferred_baisa')::bigint),0) from jsonb_array_elements(rows) x where x->>'arena_id'=a.id::text)
 ) order by a.name),'[]') into arenas_json from arenas a left join profiles pr on pr.id=a.owner_id where p_arena is null or a.id=p_arena;
 select (select count(*) from bookings b where b.starts_at>=p_from and b.starts_at<p_to and (p_arena is null or b.arena_id=p_arena))
 +(select count(*) from matches m where m.starts_at>=p_from and m.starts_at<p_to and (p_arena is null or m.arena_id=p_arena)) into booking_count;
 select (select coalesce(sum(round(b.total_price*1000)),0) from bookings b where b.booking_type<>'manual' and b.starts_at>=p_from and b.starts_at<p_to and (p_arena is null or b.arena_id=p_arena))
 +(select coalesce(sum(m.total_amount_baisa),0) from matches m where m.starts_at>=p_from and m.starts_at<p_to and (p_arena is null or m.arena_id=p_arena)) into booking_value;
 select count(*),coalesce(sum(round(total_price*1000)),0) into manual_count,manual_value from bookings
 where booking_type='manual' and starts_at>=p_from and starts_at<p_to and(p_arena is null or arena_id=p_arena);
 select count(*) into unknown_matches from matches where starts_at>=p_from and starts_at<p_to and total_amount_baisa is null and (p_arena is null or arena_id=p_arena);
 select count(*) into pending_count from checkout_orders where starts_at>=p_from and starts_at<p_to and booking_id is null and match_id is null and purpose<>'participant' and fulfillment_status='pending' and (p_arena is null or arena_id=p_arena);
 -- Cash-movement figures use first verified capture time / actual statement
 -- and transfer dates. They are not mislabeled as service-period revenue.
 select coalesce(sum(o.amount_due_baisa),0) into payment_verified from checkout_orders o
 join lateral (select min(received_at) t from arena_private.payment_events where order_id=o.id and verified_status='paid') v on true
 where v.t>=p_from and v.t<p_to and o.payment_method='card' and o.payment_status in('paid','partially_refunded','refunded') and(p_arena is null or o.arena_id=p_arena);
 select coalesce(sum(b.bank_net_baisa),0),sum(b.gateway_fee_baisa),sum(b.gateway_fee_refunded_baisa) into settlement_net,fees,fee_returns
 from finance_bank_settlements b join checkout_orders o on o.id=b.order_id where b.settled_at>=p_from and b.settled_at<p_to and(p_arena is null or o.arena_id=p_arena);
 select coalesce(sum(x.amount_baisa),0) into transferred_period from owner_bank_transfer_allocations x join owner_bank_transfers t on t.id=x.transfer_id
 join booking_financial_snapshots s on s.id=x.snapshot_id where t.transferred_at>=p_from and t.transferred_at<p_to and(p_arena is null or s.arena_id=p_arena);
 return jsonb_build_object('company_name','محور للتقنية ش.م.م','currency','OMR','from',p_from,'to',p_to,
 'policy_activated_at',(select activated_at from arena_private.finance_policy where singleton),
 'service_period',jsonb_build_object('booking_count',booking_count,'booking_value_baisa',booking_value,
 'manual_booking_count',manual_count,'manual_operational_value_baisa',manual_value,
 'historical_match_value_unknown_count',unknown_matches,'accounted_booking_count',jsonb_array_length(rows),
 'historical_not_recalculated_count',booking_count-manual_count-jsonb_array_length(rows),'pending_checkout_count',pending_count,
 'gross_baisa',gross,'discount_baisa',discounts,'arena_discount_baisa',arena_discounts,'owner_discount_baisa',owner_discounts,
 'remaining_arena_discount_baisa',remaining_arena_discount,'remaining_owner_discount_baisa',remaining_owner_discount,
 'internal_gateway_allocation_baisa',gateway_budget,'internal_arena_allocation_baisa',arena_budget,
 'arena_net_contractual_baisa',commissions-remaining_arena_discount,
 'arena_net_after_observed_fees_baisa',case when actual_fee_known=jsonb_array_length(rows) and actual_fee_known>0 then commissions-remaining_arena_discount-actual_fee+fee_returned_service end,
 'commission_baisa',commissions,'collected_baisa',captured,'refunded_baisa',refunded,'owner_net_baisa',owner_due,
 'transferred_baisa',transferred,'untransferred_baisa',greatest(owner_due-transferred,0),'held_baisa',held,
 'actual_gateway_fee_baisa',case when actual_fee_known>0 then actual_fee end,'actual_gateway_fee_known_bookings',actual_fee_known),
 'cash_movements',jsonb_build_object('first_verified_capture_baisa',payment_verified,'bank_net_baisa',settlement_net,
 'actual_gateway_fee_baisa',fees,'gateway_fee_refunded_baisa',fee_returns,'executed_transfers_baisa',transferred_period),
 'arenas',arenas_json,'bookings',rows);
end$$;
revoke all on function public.admin_financial_report(timestamptz,timestamptz,uuid) from public,anon,authenticated;
grant execute on function public.admin_financial_report(timestamptz,timestamptz,uuid) to authenticated;
revoke all on all functions in schema arena_private from public,anon,authenticated;
commit;
