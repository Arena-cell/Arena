import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.110.5';
import {handleSmsHook, type SmsLedger, type SmsTransport} from '../_shared/arena_sms_hook.ts';

// Deliberately unconfigured: no invented Ooredoo/Omantel endpoint or payload contract.
// Replace only after official transactional API documentation and local contract tests.
const transport: SmsTransport = {ready:false,send:async()=>{throw Error('PROVIDER_NOT_CONFIGURED')}};
Deno.serve(req=>{
  const url=Deno.env.get('SUPABASE_URL')??'';
  const client=()=>createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')??'',{auth:{persistSession:false,autoRefreshToken:false}});
  const ledger:SmsLedger={
    async reserve(event,phone){const {data,error}=await client().rpc('arena_sms_reserve',{p_event:event,p_phone:phone});if(error)throw error;return data},
    async finish(event,state){const {error}=await client().rpc('arena_sms_finish',{p_event:event,p_state:state});if(error)throw error},
  };
  return handleSmsHook(req,{url,enabled:Deno.env.get('ARENA_SMS_ENABLED')==='true',webhookSecret:Deno.env.get('ARENA_SMS_WEBHOOK_SECRET')??'',hashSecret:Deno.env.get('ARENA_SMS_HASH_SECRET')??''},ledger,transport);
});
