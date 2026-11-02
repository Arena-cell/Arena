import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.110.5';
import {handleOwnerSms,ownerStagingUrl} from '../_shared/owner_onboarding.ts';
Deno.serve(request=>{
 const url=Deno.env.get('SUPABASE_URL')??'',enabled=Deno.env.get('ARENA_OWNER_PHONE_AUTH_ENABLED')==='true'&&Deno.env.get('ARENA_OWNER_SMS_READY')==='true';
 const make=()=>{if(url!==ownerStagingUrl)throw Error('STAGING_ONLY');return createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'',{auth:{persistSession:false,autoRefreshToken:false}})};
 return handleOwnerSms(request,{url,enabled,origins:(Deno.env.get('ARENA_OWNER_ORIGINS')??'').split(',').filter(Boolean)},{
  async allowed(phone,ipHash){const {data,error}=await make().rpc('owner_sms_authorize',{p_phone:phone,p_ip_hash:ipHash});if(error)throw error;return data===true},
  async send(phone){const client=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')??'',{auth:{persistSession:false,autoRefreshToken:false}});const {error}=await client.auth.signInWithOtp({phone,options:{shouldCreateUser:false}});if(error)throw error},
 });
});
