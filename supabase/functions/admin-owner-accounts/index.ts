import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.110.5';
import {handleOwnerProvision,ownerStagingUrl} from '../_shared/owner_onboarding.ts';
Deno.serve(request=>{
 const url=Deno.env.get('SUPABASE_URL')??'',key=Deno.env.get('SUPABASE_ANON_KEY')??'';
 const server=()=>{if(url!==ownerStagingUrl)throw Error('STAGING_ONLY');return createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'',{auth:{persistSession:false,autoRefreshToken:false}})};
 const caller=(token:string)=>createClient(url,key,{global:{headers:{Authorization:'Bearer '+token}},auth:{persistSession:false,autoRefreshToken:false}});
 return handleOwnerProvision(request,{url,enabled:Deno.env.get('ARENA_OWNER_PROVISION_ENABLED')==='true',origins:(Deno.env.get('ARENA_ADMIN_ORIGIN')??'').split(',').filter(Boolean)},{
  async admin(token){const r=await server().auth.getUser(token);if(r.error||!r.data.user)return null;const {data,error}=await caller(token).rpc('is_platform_admin');return !error&&data===true?r.data.user.id:null},
  async prepare(token,b){const {data,error}=await caller(token).rpc('admin_prepare_owner',{p_request:b.request_id,p_owner:b.owner_id??null,p_name:b.name,p_phone:b.phone,p_arenas:b.arena_ids,p_proof:b.proof,p_verified:b.verified});if(error)throw error;return data.request_id},
  async context(id,actor){const {data,error}=await server().rpc('owner_provision_context',{p_request:id,p_actor:actor});if(error)throw error;return data},
  async create(phone){const {data,error}=await server().auth.admin.createUser({phone,phone_confirm:false});if(error||!data.user)throw Error('AUTH_CREATE_FAILED');return data.user.id},
  async updatePhone(user,phone){const {error}=await server().auth.admin.updateUserById(user,{phone,phone_confirm:false});if(error)throw error},
  async finalize(id,actor,user){const {error}=await server().rpc('owner_finalize_provision',{p_request:id,p_actor:actor,p_auth_user:user});if(error)throw error},
 });
});
