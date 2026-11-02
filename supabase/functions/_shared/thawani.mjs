// Official Thawani checkout API. This module has no built-in credentials or mocks.
export class PaymentError extends Error {
  constructor(code, status = 409) { super(code); this.status = status; }
}
export function configuration(env) {
  const secret = env('THAWANI_SECRET_KEY');
  const publishable = env('THAWANI_PUBLISHABLE_KEY');
  const mode = env('THAWANI_ENV');
  const success = env('THAWANI_SUCCESS_URL');
  const cancel = env('THAWANI_CANCEL_URL');
  if (!secret || !publishable || !mode || !success || !cancel)
    throw new PaymentError('PAYMENT_PROVIDER_NOT_CONFIGURED', 503);
  if (mode !== 'sandbox') throw new PaymentError('PRODUCTION_PAYMENTS_DISABLED', 503);
  for (const value of [success, cancel]) {
    const url = new URL(value);
    if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost','127.0.0.1'].includes(url.hostname)))
      throw new PaymentError('INVALID_PAYMENT_REDIRECT', 503);
  }
  return {secret, publishable, success, cancel, base:'https://uatcheckout.thawani.om/api/v1', checkout:'https://uatcheckout.thawani.om/pay/'};
}
export class Thawani {
  constructor(config, transport = fetch) { this.config=config; this.transport=transport; }
  async request(path, body) {
    const response = await this.transport(this.config.base+path, {
      method:body ? 'POST' : 'GET',
      headers:{'Content-Type':'application/json','Accept':'application/json','thawani-api-key':this.config.secret},
      ...(body ? {body:JSON.stringify(body)} : {}),
      signal:AbortSignal.timeout(15000),
    });
    if (response.status===404) return null;
    if (!response.ok) throw new PaymentError('PROVIDER_REQUEST_FAILED',502);
    const result=await response.json();
    if(result.success!==true || !result.data) throw new PaymentError('PROVIDER_REQUEST_FAILED',502);
    return result.data;
  }
  create(order) {
    if (!Number.isSafeInteger(order.amount_due_baisa) || order.amount_due_baisa<100)
      throw new PaymentError('CARD_MINIMUM_100_BAISA');
    const redirect=(base)=>{const url=new URL(base);url.searchParams.set('order_id',order.id);return url.href;};
    return this.request('/checkout/session',{
      client_reference_id:order.id,mode:'payment',
      products:[{name:'Arena reservation',quantity:1,unit_amount:order.amount_due_baisa}],
      success_url:redirect(this.config.success),cancel_url:redirect(this.config.cancel),
      expire_in_minutes:30,save_card_on_success:false,metadata:{order_id:order.id},
    });
  }
  retrieve(id) { return this.request('/checkout/session/'+encodeURIComponent(id)); }
  recover(reference) { return this.request('/checkout/reference/'+encodeURIComponent(reference)); }
  // Architecture only: no deployed handler calls this until refund activation
  // includes provider payment-reference verification and sandbox acceptance.
  refund(paymentId, amount, reason, refundId) {
    if(!Number.isSafeInteger(amount)||amount<1||!paymentId||!reason)throw new PaymentError('INVALID_REFUND');
    return this.request('/refunds',{payment_id:paymentId,amount,reason,metadata:{refund_id:refundId}});
  }
  url(session) { return this.config.checkout+encodeURIComponent(session)+'?key='+encodeURIComponent(this.config.publishable); }
}
export function verifiedSession(order, session) {
  if (!session || session.client_reference_id!==order.id || session.currency!=='OMR' ||
      !Number.isSafeInteger(session.total_amount) || session.total_amount!==order.amount_due_baisa ||
      !session.session_id || !['paid','unpaid','cancelled'].includes(session.payment_status) ||
      (order.provider_session_id && order.provider_session_id!==session.session_id))
    throw new PaymentError('PROVIDER_VERIFICATION_MISMATCH',502);
  return session;
}
export async function verifySignature(raw,timestamp,signature,secret,now=Date.now()) {
  if(!secret || !/^\d{10}$/.test(timestamp??'') || !/^[a-fA-F0-9]{64}$/.test(signature??''))return false;
  // Old signed events are reconciled by scheduled/server status checks, not trusted replays.
  if(Math.abs(now/1000-Number(timestamp))>300)return false;
  const encoder=new TextEncoder();
  const key=await crypto.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  const bytes=new Uint8Array(await crypto.subtle.sign('HMAC',key,encoder.encode(raw+'-'+timestamp)));
  const expected=Array.from(bytes,x=>x.toString(16).padStart(2,'0')).join('');
  let diff=0;for(let i=0;i<expected.length;i++)diff|=expected.charCodeAt(i)^signature.toLowerCase().charCodeAt(i);
  return diff===0;
}
