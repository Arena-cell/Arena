-- Deploy/test image-upload and update the clients as one approved rollout.
-- Older clients' direct uploads will be rejected. Existing files stay intact.
begin;
update storage.buckets set allowed_mime_types=array['image/jpeg','image/png','image/webp'],
 file_size_limit=case id when 'avatars' then 3145728 when 'chat-images' then 5242880 when 'stadium-images' then 10485760 end
where id in('avatars','chat-images','stadium-images');
-- MIME filtering alone cannot validate image bytes. Every untrusted upload
-- must pass the authenticated decoder/re-encoder; service_role alone writes.
create policy "validated image insert only" on storage.objects as restrictive for insert to authenticated
with check(bucket_id not in('avatars','chat-images','stadium-images'));
create policy "validated image update only" on storage.objects as restrictive for update to authenticated
using(bucket_id not in('avatars','chat-images','stadium-images'))
with check(bucket_id not in('avatars','chat-images','stadium-images'));
commit;
