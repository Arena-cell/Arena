-- STAGING ONLY: gtcrijikfaglqcwqozel. Never include in production migrations.
-- Deployment prerequisite: verify the Dashboard project reference manually.
-- Supabase handles unexpired Test Phone OTP mappings BEFORE invoking this hook.
-- Every other SMS request fails closed; no SMS is sent and no OTP is logged.
-- This does not enable Phone Auth or configure test credentials by itself.
begin;
do $$
begin
  if (select count(*) from arena_private.staging_installation
      where version in ('202609290001','202609290002','202609290003')) <> 3 then
    raise exception 'Expected Phase 1 staging installation receipts';
  end if;
end $$;

create or replace function public.staging_deny_real_sms(event jsonb)
returns jsonb language sql set search_path = '' as $$
  select '{"error":{"http_code":403,"message":"Staging permits configured, unexpired Test Phone OTPs only. Real SMS is disabled."}}'::jsonb;
$$;
revoke all on function public.staging_deny_real_sms(jsonb)
  from public, anon, authenticated;
grant usage on schema public to supabase_auth_admin;
grant execute on function public.staging_deny_real_sms(jsonb)
  to supabase_auth_admin;
commit;

-- Dashboard > Authentication > Auth Hooks > Add hook > Send SMS hook
-- Postgres / public / staging_deny_real_sms. Keep Phone confirmation enabled.
-- Then configure Phone + fixed test mappings + a short expiry in the Dashboard.
-- Verify both an actual test-number session and rejection of non-test numbers.
