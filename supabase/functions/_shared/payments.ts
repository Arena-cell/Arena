import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.110.0';
import {configuration, Thawani, verifiedSession, PaymentError} from './thawani.mjs';
export {configuration,Thawani,verifiedSession,PaymentError};
export const env=(name:string)=>Deno.env.get(name);
export function serverClient() {
  const url=env('SUPABASE_URL')??'';
  if(url!=='https://gtcrijikfaglqcwqozel.supabase.co')throw new PaymentError('STAGING_ONLY',503);
  const key=env('SUPABASE_SERVICE_ROLE_KEY');
  if(!key)throw new PaymentError('SERVER_NOT_CONFIGURED',503);
  return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
}
export async function reconcile(db:ReturnType<typeof serverClient>,order:any,session:any,event:string) {
  verifiedSession(order,session);
  const {data,error}=await db.rpc('payment_reconcile',{
    p_order:order.id,p_session:session.session_id,p_reference:session.client_reference_id,
    p_currency:session.currency,p_amount:session.total_amount,p_status:session.payment_status,
    p_invoice:session.invoice??null,p_event_key:event,
  });
  if(error)throw new PaymentError('PAYMENT_RECONCILIATION_FAILED',500);
  return data;
}
export function response(data:unknown,status=200,origin:string|null=null) {
  const allowed=(env('PAYMENT_ALLOWED_ORIGINS')??'http://127.0.0.1:5178,http://127.0.0.1:5180,http://127.0.0.1:5181').split(',');
  return new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store',
    ...(origin&&allowed.includes(origin)?{'Access-Control-Allow-Origin':origin,'Vary':'Origin'}:{}),
    'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS'}});
}
