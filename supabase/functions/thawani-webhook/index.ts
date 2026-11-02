import {env,configuration,Thawani,serverClient,reconcile,response,PaymentError} from '../_shared/payments.ts';
import {verifySignature} from '../_shared/thawani.mjs';
Deno.serve(async(req:Request)=>{
 try {
  if(req.method!=='POST')return response({error:'METHOD_NOT_ALLOWED'},405);
  const raw=await req.text();
  if(raw.length>65536)return response({error:'BODY_TOO_LARGE'},413);
  if(!await verifySignature(raw,req.headers.get('thawani-timestamp'),req.headers.get('thawani-signature'),env('THAWANI_WEBHOOK_SECRET')))
    return response({error:'INVALID_SIGNATURE'},401);
  const body=JSON.parse(raw);
  // Payment events without checkout session details are acknowledged; periodic
  // reconciliation and checkout.completed retrieve the authoritative session.
  if(!body.data?.session_id || !body.data?.client_reference_id)return response({received:true});
  const db=serverClient();
  const {data:order,error}=await db.from('checkout_orders').select('*').eq('id',body.data.client_reference_id).single();
  if(error||!order)return response({error:'ORDER_NOT_FOUND'},404);
  const provider=new Thawani(configuration(env));
  const session=await provider.retrieve(body.data.session_id);
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(raw));
  const event=Array.from(new Uint8Array(digest),x=>x.toString(16).padStart(2,'0')).join('');
  await reconcile(db,order,session,'webhook:'+event);
  return response({received:true});
 }catch(error){return response({error:error instanceof PaymentError?error.message:'WEBHOOK_RETRY_REQUIRED'},500);}
});
