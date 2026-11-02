begin;

create function arena_private.social_pair_lock(a uuid,b uuid) returns void
language sql volatile set search_path=pg_catalog as $$
 select pg_advisory_xact_lock(hashtextextended('social:'||least(a,b)::text||':'||greatest(a,b)::text,0));
$$;
revoke all on function arena_private.social_pair_lock(uuid,uuid) from public,anon,authenticated;

create function arena_private.social_pair_blocked(a uuid,b uuid) returns boolean
language sql volatile security definer set search_path=pg_catalog,public as $$
 select exists(select 1 from public.user_blocks
 where (blocker_id=a and blocked_id=b) or (blocker_id=b and blocked_id=a));
$$;
revoke all on function arena_private.social_pair_blocked(uuid,uuid) from public,anon,authenticated;

create function arena_private.lock_block_pair() returns trigger
language plpgsql security definer set search_path=pg_catalog,arena_private as $$
begin
 if TG_OP='DELETE' then
   perform arena_private.social_pair_lock(old.blocker_id,old.blocked_id); return old;
 end if;
 if TG_OP='UPDATE' and (new.blocker_id,new.blocked_id,new.created_at)
   is distinct from (old.blocker_id,old.blocked_id,old.created_at) then
   raise exception 'BLOCK_IDENTITY_IMMUTABLE' using errcode='42501';
 end if;
 perform arena_private.social_pair_lock(new.blocker_id,new.blocked_id); return new;
end $$;
revoke all on function arena_private.lock_block_pair() from public,anon,authenticated;
create trigger security_lock_block_pair before insert or update or delete on public.user_blocks
for each row execute function arena_private.lock_block_pair();

create function arena_private.guard_direct_message() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,arena_private as $$
begin
 if TG_OP='UPDATE' then
   if (to_jsonb(new)-'read_at') is distinct from (to_jsonb(old)-'read_at') then
     raise exception 'MESSAGE_IMMUTABLE' using errcode='42501';
   end if;
   if auth.uid() is distinct from old.receiver_id then
     raise exception 'MESSAGE_RECIPIENT_REQUIRED' using errcode='42501';
   end if;
   new.read_at:=coalesce(old.read_at,clock_timestamp());
 else
   perform arena_private.social_pair_lock(new.sender_id,new.receiver_id);
   if arena_private.social_pair_blocked(new.sender_id,new.receiver_id) then
     raise exception 'CONTACT_BLOCKED' using errcode='42501';
   end if;
   new.read_at:=null;
   new.created_at:=clock_timestamp();
 end if;
 return new;
end $$;
revoke all on function arena_private.guard_direct_message() from public,anon,authenticated;
create trigger security_guard_direct_message before insert or update on public.direct_messages
for each row execute function arena_private.guard_direct_message();
drop policy "message participants only" on public.direct_messages;
revoke all on public.direct_messages from public,anon,authenticated;
grant select,insert on public.direct_messages to authenticated;
grant update(read_at) on public.direct_messages to authenticated;
create policy "direct participants read" on public.direct_messages for select to authenticated
using(auth.uid() in (sender_id,receiver_id));
create policy "direct sender inserts" on public.direct_messages for insert to authenticated
with check(sender_id=auth.uid());
create policy "direct recipient marks read" on public.direct_messages for update to authenticated
using(receiver_id=auth.uid()) with check(receiver_id=auth.uid());

create function arena_private.guard_friend_request() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,arena_private as $$
begin
 perform arena_private.social_pair_lock(new.sender_id,new.receiver_id);
 if TG_OP='INSERT' then
   if new.sender_id is distinct from auth.uid() or new.status<>'pending' then
     raise exception 'FRIEND_PENDING_SENDER_REQUIRED' using errcode='42501';
   end if;
   new.created_at:=clock_timestamp();
 else
   if (new.sender_id,new.receiver_id,new.created_at) is distinct from
      (old.sender_id,old.receiver_id,old.created_at) then
     raise exception 'FRIEND_IDENTITY_IMMUTABLE' using errcode='42501';
   end if;
   if new.status='pending' then
     if auth.uid() is distinct from old.sender_id or old.status='accepted' then
       raise exception 'FRIEND_PENDING_SENDER_REQUIRED' using errcode='42501';
     end if;
   elsif auth.uid() is distinct from old.receiver_id or old.status<>'pending' then
     raise exception 'FRIEND_RECIPIENT_REQUIRED' using errcode='42501';
   end if;
 end if;
 if new.status in ('pending','accepted') and
    arena_private.social_pair_blocked(new.sender_id,new.receiver_id) then
   raise exception 'CONTACT_BLOCKED' using errcode='42501';
 end if;
 return new;
end $$;
revoke all on function arena_private.guard_friend_request() from public,anon,authenticated;
create trigger security_guard_friend_request before insert or update on public.friend_requests
for each row execute function arena_private.guard_friend_request();
drop policy "friend request participants" on public.friend_requests;
revoke all on public.friend_requests from public,anon,authenticated;
grant select,insert,delete on public.friend_requests to authenticated;
grant update(status) on public.friend_requests to authenticated;
create policy "friend participants read" on public.friend_requests for select to authenticated
using(auth.uid() in(sender_id,receiver_id));
create policy "friend sender requests" on public.friend_requests for insert to authenticated
with check(sender_id=auth.uid() and status='pending');
create policy "friend participants update" on public.friend_requests for update to authenticated
using(auth.uid() in(sender_id,receiver_id)) with check(auth.uid() in(sender_id,receiver_id));
create policy "friend participants remove" on public.friend_requests for delete to authenticated
using(auth.uid() in(sender_id,receiver_id));
create function public.respond_friend_request(p_sender uuid,p_accept boolean) returns void
language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
 if auth.uid() is null or p_accept is null then raise exception 'NOT_AUTHORIZED' using errcode='42501'; end if;
 update public.friend_requests set status=case when p_accept then 'accepted' else 'declined' end
 where sender_id=p_sender and receiver_id=auth.uid() and status='pending';
 if not found then raise exception 'PENDING_REQUEST_NOT_FOUND' using errcode='42501'; end if;
end $$;
revoke all on function public.respond_friend_request(uuid,boolean) from public,anon;
grant execute on function public.respond_friend_request(uuid,boolean) to authenticated;
-- PostgREST upsert updates every supplied column, including immutable parties.
-- Keep legitimate retries/resubmission without granting party UPDATE rights.
create function public.request_friendship(p_receiver uuid) returns text
language plpgsql security invoker set search_path=pg_catalog,public as $$
declare result text;
begin
 if auth.uid() is null or p_receiver is null or p_receiver=auth.uid() then
   raise exception 'INVALID_FRIEND_REQUEST' using errcode='42501';end if;
 insert into public.friend_requests(sender_id,receiver_id,status)
 values(auth.uid(),p_receiver,'pending') on conflict(sender_id,receiver_id) do nothing;
 select status into result from public.friend_requests where sender_id=auth.uid() and receiver_id=p_receiver;
 if result='declined' then
   update public.friend_requests set status='pending' where sender_id=auth.uid() and receiver_id=p_receiver;
   result:='pending';
 end if;
 return result;
end $$;
revoke all on function public.request_friendship(uuid) from public,anon;
grant execute on function public.request_friendship(uuid) to authenticated;
revoke truncate,references,trigger on public.user_blocks from public,anon,authenticated;

-- Keep old objects and message rows. Resolve the existing public URL to its
-- object name; only the storage access mode changes, never message history.
create function arena_private.chat_image_path(ref text) returns text
language sql immutable set search_path=pg_catalog as $$
 select case
 when ref like 'chat-images/%' then substr(ref,13)
 when ref like 'https://gtcrijikfaglqcwqozel.supabase.co/storage/v1/object/public/chat-images/%'
 then substr(ref,length('https://gtcrijikfaglqcwqozel.supabase.co/storage/v1/object/public/chat-images/')+1)
 else null end;
$$;
revoke all on function arena_private.chat_image_path(text) from public,anon,authenticated;
create function public.can_read_chat_image(p_name text) returns boolean
language sql stable security definer set search_path=pg_catalog,public,arena_private as $$
 select auth.uid() is not null and (
 -- Uploader can inspect an upload before sending it.
 split_part(p_name,'/',1)=auth.uid()::text
 or exists(select 1 from public.direct_messages d
   where auth.uid() in(d.sender_id,d.receiver_id)
   and arena_private.chat_image_path(d.image_url)=p_name)
 or exists(select 1 from public.group_messages g
   where public.is_chat_group_member(g.group_id)
   and arena_private.chat_image_path(g.image_url)=p_name));
$$;
revoke all on function public.can_read_chat_image(text) from public,anon;
grant execute on function public.can_read_chat_image(text) to authenticated;

-- Prevent attaching somebody else's private object to a new message in order
-- to gain access. Old message references remain intact.
create function arena_private.guard_chat_attachment() returns trigger
language plpgsql security definer set search_path=pg_catalog,public,arena_private as $$
declare object_name text;
begin
 if new.image_url is null then return new; end if;
 object_name:=arena_private.chat_image_path(new.image_url);
 if object_name is null or split_part(object_name,'/',1)<>new.sender_id::text
    or not exists(select 1 from storage.objects where bucket_id='chat-images' and name=object_name) then
   raise exception 'INVALID_CHAT_ATTACHMENT' using errcode='42501';
 end if;
 return new;
end $$;
revoke all on function arena_private.guard_chat_attachment() from public,anon,authenticated;
create trigger security_guard_direct_attachment before insert on public.direct_messages
for each row execute function arena_private.guard_chat_attachment();
create trigger security_guard_group_attachment before insert on public.group_messages
for each row execute function arena_private.guard_chat_attachment();
update storage.buckets set public=false where id='chat-images';
drop policy "chat images publicly readable" on storage.objects;
create policy "chat images participants read" on storage.objects for select to authenticated
using(bucket_id='chat-images' and public.can_read_chat_image(name));
commit;
