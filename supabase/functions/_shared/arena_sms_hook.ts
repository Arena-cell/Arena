// Provider-neutral transport boundary. Never generate/verify OTP or mint sessions here.
import { Webhook } from 'npm:standardwebhooks@1.0.0';
export const smsStagingUrl = 'https://gtcrijikfaglqcwqozel.supabase.co';
export interface SmsTransport {
  ready: boolean;
  send(input: { phone: string; otp: string; idempotencyKey: string }): Promise<void>;
}
export interface SmsLedger {
  reserve(event: string, phone: string): Promise<'send' | 'accepted' | 'deny'>;
  finish(event: string, state: 'accepted' | 'uncertain'): Promise<void>;
}
export interface SmsConfig { url: string; enabled: boolean; webhookSecret: string; hashSecret: string }
export async function smsDigest(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), {name:'HMAC',hash:'SHA-256'}, false, ['sign']);
  return Array.from(new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value))), v=>v.toString(16).padStart(2,'0')).join('');
}
export async function handleSmsHook(req: Request, config: SmsConfig, ledger: SmsLedger, transport: SmsTransport): Promise<Response> {
  const reply = (status: number) => new Response(JSON.stringify(status===200 ? {} : {error:{http_code:status,message:'SMS unavailable or request not permitted'}}), {status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}});
  if(req.method!=='POST') return reply(405);
  if(config.url!==smsStagingUrl || !config.enabled || !transport.ready || config.hashSecret.length<32 || !config.webhookSecret) return reply(503);
  // Bounded streaming read, before signature verification; never log payload/headers.
  let raw='';
  try {
    const reader=req.body?.getReader(); if(!reader)return reply(400);
    const chunks:Uint8Array[]=[]; let size=0;
    while(true){const part=await reader.read();if(part.done)break;size+=part.value.length;if(size>16384){await reader.cancel();return reply(413)}chunks.push(part.value)}
    const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length}raw=new TextDecoder('utf-8',{fatal:true}).decode(bytes);
  } catch { return reply(400); }
  let payload: {user?:{phone?:unknown};sms?:{otp?:unknown}};
  try { payload=new Webhook(config.webhookSecret.replace(/^v1,whsec_/, 'whsec_')).verify(raw,Object.fromEntries(req.headers)) as typeof payload; }
  catch { return reply(401); }
  const phone=payload?.user?.phone, otp=payload?.sms?.otp;
  // Supabase Auth phone format is normally digits without '+'; accept canonical equivalents only.
  if(typeof phone!=='string'||!/^\+?968[79]\d{7}$/.test(phone)||typeof otp!=='string'||!/^\d{6}$/.test(otp))return reply(400);
  const normalized='+'+phone.replace(/^\+/, '');
  try {
    // Deduplicate the same code even if a retry is delivered with a new webhook-id.
    const event=await smsDigest(config.hashSecret,`sms:${normalized}:${otp}`);
    const phoneHash=await smsDigest(config.hashSecret,`phone:${normalized}`);
    const reservation=await ledger.reserve(event,phoneHash);
    if(reservation==='accepted')return reply(200);
    if(reservation!=='send')return reply(429);
    try { await transport.send({phone:normalized,otp,idempotencyKey:event}); }
    catch { await ledger.finish(event,'uncertain'); return reply(503); }
    // This is provider acceptance, never evidence of delivery or authentication.
    await ledger.finish(event,'accepted');return reply(200);
  } catch { return reply(503); }
}
