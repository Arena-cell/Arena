-- READ ONLY: migration/security and scoped preservation evidence.
select jsonb_build_object(
 'receipt',(select to_jsonb(s) from arena_private.staging_installation s where version='202610090103'),
 'history_receipt',(select to_jsonb(s) from arena_private.staging_installation s where version='202610090104'),
 'historical_addons_unchanged',(select count(*) from arena_private.refund_policy_backup_20261009 h join booking_addons a on a.id::text=h.row_key join arena_private.phase3_final_backup_20261009 b on b.kind='booking_addons' and b.row_key=a.id::text where h.kind='booking_addons' and b.payload=to_jsonb(a)),
 'prior_addon_changes',(select count(*) from arena_private.phase3_final_backup_20261009 b left join booking_addons a on a.id::text=b.row_key where b.kind='booking_addons' and b.payload is distinct from to_jsonb(a)),
 'prior_catalog_changes',(select count(*) from arena_private.phase3_final_backup_20261009 b left join arena_addons a on a.id::text=b.row_key where b.kind='arena_addons' and b.payload is distinct from to_jsonb(a)),
 'prior_order_changes',(select count(*) from arena_private.phase3_final_backup_20261009 b left join checkout_orders o on o.id::text=b.row_key where b.kind='checkout_orders' and b.payload is distinct from to_jsonb(o)),
 'prior_match_changes',(select count(*) from arena_private.phase3_final_backup_20261009 b left join matches m on m.id::text=b.row_key where b.kind='matches' and b.payload is distinct from to_jsonb(m)-'cancelled_at'-'cancelled_by'),
 'prior_membership_changes',(select count(*) from arena_private.phase3_final_backup_20261009 b left join match_players m on m.match_id::text||':'||m.user_id::text=b.row_key where b.kind='match_players' and b.payload is distinct from to_jsonb(m)-'cancelled_from_status'),
 'prior_court_changes',(select count(*) from arena_private.phase3_final_backup_20261009 b left join court_reservations r on r.id::text=b.row_key where b.kind='court_reservations' and (r.id is null or b.payload is distinct from to_jsonb(r))),
 'refresh_test',(select jsonb_build_object('status',status,'reason',cancellation_reason,'actor',cancelled_by,'members',(select count(*) from match_players p where p.match_id=m.id and p.status='cancelled'),'court_reservations',(select count(*) from court_reservations r where r.source_id=m.id)) from matches m where id='f3090000-0000-4000-8000-000000000003'),
 'private_test',(select jsonb_build_object('status',status,'private',is_private,'members',(select jsonb_agg(jsonb_build_object('user_id',user_id,'status',status,'previous_status',cancelled_from_status)) from match_players p where p.match_id=m.id),'court_reservations',(select count(*) from court_reservations r where r.source_id=m.id),'former_participant_read',public.can_view_match(m.id,'c1faaa2a-f829-46f0-ae35-9f095a01ef4f'),'outsider_read',public.can_view_match(m.id,'83c787cc-4c6f-4802-b9e4-2522d7f046ea')) from matches m where id='f3090000-0000-4000-8000-000000000004'),
 'test_match',(select to_jsonb(m) from matches m where id='f3090000-0000-4000-8000-000000000001'),
 'test_memberships',(select jsonb_agg(to_jsonb(p)) from match_players p where match_id='f3090000-0000-4000-8000-000000000001'),
 'test_court_reservations',(select count(*) from court_reservations where source_id='f3090000-0000-4000-8000-000000000001'),
 'test_decisions',(select count(*) from arena_private.match_decisions where match_id='f3090000-0000-4000-8000-000000000001'),
 'test_notifications',(select jsonb_agg(jsonb_build_object('recipient',user_id,'type',type,'event_key',event_key,'body',body_en)) from notifications where event_key='match-decision:f3090000-0000-4000-8000-000000000001'),
 'refund_count',(select count(*) from payment_refunds),
 'payment_success_count',(select count(*) from checkout_orders where payment_status in('paid','partially_refunded','refunded')),
 'ordinary_150_boundary',arena_private.booking_cancel_allowed('2040-01-01 12:30Z','2040-01-01 10:00Z'),
 'host_90_boundary',arena_private.host_match_cancel_allowed('2040-01-01 11:30Z','2040-01-01 10:00Z'),
 'anonymous_cancel_permission',has_function_privilege('anon','public.cancel_host_paid_match(uuid)','execute'),
 'authenticated_refund_confirmation_permission',has_function_privilege('authenticated','public.payment_confirm_refund(uuid,text,bigint,boolean)','execute'),
 'authenticated_direct_match_update',has_table_privilege('authenticated','public.matches','update')
) as verification;

