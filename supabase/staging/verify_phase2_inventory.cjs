const fs=require('node:fs'),assert=require('node:assert/strict'),crypto=require('node:crypto');
process.chdir(require('node:path').resolve(__dirname,'../..'));
const url='https://gtcrijikfaglqcwqozel.supabase.co',key='sb_publishable_pxaampXaN_YJB3uqB-B3CA_dcYA-glr';
const session=JSON.parse(fs.readFileSync('build/staging-evidence/sessions.local.json','utf8'))[0];
async function call(name,body){const r=await fetch(url+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key,Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'},body:JSON.stringify(body)});return {status:r.status,data:await r.json()};}
(async()=>{
 const arena='a1000000-0000-4000-8000-000000000002',start='2036-04-03T10:00:00+04:00',end='2036-04-03T11:00:00+04:00';
 const quote=await call('checkout_quote',{p_arena:arena,p_start:start,p_end:end});assert.equal(quote.status,200,JSON.stringify(quote));
 const rack=quote.data.catalog.find(x=>x.code==='racket'),water=quote.data.catalog.find(x=>x.code==='water');assert.ok(rack&&water,'Admin catalog must be configured');
 const p={purpose:'booking',payment_method:'cash',arena_id:arena,starts_at:start,ends_at:end,addons:[{id:rack.id,quantity:6},{id:water.id,quantity:2}]};
 const path='build/phase2-evidence/inventory-request.local.json';
 let id;if(fs.existsSync(path))id=JSON.parse(fs.readFileSync(path,'utf8')).key;else{ id=crypto.randomUUID();fs.writeFileSync(path,JSON.stringify({key:id}));}
 const order=await call('create_checkout',{p_request:p,p_request_key:id});assert.equal(order.status,200,JSON.stringify(order));assert.equal(order.data.total_amount_baisa,17000);
 const overlap=await call('checkout_quote',{p_arena:arena,p_start:start,p_end:end,p_addons:[{id:rack.id,quantity:3}]});assert.ok(overlap.status>=400);assert.match(overlap.data.message,/ADDON_STOCK_UNAVAILABLE/);
 const available=await call('checkout_quote',{p_arena:arena,p_start:start,p_end:end});assert.equal(available.data.catalog.find(x=>x.code==='racket').available_quantity,2);
 const adjacent=await call('checkout_quote',{p_arena:arena,p_start:end,p_end:'2036-04-03T12:00:00+04:00',p_addons:[{id:rack.id,quantity:8}]});assert.equal(adjacent.status,200,JSON.stringify(adjacent));assert.equal(adjacent.data.total_amount_baisa,18000);
 console.log('PASS Staging Admin-configured water/rackets, server 17.000 OMR snapshot, overlapping stock=2, adjacent stock=8');
})().catch(e=>{console.error(e.message);process.exitCode=1;});
