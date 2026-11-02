select jsonb_build_object(
 'fixtures',(select jsonb_agg(jsonb_build_object('id',m.id,'status',m.status,'outcome',m.decision_outcome,'confirmed_count',m.decision_joined_count,'reason',m.cancellation_reason,'court_reserved',exists(select 1 from court_reservations r where r.source_id=m.id))) from matches m where m.id::text like 'f3000000-%'),
 'reminders',(select count(*) from notifications where data->>'match_id'='f3000000-0000-4000-8000-000000000001' and type='match_reminder'),
 'decision_notifications',(select count(*) from notifications where data->>'match_id' like 'f3000000-%' and type in('match_confirmed','match_cancelled')),
 'recent_jobs',(select jsonb_agg(to_jsonb(j)) from (select outcome,decision_count,reminder_count,last_error,processed_at from arena_scheduled_job_runs order by started_at desc limit 3)j),
 'cron_success',(select count(*) from cron.job_run_details where jobid=1 and status='succeeded'),
 'job_active',(select active from cron.job where jobname='arena-phase3-decisions-reminders'),
 'inventory_conflicts',(select count(*) from inventory_migration_issues where resolved_at is null),
 'original_bookings',(select count(*) from bookings),
 'captured_payments',(select count(*) from checkout_orders where payment_status in('paid','partially_refunded'))
) as scheduled_verification;
