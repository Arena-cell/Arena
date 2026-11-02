import { imageLimits, ImageRejected, type ImageBucket, validateAndOptimizeImage } from './validated_image.ts';

export interface ImageUploadPort {
  user(token: string): Promise<string | null>;
  manageArena(token: string, path: string): Promise<boolean>;
  store(bucket: ImageBucket, path: string, bytes: Uint8Array): Promise<void>;
  publicUrl(bucket: ImageBucket, path: string): string;
}
export async function handleImageUpload(request: Request, config: { url: string; origins: string[] }, port: ImageUploadPort): Promise<Response> {
  const origin = request.headers.get('origin');
  const headers: Record<string,string> = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', Vary: 'Origin' };
  if (origin && config.origins.includes(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
    headers['Access-Control-Allow-Headers'] = 'authorization,apikey,content-type,x-client-info,x-arena-image-bucket,x-arena-id,x-arena-owner-unlock';
    headers['Access-Control-Allow-Methods'] = 'POST,OPTIONS';
  }
  const reply = (status: number, body: Record<string,unknown>) => new Response(JSON.stringify(body), { status, headers });
  if (origin && !config.origins.includes(origin)) return reply(403, { error: 'ORIGIN_NOT_ALLOWED' });
  if (request.method === 'OPTIONS') return reply(200, {});
  if (request.method !== 'POST') return reply(405, { error: 'METHOD_NOT_ALLOWED' });
  if (config.url !== 'https://gtcrijikfaglqcwqozel.supabase.co') return reply(503, { error: 'STAGING_ONLY' });
  const token = request.headers.get('authorization')?.match(/^Bearer (\S+)$/)?.[1];
  if (!token) return reply(401, { error: 'UNAUTHORIZED' });
  const bucket = request.headers.get('x-arena-image-bucket') as ImageBucket;
  if (!Object.hasOwn(imageLimits, bucket)) return reply(400, { error: 'INVALID_BUCKET' });
  try {
    const user = await port.user(token);
    if (!user) return reply(401, { error: 'UNAUTHORIZED' });
    let path = `${user}/${crypto.randomUUID()}.webp`;
    if (bucket === 'stadium-images') {
      const arena = request.headers.get('x-arena-id');
      if (!arena || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(arena)) return reply(400, { error: 'INVALID_ARENA' });
      path = `${user}/${arena}/${crypto.randomUUID()}.webp`;
      if (!await port.manageArena(token, path)) return reply(403, { error: 'IMAGE_UPLOAD_NOT_AUTHORIZED' });
    }
    // Never trust Content-Length, MIME or a filename. Bound the stream itself.
    const reader = request.body?.getReader();
    if (!reader) return reply(400, { error: 'INVALID_IMAGE' });
    const parts: Uint8Array[] = []; let size = 0;
    while (true) {
      const chunk = await reader.read(); if (chunk.done) break;
      size += chunk.value.length;
      if (size > imageLimits[bucket]) { await reader.cancel(); return reply(413, { error: 'IMAGE_TOO_LARGE' }); }
      parts.push(chunk.value);
    }
    const input = new Uint8Array(size); let offset = 0;
    for (const part of parts) { input.set(part, offset); offset += part.length; }
    const bytes = await validateAndOptimizeImage(input, bucket);
    await port.store(bucket, path, bytes);
    return reply(200, { path, reference: `${bucket}/${path}`, mime: 'image/webp', bytes: bytes.length,
      ...(bucket === 'chat-images' ? {} : { publicUrl: port.publicUrl(bucket, path) }) });
  } catch (error) {
    return error instanceof ImageRejected ? reply(error.status, { error: error.code }) : reply(503, { error: 'IMAGE_UPLOAD_UNAVAILABLE' });
  }
}
