-- READ ONLY. Dashboard project must be arena-staging / gtcrijikfaglqcwqozel.
select jsonb_build_object(
 'receipts',(select jsonb_agg(jsonb_build_object('version',version,'sha256',source_sha256)) from arena_private.staging_installation where version in ('202610090101','202610090102')),
 'backup_rows',(select count(*) from arena_private.refund_policy_backup_20261009),
 'original_bookings_retained',(select count(*) from arena_private.refund_policy_backup_20261009 s join bookings b on b.id::text=s.row_key where s.kind='bookings'),
 'original_booking_status_changes',(select jsonb_agg(jsonb_build_object('id',b.id,'before',s.payload->>'status','after',b.status,'start',b.starts_at,'end',b.ends_at)) from arena_private.refund_policy_backup_20261009 s join bookings b on b.id::text=s.row_key where s.kind='bookings' and b.status::text is distinct from s.payload->>'status'),
 'historical_addons_restored',(select count(*) from arena_private.refund_policy_backup_20261009 s join booking_addons a on a.id::text=s.row_key where s.kind='booking_addons' and a.restored_quantity<>0),
 'unknown_delivery',(select count(*) from booking_addons where delivered_quantity is null and stock_debited_quantity=0),
 'captured_payments',(select count(*) from checkout_orders where payment_status in ('paid','partially_refunded')),
 'refunds',(select count(*) from payment_refunds),
 'cancelled_policy_bookings',(select count(*) from bookings b join checkout_orders o on o.booking_id=b.id where b.status='cancelled' and o.cancellation_requested_at is not null),
 'cancelled_bookings_still_reserved',(select count(*) from court_reservations r join bookings b on b.id=r.source_id where b.status='cancelled'),
 'inventory_conflicts',(select count(*) from inventory_migration_issues where resolved_at is null),
 'water_stock',(select stock from arena_addons where arena_id='a1000000-0000-4000-8000-000000000002' and addon_code='water'),
 'scheduler_active',(select active from cron.job where jobname='arena-phase3-decisions-reminders'),
 'match_decisions',(select jsonb_agg(jsonb_build_object('status',status,'outcome',decision_outcome,'count',decision_joined_count)) from matches where id::text like 'f3000000-%')
) as verification;
