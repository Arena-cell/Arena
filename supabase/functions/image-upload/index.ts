import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.110.5';
import { handleImageUpload, type ImageUploadPort } from '../_shared/image_upload.ts';

Deno.serve((request: Request) => {
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const publicKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  let server: SupabaseClient | undefined;
  const admin = () => {
    if (url !== 'https://gtcrijikfaglqcwqozel.supabase.co' || !secret) throw new Error('NOT_CONFIGURED');
    return server ??= createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });
  };
  const port: ImageUploadPort = {
    async user(token) { const { data, error } = await admin().auth.getUser(token); return error ? null : data.user?.id ?? null; },
    async manageArena(token, path) {
      const unlock = request.headers.get('x-arena-owner-unlock');
      const client = createClient(url, publicKey, { global: { headers: { Authorization: `Bearer ${token}`, ...(unlock ? { 'x-arena-owner-unlock': unlock } : {}) } }, auth: { persistSession: false, autoRefreshToken: false } });
      const { data, error } = await client.rpc('can_manage_stadium_image', { p_object_name: path });
      return !error && data === true;
    },
    async store(bucket, path, bytes) {
      const { error } = await admin().storage.from(bucket).upload(path, bytes, { contentType: 'image/webp', cacheControl: '60', upsert: false });
      if (error) throw error;
    },
    publicUrl(bucket, path) { return admin().storage.from(bucket).getPublicUrl(path).data.publicUrl; },
  };
  return handleImageUpload(request, { url, origins: (Deno.env.get('ARENA_IMAGE_UPLOAD_ORIGINS') ?? '').split(',').map(value => value.trim()).filter(Boolean) }, port);
});
