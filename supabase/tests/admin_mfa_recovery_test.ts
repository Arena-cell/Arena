import { handleAdminRecovery, type RecoveryPort } from '../functions/_shared/admin_mfa_recovery.ts';
function assert(value: unknown) { if (!value) throw new Error('Assertion failed'); }
const config = { enabled: true, url: 'https://gtcrijikfaglqcwqozel.supabase.co', origin: 'http://localhost:5181' };
function request(code: unknown = 'ab'.repeat(16), token = true) {
  return new Request('http://local/recovery', { method: 'POST', headers: token ? { authorization: 'Bearer LOCAL_TEST_ONLY' } : {}, body: JSON.stringify({ code }) });
}
function fixture() {
  const calls: string[] = [];
  const port: RecoveryPort = {
    user: async () => 'LOCAL_USER',
    begin: async () => ({ ok: true, ticket: 'LOCAL_TEST_TICKET' }),
    factors: async () => ['LOCAL_FACTOR'],
    removeFactor: async (user, factor) => { calls.push(`remove:${user}:${factor}`); },
    revokeSessions: async () => { calls.push('revoke'); },
    finish: async () => { calls.push('finish'); },
  };
  return { port, calls };
}
Deno.test('recovery disabled by default', async () => {
  const { port, calls } = fixture(); assert((await handleAdminRecovery(request(), { ...config, enabled: false }, port)).status === 503); assert(calls.length === 0);
});
Deno.test('non-staging recovery fails closed', async () => {
  const { port, calls } = fixture(); assert((await handleAdminRecovery(request(), { ...config, url: 'https://other.example' }, port)).status === 503); assert(calls.length === 0);
});
Deno.test('unauthenticated recovery rejected', async () => { const { port } = fixture(); assert((await handleAdminRecovery(request(undefined, false), config, port)).status === 401); });
Deno.test('invalid JWT rejected before backup code', async () => { const { port, calls } = fixture(); port.user = async () => null; assert((await handleAdminRecovery(request(), config, port)).status === 401); assert(calls.length === 0); });
Deno.test('malformed code cannot trigger factor deletion', async () => { const { port, calls } = fixture(); assert((await handleAdminRecovery(request('bad'), config, port)).status === 400); assert(calls.length === 0); });
Deno.test('rejected/replayed backup code cannot delete factors', async () => { const { port, calls } = fixture(); port.begin = async () => ({ ok: false }); assert((await handleAdminRecovery(request(), config, port)).status === 403); assert(calls.length === 0); });
Deno.test('recovery removes only trusted snapshot factors, never returns AAL2', async () => {
  const { port, calls } = fixture(); const response = await handleAdminRecovery(request(), config, port);
  assert(response.status === 200); assert(calls.join(',') === 'remove:LOCAL_USER:LOCAL_FACTOR,revoke,finish');
  const body = await response.text(); assert(!body.includes('TICKET')); assert(!body.includes('FACTOR')); assert(!body.includes('aal2')); assert(response.headers.get('cache-control') === 'no-store');
});
Deno.test('worker failure never grants success', async () => { const { port, calls } = fixture(); port.removeFactor = async () => { throw new Error('SENSITIVE_PROVIDER_ERROR'); }; const response = await handleAdminRecovery(request(), config, port); assert(response.status === 503); assert(!(await response.text()).includes('SENSITIVE')); assert(calls.length === 0); });
Deno.test('cross-origin recovery denied', async () => { const { port, calls } = fixture(); const req = request(); req.headers.set('origin', 'https://evil.example'); assert((await handleAdminRecovery(req, config, port)).status === 403); assert(calls.length === 0); });
Deno.test('oversized authenticated recovery request rejected', async () => { const { port, calls } = fixture(); assert((await handleAdminRecovery(request('a'.repeat(2048)), config, port)).status === 400); assert(calls.length === 0); });
Deno.test('null recovery body rejected', async () => { const { port, calls } = fixture(); const req = new Request('http://local/recovery',{method:'POST',headers:{authorization:'Bearer LOCAL_TEST_ONLY'},body:'null'}); assert((await handleAdminRecovery(req, config, port)).status === 400); assert(calls.length === 0); });
