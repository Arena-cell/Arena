import {env,configuration,Thawani,PaymentError,serverClient,reconcile,response} from '../_shared/payments.ts';
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get('origin');
 if(req.method==='OPTIONS')return response({},200,origin);
 try {
  if(req.method!=='POST')return response({error:'METHOD_NOT_ALLOWED'},405,origin);
  const db=serverClient();
  const token=req.headers.get('authorization')?.replace(/^Bearer /i,'');
  if(!token)return response({error:'AUTH_REQUIRED'},401,origin);
  const {data:{user},error:authError}=await db.auth.getUser(token);
  if(authError||!user)return response({error:'AUTH_REQUIRED'},401,origin);
  const {order_id,action}=await req.json();
  if(!['start','verify'].includes(action))throw new PaymentError('INVALID_ACTION');
  const {data:order,error}=await db.from('checkout_orders').select('*').eq('id',order_id).eq('user_id',user.id).single();
  if(error||!order)return response({error:'ORDER_NOT_FOUND'},404,origin);
  if(action==='start' && (order.cancellation_requested_at || order.entitlement_revoked_at || order.fulfillment_status!=='pending'))throw new PaymentError('ORDER_NOT_PAYABLE');
  // Missing keys fail before claiming a session or calling the provider.
  const provider=new Thawani(configuration(env));
  if(order.payment_method!=='card')throw new PaymentError('NOT_CARD_ORDER');
  let session;
  if(order.provider_session_id)session=await provider.retrieve(order.provider_session_id);
  else if(action==='start') {
    const {data:claim,error:claimError}=await db.rpc('payment_claim_session',{p_order:order.id});
    if(claimError)throw new PaymentError('ORDER_NOT_PAYABLE');
    session=claim.create_allowed ? await provider.create(order) : await provider.recover(order.id);
  } else session=await provider.recover(order.id);
  if(!session)throw new PaymentError('PAYMENT_RECONCILIATION_PENDING');
  const result=await reconcile(db,order,session,'verify:'+crypto.randomUUID());
  return response({order:result,checkout_url:session.payment_status==='unpaid' && result.fulfillment_status==='pending' && !result.cancellation_requested_at && !result.entitlement_revoked_at?provider.url(session.session_id):null},200,origin);
 }catch(error){return response({error:error instanceof PaymentError?error.message:'PAYMENT_RECONCILIATION_PENDING'},error instanceof PaymentError?error.status:502,origin);}
});
