select jsonb_build_object('database',current_database(),'baseline',(select count(*) from arena_private.staging_installation where version between '202610080101' and '202610080108'),
 'policy_already_applied',(select count(*) from arena_private.staging_installation where version like '20261009010%'),
 'bookings',(select count(*) from bookings),'paid',(select count(*) from checkout_orders where payment_status in('paid','partially_refunded')),
 'addons_unknown_delivery',(select count(*) from booking_addons b join checkout_orders o on o.id=b.order_id where o.fulfillment_status='fulfilled'),
 'refunds',(select count(*) from payment_refunds),'inventory_conflicts',(select count(*) from inventory_migration_issues where resolved_at is null),
 'duplicate_participant_entitlements',(select count(*) from (select match_id,user_id from checkout_orders where purpose='participant' and fulfillment_status<>'cancelled' group by match_id,user_id having count(*)>1)s)) as preflight;
