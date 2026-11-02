// All transport is local fake; this file never contacts Supabase or Thawani.
Deno.test('Cancelled/revoked orders cannot restart provider payment; missing keys stay explicit', async () => {
  const oldFetch=globalThis.fetch,oldServe=Deno.serve;
  let handler: (r: Request)=>Promise<Response>;
  let order: Record<string,unknown>={id:'11111111-1111-4111-8111-111111111111',user_id:'22222222-2222-4222-8222-222222222222',payment_method:'card',fulfillment_status:'cancelled',cancellation_requested_at:'2026-10-09T00:00:00Z'};
  const previous=new Map(['SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','THAWANI_SECRET_KEY'].map(k=>[k,Deno.env.get(k)]));
  try {
    Deno.env.set('SUPABASE_URL','https://gtcrijikfaglqcwqozel.supabase.co');Deno.env.set('SUPABASE_SERVICE_ROLE_KEY','LOCAL_TEST_FAKE_ONLY');Deno.env.delete('THAWANI_SECRET_KEY');
    // Capture the actual entry handler without opening an HTTP server.
    Deno.serve=((h: unknown)=>{handler=h as typeof handler;return {} as Deno.HttpServer}) as typeof Deno.serve;
    globalThis.fetch=((input: RequestInfo | URL)=>{
      const url=String(input instanceof Request?input.url:input);
      if(url.includes('/auth/v1/user'))return Promise.resolve(new Response(JSON.stringify({id:order.user_id}),{headers:{'content-type':'application/json'}}));
      if(url.includes('/rest/v1/checkout_orders'))return Promise.resolve(new Response(JSON.stringify(order),{headers:{'content-type':'application/json'}}));
      throw Error('Unexpected network request in local fake: '+url);
    }) as typeof fetch;
    await import('../functions/arena-payment/index.ts');
    const request=()=>new Request('http://localhost',{method:'POST',headers:{authorization:'Bearer LOCAL_TEST_FAKE_ONLY','content-type':'application/json'},body:JSON.stringify({order_id:order.id,action:'start'})});
    const cancelled=await handler!(request());if(cancelled.status!==409 || (await cancelled.json()).error!=='ORDER_NOT_PAYABLE')throw Error('Cancelled order was payable');
    order={...order,fulfillment_status:'pending',cancellation_requested_at:null,entitlement_revoked_at:'2026-10-09T00:00:00Z'};
    const revoked=await handler!(request());if(revoked.status!==409)throw Error('Revoked order was payable');
    order={...order,entitlement_revoked_at:null};const pending=await handler!(request());if(pending.status!==503 || (await pending.json()).error!=='PAYMENT_PROVIDER_NOT_CONFIGURED')throw Error('Missing provider config was not explicit');
  } finally {
    globalThis.fetch=oldFetch;Deno.serve=oldServe;for(const [k,v] of previous){if(v===undefined)Deno.env.delete(k);else Deno.env.set(k,v)}
  }
});
