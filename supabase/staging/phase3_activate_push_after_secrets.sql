-- OPTIONAL MANUAL ACTIVATION, STAGING ONLY. Do NOT run until server secrets,
-- Firebase service account, gateway settings and authenticated invocation pass.
-- Put the SAME ARENA_SCHEDULER_SECRET value in Vault as arena_scheduler_secret.
-- No secret is embedded in this file or the stored cron command.
begin;
create extension if not exists pg_net;
do $$ begin
 if not exists(select 1 from vault.decrypted_secrets where name='arena_scheduler_secret'
  and nullif(decrypted_secret,'') is not null) then raise exception 'SCHEDULER_VAULT_SECRET_REQUIRED';end if;
end $$;
select cron.schedule('arena-phase3-push-dispatch','30 seconds',$job$
 select net.http_post(
  url:='https://gtcrijikfaglqcwqozel.supabase.co/functions/v1/arena-scheduler',
  headers:=jsonb_build_object('Content-Type','application/json','Authorization',
   'Bearer '||(select decrypted_secret from vault.decrypted_secrets where name='arena_scheduler_secret' limit 1)),
  body:='{}'::jsonb,timeout_milliseconds:=120000);
$job$);
commit;
select jobname,schedule,active from cron.job where jobname='arena-phase3-push-dispatch';
