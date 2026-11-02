-- READ ONLY. Only arena-staging / gtcrijikfaglqcwqozel.
select jsonb_build_object('receipts',(select jsonb_agg(to_jsonb(i)) from arena_private.staging_installation i where version>='202610090101'),
 'paid',(select count(*) from checkout_orders where payment_status in('paid','partially_refunded')),
 'refunds',(select count(*) from payment_refunds),'inventory_conflicts',(select count(*) from inventory_migration_issues where resolved_at is null),
 'tables',(select jsonb_agg(table_schema||'.'||table_name) from information_schema.tables where table_name ~ '(audit|stock|inventory|movement|backup)' and table_schema in('public','arena_private')),
 'historical',(select jsonb_agg(jsonb_build_object('addon',to_jsonb(a),'order',to_jsonb(o),'booking',to_jsonb(b),'arena_addon',to_jsonb(aa),
 'backup_addon',s.payload,'backup_catalog',(select payload from arena_private.refund_policy_backup_20261009 where kind='arena_addons' and row_key=a.arena_addon_id::text)))
 from arena_private.refund_policy_backup_20261009 s join booking_addons a on a.id::text=s.row_key join checkout_orders o on o.id=a.order_id left join bookings b on b.id=o.booking_id join arena_addons aa on aa.id=a.arena_addon_id
 where s.kind='booking_addons'),
 'overlaps',(select jsonb_agg(to_jsonb(o)) from checkout_orders o where o.arena_id='a1000000-0000-4000-8000-000000000002' and o.fulfillment_status in('fulfilled','refund_required'))
) as final_preflight;
