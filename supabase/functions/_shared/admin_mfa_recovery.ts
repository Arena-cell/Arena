export interface RecoveryPort {
  user(token: string): Promise<string | null>;
  begin(token: string, code: string): Promise<{ ok: boolean; ticket?: string }>;
  factors(user: string, ticket: string): Promise<string[] | null>;
  removeFactor(user: string, factor: string): Promise<void>;
  revokeSessions(token: string): Promise<void>;
  finish(user: string, ticket: string): Promise<void>;
}

// No recovery payload or provider exception is logged or echoed.
export async function handleAdminRecovery(
  request: Request,
  config: { enabled: boolean; url: string; origin: string },
  port: RecoveryPort,
): Promise<Response> {
  const origin = request.headers.get('origin');
  const headers: Record<string, string> = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', Vary: 'Origin' };
  if (origin && origin === config.origin) {
    headers['Access-Control-Allow-Origin'] = origin;
    headers['Access-Control-Allow-Headers'] = 'authorization,apikey,content-type,x-client-info';
    headers['Access-Control-Allow-Methods'] = 'POST,OPTIONS';
  }
  const reply = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify(body), { status, headers });
  if (origin && origin !== config.origin) return reply(403, { error: 'ORIGIN_NOT_ALLOWED' });
  if (request.method === 'OPTIONS') return reply(200, {});
  if (request.method !== 'POST') return reply(405, { error: 'METHOD_NOT_ALLOWED' });
  if (!config.enabled || config.url !== 'https://gtcrijikfaglqcwqozel.supabase.co') return reply(503, { error: 'RECOVERY_NOT_ENABLED' });
  const token = request.headers.get('authorization')?.match(/^Bearer (\S+)$/)?.[1];
  if (!token) return reply(401, { error: 'UNAUTHORIZED' });
  try {
    const user = await port.user(token);
    if (!user) return reply(401, { error: 'UNAUTHORIZED' });
    const reader = request.body?.getReader();
    if (!reader) return reply(400, { error: 'INVALID_REQUEST' });
    let size = 0; const parts: Uint8Array[] = [];
    while (true) {
      const chunk = await reader.read(); if (chunk.done) break;
      size += chunk.value.length;
      if (size > 512) { await reader.cancel(); return reply(400, { error: 'INVALID_REQUEST' }); }
      parts.push(chunk.value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const part of parts) { bytes.set(part, offset); offset += part.length; }
    let body;
    try { body = JSON.parse(new TextDecoder().decode(bytes)); } catch { return reply(400, { error: 'INVALID_REQUEST' }); }
    if (!body || typeof body.code !== 'string' || !/^[0-9a-f]{32}$/.test(body.code)) return reply(400, { error: 'INVALID_REQUEST' });
    const recovery = await port.begin(token, body.code);
    if (!recovery.ok || !recovery.ticket) return reply(403, { error: 'RECOVERY_REJECTED' });
    const factors = await port.factors(user, recovery.ticket);
    if (!factors) return reply(403, { error: 'RECOVERY_REJECTED' });
    for (const factor of factors) await port.removeFactor(user, factor);
    await port.revokeSessions(token);
    await port.finish(user, recovery.ticket);
    return reply(200, { ok: true, reenrollment_required: true });
  } catch {
    return reply(503, { error: 'RECOVERY_UNAVAILABLE' });
  }
}
