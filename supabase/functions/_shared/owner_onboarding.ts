export const ownerStagingUrl='https://gtcrijikfaglqcwqozel.supabase.co';
export function ownerPhone(input:unknown):string|null{if(typeof input!=='string')return null;const n=input.trim().replace(/[٠-٩]/g,c=>String(c.charCodeAt(0)-1632)).replace(/[\s()-]/g,'').replace(/^00/,'+').replace(/^\+?968/,'');return /^[79]\d{7}$/.test(n)?'+968'+n:null;}
export async function ownerBody(request:Request):Promise<Record<string,unknown>|null>{const reader=request.body?.getReader();if(!reader)return null;const chunks:Uint8Array[]=[];let size=0;while(true){const r=await reader.read();if(r.done)break;size+=r.value.length;if(size>16384){await reader.cancel();return null}chunks.push(r.value)}const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length}try{const value=JSON.parse(new TextDecoder().decode(bytes));return value&&typeof value==='object'&&!Array.isArray(value)?value:null}catch{return null}}
export interface OwnerSmsPort{allowed(phone:string,ipHash:string):Promise<boolean>;send(phone:string):Promise<void>}
export async function handleOwnerSms(request:Request,config:{url:string;enabled:boolean;origins:string[]},port:OwnerSmsPort):Promise<Response>{
 const origin=request.headers.get('origin');const headers:Record<string,string>={'Content-Type':'application/json','Cache-Control':'no-store',Vary:'Origin'};
 if(origin&&config.origins.includes(origin)){headers['Access-Control-Allow-Origin']=origin;headers['Access-Control-Allow-Headers']='authorization,apikey,content-type,x-client-info';headers['Access-Control-Allow-Methods']='POST,OPTIONS'}
 const reply=(status:number,body:Record<string,unknown>)=>new Response(JSON.stringify(body),{status,headers});
 if(origin&&!config.origins.includes(origin))return reply(403,{error:'ORIGIN_NOT_ALLOWED'});
 if(request.method==='OPTIONS')return reply(200,{});if(request.method!=='POST')return reply(405,{error:'METHOD_NOT_ALLOWED'});
 if(config.url!==ownerStagingUrl||!config.enabled)return reply(503,{error:'OWNER_SMS_NOT_CONFIGURED'});
 const body=await ownerBody(request),phone=ownerPhone(body?.phone);if(!phone)return reply(400,{error:'INVALID_OMAN_MOBILE'});
 try{const address=request.headers.get('x-real-ip')??request.headers.get('x-forwarded-for')?.split(',')[0]??'unknown';const ipHash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(address)))).map(v=>v.toString(16).padStart(2,'0')).join('');if(await port.allowed(phone,ipHash))await port.send(phone);return reply(200,{ok:true,message:'IF_OWNER_APPROVED_SMS_REQUESTED'})}catch{return reply(503,{error:'OWNER_SMS_UNAVAILABLE'})}
}
export interface OwnerProvisionPort{admin(token:string):Promise<string|null>;prepare(token:string,body:Record<string,unknown>):Promise<string>;context(id:string,actor:string):Promise<{owner_id:string|null;existing_auth_id:string|null;phone:string;status:string}>;create(phone:string):Promise<string>;updatePhone(user:string,phone:string):Promise<void>;finalize(id:string,actor:string,user:string):Promise<void>}
export async function handleOwnerProvision(request:Request,config:{url:string;enabled:boolean;origins:string[]},port:OwnerProvisionPort):Promise<Response>{
 const origin=request.headers.get('origin'),headers:Record<string,string>={'Content-Type':'application/json','Cache-Control':'no-store',Vary:'Origin'};
 if(origin&&config.origins.includes(origin)){headers['Access-Control-Allow-Origin']=origin;headers['Access-Control-Allow-Headers']='authorization,apikey,content-type,x-client-info';headers['Access-Control-Allow-Methods']='POST,OPTIONS'}
 const reply=(status:number,body:Record<string,unknown>)=>new Response(JSON.stringify(body),{status,headers});
 if(origin&&!config.origins.includes(origin))return reply(403,{error:'ORIGIN_NOT_ALLOWED'});if(request.method==='OPTIONS')return reply(200,{});if(request.method!=='POST')return reply(405,{error:'METHOD_NOT_ALLOWED'});
 if(!config.enabled||config.url!==ownerStagingUrl)return reply(503,{error:'OWNER_PROVISION_NOT_CONFIGURED'});
 const token=request.headers.get('authorization')?.match(/^Bearer (\S+)$/)?.[1];if(!token)return reply(401,{error:'AUTH_REQUIRED'});
 try{
  const actor=await port.admin(token);if(!actor)return reply(403,{error:'ADMIN_ONLY'});
  const body=await ownerBody(request);if(!body||!ownerPhone(body.phone)||body.verified!==true)return reply(400,{error:'VERIFIED_OWNER_DETAILS_REQUIRED'});
  const id=await port.prepare(token,body),context=await port.context(id,actor);
  if(context.status==='completed')return reply(200,{ok:true,request_id:id,owner_id:context.owner_id});
  let user=context.owner_id??context.existing_auth_id;
  if(!user)user=await port.create(context.phone);
  else if(context.owner_id&&context.owner_id!==context.existing_auth_id)await port.updatePhone(context.owner_id,context.phone);
  await port.finalize(id,actor,user);
  return reply(200,{ok:true,request_id:id,owner_id:user,activation:'SMS_REQUIRED'});
 }catch{return reply(503,{error:'OWNER_PROVISION_REQUIRES_REVIEW'})}
}
