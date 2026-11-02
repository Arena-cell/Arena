-- READ ONLY investigation; one result preserves both result sets.
select jsonb_build_object('records',(select jsonb_agg(to_jsonb(x)) from (select a.id,a.order_id,o.booking_id,o.match_id,o.arena_id,a.addon_code,a.kind,a.quantity,
 b.status as booking_status,o.payment_status,o.fulfillment_status,a.inventory_tracked,
 a.stock_debited_quantity,a.delivered_quantity,a.restored_quantity,a.released_at,
 o.created_at as order_created_at,o.updated_at as order_updated_at,b.cancelled_at,b.cancelled_by,b.cancellation_reason,
 aa.stock as current_stock,prev.payload->>'stock' as previous_snapshot_stock,
 (select count(*) from checkout_orders x where x.id<>o.id and x.arena_id=o.arena_id and x.fulfillment_status in('fulfilled','refund_required') and tstzrange(x.starts_at,x.ends_at,'[)')&&tstzrange(o.starts_at,o.ends_at,'[)')) as overlapping_fulfilled_orders,
 (select count(*) from notifications n where n.type='booking_cancellation' and n.data->>'booking_id'=b.id::text) as cancellation_notifications,
 arena_private.addon_available(a.arena_addon_id,o.starts_at,o.ends_at) as currently_available_for_interval
from arena_private.refund_policy_backup_20261009 s join booking_addons a on a.id::text=s.row_key
join checkout_orders o on o.id=a.order_id left join bookings b on b.id=o.booking_id join arena_addons aa on aa.id=a.arena_addon_id
left join arena_private.refund_policy_backup_20261009 prev on prev.kind='arena_addons' and prev.row_key=a.arena_addon_id::text
where s.kind='booking_addons' order by a.order_id,a.kind) x),'tracking_columns',(select jsonb_agg(to_jsonb(x)) from (select table_name,column_name from information_schema.columns where table_schema='public' and table_name='booking_addons' and column_name ~ '(created|updated|deliver|restore|track|debit|release)' order by column_name) x)) as investigation;
