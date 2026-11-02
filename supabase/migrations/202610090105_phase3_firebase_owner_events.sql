-- Extend the existing inbox; no booking, inventory or financial mutations.
begin;
create function public.phase3_owner_notification() returns trigger
language plpgsql security definer set search_path=public as $$
declare arena uuid; u uuid; entity text; payload jsonb;
begin
 if new.data->>'audience'='owner' then return new;end if;
 if new.type not in('booking_confirmation','booking_cancellation','booking_status',
   'match_confirmed','match_cancelled','payment_confirmed','refund_pending','refund_completed','stadium_update') then return new;end if;
 if nullif(new.data->>'booking_id','') is not null then
  select arena_id into arena from bookings where id::text=new.data->>'booking_id';
 elsif nullif(new.data->>'match_id','') is not null then
  select arena_id into arena from matches where id::text=new.data->>'match_id';
 elsif nullif(new.data->>'order_id','') is not null then
  select arena_id into arena from checkout_orders where id::text=new.data->>'order_id';
 else
  select id into arena from arenas where id::text=new.data->>'arena_id';
 end if;
 if arena is null then return new;end if;
 entity:=coalesce(new.data->>'match_id',new.data->>'booking_id',new.data->>'order_id',new.data->>'arena_id',new.id::text);
 payload:=coalesce(new.data,'{}'::jsonb)||jsonb_build_object('arena_id',arena,'audience','owner');
 -- Re-evaluate existing ownership/assignment and disabled staff restrictions.
 for u in select owner_id from arenas where id=arena and owner_id is not null
   union select user_id from owner_stadium_assignments where stadium_id=arena loop
  if u<>new.user_id and public.is_stadium_owner_of(arena,u) then
   perform arena_private.notify(u,new.type,'owner:'||coalesce(new.event_key,new.type||':'||entity),payload,
     'Your arena has an update. Open Arena Owner to review it.',
     'يوجد تحديث لملعبك. افتح تطبيق المالك للاطلاع عليه.');
  end if;
 end loop;
 return new;
end $$;
create trigger phase3_owner_notification after insert on public.notifications
 for each row execute function public.phase3_owner_notification();
revoke all on function public.phase3_owner_notification() from public,anon,authenticated;
commit;
