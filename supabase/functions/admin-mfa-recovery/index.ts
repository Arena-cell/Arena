import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.110.5';
import { handleAdminRecovery, type RecoveryPort } from '../_shared/admin_mfa_recovery.ts';

// Deliberately disabled until enrollment/recovery acceptance and explicit
// approval. Gateway JWT verification remains enabled as well.
Deno.serve(async (request: Request) => {
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const publicKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const config = {
    enabled: Deno.env.get('ARENA_ADMIN_MFA_RECOVERY_ENABLED') === 'true',
    url,
    origin: Deno.env.get('ARENA_ADMIN_ORIGIN') ?? '',
  };
  let server: SupabaseClient | undefined;
  const admin = () => {
    if (url !== 'https://gtcrijikfaglqcwqozel.supabase.co' || !key) throw new Error('NOT_CONFIGURED');
    return server ??= createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  };
  const port: RecoveryPort = {
    async user(token) {
      const { data, error } = await admin().auth.getUser(token);
      return error ? null : data.user?.id ?? null;
    },
    async begin(token, code) {
      const user = createClient(url, publicKey, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false, autoRefreshToken: false } });
      const { data, error } = await user.rpc('begin_admin_mfa_recovery', { p_code: code });
      if (error) throw error;
      return data;
    },
    async factors(user, ticket) {
      const { data, error } = await admin().rpc('admin_mfa_recovery_factors', { p_user: user, p_ticket: ticket });
      if (error) throw error;
      return data;
    },
    async removeFactor(user, factor) {
      const { error } = await admin().auth.admin.mfa.deleteFactor({ userId: user, id: factor });
      // Retry safely when a preceding attempt already deleted this factor.
      if (error && error.code !== 'mfa_factor_not_found') throw error;
    },
    async revokeSessions(token) {
      const { error } = await admin().auth.admin.signOut(token, 'others');
      if (error) throw error;
    },
    async finish(user, ticket) {
      const { error } = await admin().rpc('finish_admin_mfa_recovery', { p_user: user, p_ticket: ticket });
      if (error) throw error;
    },
  };
  return handleAdminRecovery(request, config, port);
});
