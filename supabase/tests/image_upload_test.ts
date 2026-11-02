import { handleImageUpload, type ImageUploadPort } from '../functions/_shared/image_upload.ts';
import { ImageRejected, imageLimits, validateAndOptimizeImage } from '../functions/_shared/validated_image.ts';
function assert(value: unknown): asserts value { if (!value) throw new Error('Assertion failed'); }
const fixture = (name: string) => Deno.readFile(new URL(`./fixtures/security-images/${name}`, import.meta.url));
async function rejected(bytes: Uint8Array, code?: string) {
  try { await validateAndOptimizeImage(bytes, 'avatars'); } catch (error) { assert(error instanceof ImageRejected); if (code) assert(error.code === code); return; }
  throw new Error('Invalid image accepted');
}
for (const name of ['valid.png', 'valid.jpg', 'valid.webp']) Deno.test(`fully decode and re-encode ${name}; strip metadata`, async () => {
  const output = await validateAndOptimizeImage(await fixture(name), 'avatars');
  assert(new TextDecoder().decode(output.subarray(8, 12)) === 'WEBP');
  assert(!new TextDecoder().decode(output).includes('LOCAL_PRIVATE_METADATA'));
});
Deno.test('reject HTML spoofed as JPEG', async () => rejected(new TextEncoder().encode('<html><script>bad()</script></html>'), 'IMAGE_TYPE_NOT_ALLOWED'));
Deno.test('reject SVG even if named png', async () => rejected(new TextEncoder().encode('<svg xmlns="http://www.w3.org/2000/svg"/>'), 'IMAGE_TYPE_NOT_ALLOWED'));
Deno.test('reject a correct PNG signature with invalid image structure', async () => rejected(new Uint8Array([137,80,78,71,13,10,26,10,0,0,0,0]), 'INVALID_IMAGE'));
Deno.test('reject truncated JPEG structure', async () => rejected(new Uint8Array([255,216,255,0,0,0]), 'INVALID_IMAGE'));
Deno.test('reject excessive dimension header before acceptance', async () => rejected(await fixture('excessive-dimensions.png')));
Deno.test('reject over-limit input before decode', async () => rejected(new Uint8Array(imageLimits.avatars + 1), 'IMAGE_TOO_LARGE'));
Deno.test('polyglot trailing active payload is absent from canonical output', async () => {
  const jpeg = await fixture('valid.jpg'), extra = new TextEncoder().encode('<script>LOCAL_ACTIVE_PAYLOAD</script>');
  const mixed = new Uint8Array(jpeg.length + extra.length); mixed.set(jpeg); mixed.set(extra,jpeg.length);
  const output = await validateAndOptimizeImage(mixed, 'avatars'); assert(!new TextDecoder().decode(output).includes('LOCAL_ACTIVE_PAYLOAD'));
});
const config = { url: 'https://gtcrijikfaglqcwqozel.supabase.co', origins: ['http://localhost:5181'] };
function portFixture() {
  const saved: Uint8Array[] = [], paths: string[] = [];
  const port: ImageUploadPort = {
    user: async () => '10000000-0000-4000-8000-000000000001', manageArena: async () => true,
    store: async (_bucket, path, bytes) => { saved.push(bytes); paths.push(path); },
    publicUrl: (_bucket,path) => `https://example.invalid/public/${path}`,
  }; return { port, saved, paths };
}
function req(bytes: Uint8Array, bucket = 'avatars', token = true, arena?: string) {
  return new Request('http://local/upload', { method: 'POST', headers: {
    'x-arena-image-bucket': bucket, 'Content-Type': 'image/jpeg',
    ...(token ? { Authorization: 'Bearer LOCAL_TEST_ONLY' } : {}), ...(arena ? { 'x-arena-id': arena } : {}),
  }, body: new Uint8Array(bytes) });
}
Deno.test('anonymous upload denied before storage', async () => { const { port,saved } = portFixture(); assert((await handleImageUpload(req(await fixture('valid.png'),'avatars',false),config,port)).status === 401); assert(saved.length === 0); });
Deno.test('invalid JWT upload rejected', async () => { const { port,saved } = portFixture(); port.user = async () => null; assert((await handleImageUpload(req(await fixture('valid.png')),config,port)).status === 401); assert(saved.length === 0); });
Deno.test('valid user upload stores only canonical bytes under its own generated path', async () => {
  const { port,saved,paths } = portFixture(); const response = await handleImageUpload(req(await fixture('valid.png')),config,port);
  assert(response.status === 200); assert(saved.length === 1); assert(paths[0].startsWith('10000000-0000-4000-8000-000000000001/')); assert(paths[0].endsWith('.webp'));
  assert(new TextDecoder().decode(saved[0].subarray(8,12)) === 'WEBP');
});
Deno.test('private chat upload never returns a public URL', async () => {
  const { port } = portFixture(); const response = await handleImageUpload(req(await fixture('valid.png'),'chat-images'),config,port);
  assert(response.status === 200); const body = await response.json(); assert(!('publicUrl' in body)); assert(body.reference.startsWith('chat-images/'));
});
Deno.test('cannot upload arena image without actual arena authorization', async () => {
  const { port,saved } = portFixture(); port.manageArena = async () => false;
  assert((await handleImageUpload(req(await fixture('valid.png'),'stadium-images',true,'10000000-0000-4000-8000-000000000099'),config,port)).status === 403); assert(saved.length === 0);
});
Deno.test('authorized arena upload succeeds', async () => {
  const { port,paths } = portFixture(); const response = await handleImageUpload(req(await fixture('valid.png'),'stadium-images',true,'10000000-0000-4000-8000-000000000099'),config,port);
  assert(response.status === 200); assert(paths[0].includes('/10000000-0000-4000-8000-000000000099/'));
});
Deno.test('MIME spoof cannot reach storage', async () => { const { port,saved } = portFixture(); assert((await handleImageUpload(req(new TextEncoder().encode('<html>bad</html>')),config,port)).status === 400); assert(saved.length === 0); });
Deno.test('stream limit cannot be bypassed with Content-Length', async () => { const { port,saved } = portFixture(); const request = req(new Uint8Array(imageLimits.avatars + 1)); request.headers.set('Content-Length','1'); assert((await handleImageUpload(request,config,port)).status === 413); assert(saved.length === 0); });
Deno.test('invalid bucket denied', async () => { const { port } = portFixture(); assert((await handleImageUpload(req(new Uint8Array(),'private-secrets'),config,port)).status === 400); });
Deno.test('non-staging target fails closed', async () => { const { port,saved } = portFixture(); assert((await handleImageUpload(req(new Uint8Array()),{...config,url:'https://other.invalid'},port)).status === 503); assert(saved.length === 0); });
Deno.test('unapproved browser origin denied', async () => { const { port } = portFixture(); const request=req(new Uint8Array()); request.headers.set('origin','https://evil.invalid'); assert((await handleImageUpload(request,config,port)).status === 403); });
for (const [bucket, limit] of Object.entries(imageLimits)) {
  Deno.test(`${bucket} enforces its exact stream limit`, async () => {
    const { port,saved } = portFixture();
    const arena = bucket === 'stadium-images' ? '10000000-0000-4000-8000-000000000099' : undefined;
    assert((await handleImageUpload(req(new Uint8Array(limit + 1),bucket,true,arena),config,port)).status === 413);
    assert(saved.length === 0);
  });
}
Deno.test('invalid WebP structure cannot pass its signature alone', async () => rejected(new TextEncoder().encode('RIFF0000WEBP0000000000000000000000'),'INVALID_IMAGE'));
Deno.test('storage failure never reports upload success', async () => {
  const { port } = portFixture(); port.store = async () => { throw new Error('PRIVATE_BACKEND_FAILURE'); };
  const response = await handleImageUpload(req(await fixture('valid.png')),config,port);
  assert(response.status === 503); assert(!(await response.text()).includes('PRIVATE_BACKEND_FAILURE'));
});
