begin;
alter table device_tokens add column is_active boolean not null default true;
alter table notifications add column lease_id uuid;
alter table notifications add column lease_until timestamptz;
alter table notification_push_deliveries add column next_attempt_at timestamptz not null default now();
alter table notification_push_deliveries add column lease_until timestamptz;
create function public.claim_arena_push_batch(p_limit integer default 20)
returns setof public.notifications language plpgsql security definer set search_path=public as $$ begin
 update notifications set delivery_status='exhausted',lease_id=null,lease_until=null
 where delivery_status='sending' and lease_until<=clock_timestamp() and attempt_count>=8;
 return query with candidates as (
  select id from notifications where due_at<=clock_timestamp() and attempt_count<8 and (
   (delivery_status in('pending','failed') and next_attempt_at<=clock_timestamp()) or
   (delivery_status='sending' and lease_until<=clock_timestamp()))
  order by due_at,id limit least(greatest(p_limit,1),50) for update skip locked)
 update notifications n set delivery_status='sending',lease_id=gen_random_uuid(),
  lease_until=clock_timestamp()+interval '2 minutes',attempt_count=n.attempt_count+1
 from candidates c where n.id=c.id returning n.*;
end $$;
create function public.finish_arena_push(p_notification uuid,p_lease uuid,p_status text) returns void
language plpgsql security definer set search_path=public as $$ begin
 if p_status not in('sent','failed','no_device') then raise exception 'INVALID_DELIVERY_STATUS';end if;
 update notifications set delivery_status=case when p_status='failed' and attempt_count>=8 then 'exhausted' else p_status end,
  next_attempt_at=clock_timestamp()+make_interval(secs=>least(3600,30*(2^least(attempt_count,7))::integer)),
  lease_until=null,lease_id=null where id=p_notification and lease_id=p_lease;
end $$;
create or replace function public.claim_notification_push_delivery(p_notification_id uuid,p_device_token_id uuid)
returns table(delivery_id uuid,delivery_attempt_count integer)
language plpgsql security definer set search_path=public as $$ begin
 -- A token must belong to this notification recipient, even for internal callers.
 if not exists(select 1 from device_tokens t join notifications n on n.user_id=t.user_id
   where t.id=p_device_token_id and t.is_active and n.id=p_notification_id) then raise exception 'TOKEN_RECIPIENT_MISMATCH';end if;
 return query insert into notification_push_deliveries as d(notification_id,device_token_id,status,attempt_count,updated_at,lease_until)
 values(p_notification_id,p_device_token_id,'sending',1,clock_timestamp(),clock_timestamp()+interval '90 seconds')
 on conflict(notification_id,device_token_id) do update set status='sending',attempt_count=d.attempt_count+1,
  updated_at=clock_timestamp(),lease_until=clock_timestamp()+interval '90 seconds',last_error_code=null
 where d.attempt_count<8 and ((d.status in('pending','failed') and d.next_attempt_at<=clock_timestamp())
   or (d.status='sending' and d.lease_until<=clock_timestamp()))
 returning d.id,d.attempt_count;
end $$;
create function public.admin_retry_arena_notification(p_notification uuid) returns void
language plpgsql security definer set search_path=public as $$ begin
 if not is_platform_admin() then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 update notifications set delivery_status='pending',next_attempt_at=clock_timestamp(),attempt_count=0
 where id=p_notification and delivery_status in('failed','exhausted','no_device');
 update notification_push_deliveries set status='pending',next_attempt_at=clock_timestamp(),attempt_count=0
 where notification_id=p_notification and (status='failed' or (status='sending' and lease_until<=clock_timestamp()));
end $$;
create function public.phase3_new_device() returns trigger
language plpgsql security definer set search_path=public as $$ begin
 update notifications set delivery_status='pending',next_attempt_at=clock_timestamp()
 where user_id=new.user_id and delivery_status='no_device' and due_at>now()-interval '1 day';
 return new;
end $$;
create trigger phase3_new_device after insert or update on device_tokens for each row execute function phase3_new_device();
revoke all on notification_push_deliveries from anon,authenticated;
grant select on notification_push_deliveries to authenticated;
grant select,update on notifications to service_role;
grant select,insert,update on notification_push_deliveries to service_role;
grant select,update on device_tokens to service_role;
revoke all on function public.claim_arena_push_batch(integer),public.finish_arena_push(uuid,uuid,text),
 public.claim_notification_push_delivery(uuid,uuid),public.admin_retry_arena_notification(uuid),public.phase3_new_device() from public,anon,authenticated;
grant execute on function public.claim_arena_push_batch(integer),public.finish_arena_push(uuid,uuid,text),public.claim_notification_push_delivery(uuid,uuid) to service_role;
grant execute on function public.admin_retry_arena_notification(uuid) to authenticated;
commit;
