const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const sessions=JSON.parse(fs.readFileSync(path.resolve(__dirname,'../../build/staging-evidence/sessions.local.json')));
const base='https://gtcrijikfaglqcwqozel.supabase.co';
const key='sb_publishable_pxaampXaN_YJB3uqB-B3CA_dcYA-glr';
const one='a1000000-0000-4000-8000-000000000001',two='a1000000-0000-4000-8000-000000000002';
const day=process.env.STAGING_BOOKING_TEST_DAY || '2026-10-03';
const at=t=>`${day}T${t}:00+04:00`;
async function rpc(name,body,u=0){const r=await fetch(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key,Authorization:`Bearer ${sessions[u].access_token}`,'Content-Type':'application/json'},body:JSON.stringify(body)});const t=await r.text();return{status:r.status,data:t?JSON.parse(t):null};}
const params=(arena,s,e)=>({p_arena_id:arena,p_starts_at:at(s),p_ends_at:at(e),p_water_cartons:0,p_idempotency_key:randomUUID()});
const book=(p,u=0)=>rpc('create_arena_booking',p,u);
const ok=r=>assert.equal(r.status,200,JSON.stringify(r));
async function available(arena,s,e){const r=await rpc('arena_has_available_court',{p_arena_id:arena,p_start:at(s),p_end:at(e)});ok(r);return r.data;}
(async()=>{
  const first=params(one,'10:00','10:30');const a=await book(first);ok(a);
  const retry=await book(first);ok(retry);assert.deepEqual(retry.data,a.data);console.log('PASS half-hour booking and idempotent retry');
  const overlap=await book(params(one,'10:00','11:00'),1);assert.ok(overlap.status>=400);assert.match(JSON.stringify(overlap),/TIME_NO_LONGER_AVAILABLE/);console.log('PASS overlapping booking denied');
  ok(await book(params(one,'10:30','11:00'),1));console.log('PASS adjacent half-hour booking');
  const race=await Promise.all([book(params(one,'12:00','13:00')),book(params(one,'12:00','13:00'),1)]);
  assert.equal(race.filter(r=>r.status===200).length,1,JSON.stringify(race));assert.match(JSON.stringify(race.find(r=>r.status!==200)),/TIME_NO_LONGER_AVAILABLE/);console.log('PASS simultaneous last-court requests: exactly one winner');
  const multi=await Promise.all([book(params(two,'14:00','15:00')),book(params(two,'14:00','15:00'),1)]);multi.forEach(ok);
  assert.notEqual(multi[0].data[0].court_id,multi[1].data[0].court_id);
  const third=await book(params(two,'14:00','15:00'));assert.ok(third.status>=400);assert.match(JSON.stringify(third),/TIME_NO_LONGER_AVAILABLE/);console.log('PASS simultaneous two-court capacity; third booking rejected');
  const match=await rpc('create_arena_match',{p_arena_id:one,p_name:'Staging Phase 1 Match',p_description:'Test only',p_rules:'',p_sport:'football',p_starts_at:at('16:00'),p_ends_at:at('17:00'),p_max_players:4,p_is_private:false,p_show_joined_players:true,p_payment_method:'cash',p_idempotency_key:randomUUID()});ok(match);
  const onMatch=await book(params(one,'16:30','17:00'),1);assert.ok(onMatch.status>=400);assert.match(JSON.stringify(onMatch),/TIME_NO_LONGER_AVAILABLE/);console.log('PASS match consumes the same inventory as bookings');
  fs.writeFileSync(path.resolve(__dirname,'../../build/staging-evidence/booking-results.json'),JSON.stringify({day,first:a,race,multi,match},null,2));
})().catch(e=>{console.error(e.message);process.exitCode=1});
