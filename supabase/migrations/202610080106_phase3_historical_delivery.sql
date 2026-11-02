-- Distinguish historical inbox entries from provider-confirmed push deliveries.
begin;
alter table notifications drop constraint notifications_delivery_status_check;
alter table notifications add constraint notifications_delivery_status_check
 check(delivery_status in('historical','pending','sending','sent','failed','no_device','exhausted'));
-- Only rows present in the pre-Phase-3 snapshot; no new delivered event is relabelled.
do $$ begin
 if to_regclass('arena_private.phase3_backup_20261008') is not null then
  update public.notifications set delivery_status='historical'
  where delivery_status='sent' and attempt_count=0 and id in(
   select (record->>'id')::uuid from arena_private.phase3_backup_20261008 where object_name='notifications');
 end if;
end $$;
commit;
