-- STAGING ONLY. Run after Phase 3 migrations and hosted verification.
-- Database scheduling is independent of FCM/Thawani credentials.
create extension if not exists pg_cron;
select cron.schedule('arena-phase3-decisions-reminders','5 seconds','select public.process_arena_scheduled_events();');
select jobid,jobname,schedule,active from cron.job where jobname='arena-phase3-decisions-reminders';
