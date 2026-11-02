import {env,configuration,Thawani,serverClient,reconcile,response} from '../_shared/payments.ts';
// Scheduled server job, never callable with a user's JWT. Set up only on Staging.
Deno.serve(async(req:Request)=>{
 if(req.method!=='POST')return response({error:'METHOD_NOT_ALLOWED'},405);
 const secret=env('PAYMENT_RECONCILE_SECRET');
 if(!secret || req.headers.get('authorization')!==`Bearer ${secret}`)return response({error:'UNAUTHORIZED'},401);
 try {
  const db=serverClient(),provider=new Thawani(configuration(env));
  const {data:orders,error}=await db.from('checkout_orders').select('*')
   .eq('payment_method','card').in('payment_status',['pending','cancelled'])
   .neq('provider_creation_state','not_started').order('updated_at').limit(50);
  if(error)return response({error:'RECONCILIATION_FAILED'},500);
  let checked=0,failed=0;
  for(const order of orders??[]) {
   try {
    const session=order.provider_session_id?await provider.retrieve(order.provider_session_id):await provider.recover(order.id);
    if(session){await reconcile(db,order,session,'scheduled:'+crypto.randomUUID());checked++;}
   }catch{failed++;}
  }
  return response({checked,failed});
 }catch{return response({error:'PAYMENT_PROVIDER_NOT_CONFIGURED_OR_UNAVAILABLE'},503);}
});
