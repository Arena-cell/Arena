-- Allow arena pricing updates when owner manual bookings have no user.
begin;
create or replace function public.notify_arena_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (to_jsonb(new) - 'rating' - 'review_count') is not distinct from
     (to_jsonb(old) - 'rating' - 'review_count') then
    return new;
  end if;
  insert into public.notifications(
    user_id, type, title, body, title_ar, title_en, body_ar, body_en, data, event_key
  )
  select distinct b.user_id, 'stadium_update', 'Arena details updated',
    'Details for an arena in your upcoming bookings changed.',
    'تم تحديث بيانات الملعب', 'Arena details updated',
    'تغيّرت بيانات ملعب ضمن حجوزاتك القادمة.',
    'Details for an arena in your upcoming bookings changed.',
    jsonb_build_object('arena_id', new.id, 'booking_id', b.id),
    'stadium-update:' || b.id::text || ':' || txid_current()::text
  from public.bookings b
  where b.user_id is not null and b.arena_id = new.id and b.status <> 'cancelled' and b.ends_at > now()
  on conflict (user_id, event_key) where event_key is not null do nothing;
  return new;
end;
$$;
commit;
