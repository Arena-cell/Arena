-- READ ONLY. Run against the explicitly verified Staging project before any
-- approved deployment. Does not inspect image bytes or return private content.
select jsonb_build_object(
 'database',current_database(),
 'public_profile_write_grants',(select jsonb_agg(jsonb_build_object('role',grantee,'privilege',privilege_type)) from information_schema.role_table_grants where table_schema='public' and table_name='public_profiles' and grantee in('PUBLIC','anon','authenticated') and privilege_type<>'SELECT'),
 'public_profile_column_write_grants',(select jsonb_agg(to_jsonb(g)) from information_schema.column_privileges g where table_schema='public' and table_name='public_profiles' and grantee in('PUBLIC','anon','authenticated') and privilege_type<>'SELECT'),
 'buckets',(select jsonb_agg(jsonb_build_object('id',id,'public',public,'limit',file_size_limit,'mime',allowed_mime_types)) from storage.buckets where id in('avatars','chat-images','stadium-images')),
 'chat_legacy_references',(select count(*) from public.direct_messages where image_url like 'https://gtcrijikfaglqcwqozel.supabase.co/storage/v1/object/public/chat-images/%'),
 'chat_unsupported_references',(select count(*) from public.direct_messages where image_url is not null and image_url not like 'chat-images/%' and image_url not like 'https://gtcrijikfaglqcwqozel.supabase.co/storage/v1/object/public/chat-images/%'),
 'group_unsupported_references',(select count(*) from public.group_messages where image_url is not null and image_url not like 'chat-images/%' and image_url not like 'https://gtcrijikfaglqcwqozel.supabase.co/storage/v1/object/public/chat-images/%'),
 'existing_accepted_friendships',(select count(*) from public.friend_requests where status='accepted'),
 'totp_table_available',to_regclass('auth.mfa_factors') is not null,
 'old_image_upload_helper_executable',has_function_privilege('authenticated','public.can_manage_stadium_image(text)','execute')
) as security_preflight;
-- Any unsupported reference or unexpected policy/ACL must be reviewed before
-- making chat-images private. Old cached/downloaded public images cannot be
-- retroactively recalled; no automatic deletion or history rewrite is done.
