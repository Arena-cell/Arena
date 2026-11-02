import {deletionBlocked,deletionSteps,executeDeletion,restoreMayEnableAccount,planMessageErasure,retainRestrictedFields,type DeletionFacts,type DeletionPort} from '../functions/_shared/account_deletion_plan.ts';
const facts:DeletionFacts={activeBookings:false,activeMatches:false,unsettledMoney:false,pendingRefunds:false,ownerAssignments:false,legalHold:false};
function assert(x:unknown){if(!x)throw Error('assertion failed')}
function fixture(){const calls:string[]=[],done=new Set<string>();const p:DeletionPort={facts:async()=>facts,locked:async f=>f(),done:async s=>done.has(s),step:async s=>{calls.push(s)},markDone:async s=>{done.add(s)},verify:async()=>true,status:async s=>{calls.push(s)}};return {p,calls,done}}
for(const key of Object.keys(facts).filter(k=>k!=='legalHold'))Deno.test('deletion blocked by '+key,async()=>{const f=fixture();f.p.facts=async()=>({...facts,[key]:true});assert(await executeDeletion({enabled:true,policyApproved:true},f.p)==='blocked_obligations');assert(f.done.size===0)});
Deno.test('disabled execution never touches account',async()=>{const f=fixture();try{await executeDeletion({enabled:false,policyApproved:true},f.p);throw Error('expected')}catch(e){assert(String(e).includes('NOT_ENABLED'))}assert(f.calls.length===0)});
Deno.test('unapproved policy never touches account',async()=>{const f=fixture();try{await executeDeletion({enabled:true,policyApproved:false},f.p);throw Error('expected')}catch(e){assert(String(e).includes('NOT_ENABLED'))}assert(f.calls.length===0)});
Deno.test('completion requires all cleanup steps before status',async()=>{const f=fixture();assert(await executeDeletion({enabled:true,policyApproved:true},f.p)==='completed');assert(f.done.size===deletionSteps.length);assert(f.calls.indexOf('record_restore_tombstone')<f.calls.indexOf('block_access_revoke_sessions'));assert(f.calls.at(-1)==='completed')});
Deno.test('failed media cleanup cannot claim completed and retry resumes',async()=>{const f=fixture();f.p.step=async s=>{f.calls.push(s);if(s==='remove_sent_chat_images')throw Error('storage unavailable')};assert(await executeDeletion({enabled:true,policyApproved:true},f.p)==='failed');assert(!f.done.has('remove_sent_chat_images'));const first=f.calls.filter(x=>x==='record_restore_tombstone').length;f.p.step=async s=>{f.calls.push(s)};assert(await executeDeletion({enabled:true,policyApproved:true},f.p)==='completed');assert(f.calls.filter(x=>x==='record_restore_tombstone').length===first)});
Deno.test('postcondition failure is not completion',async()=>{const f=fixture();f.p.verify=async()=>false;assert(await executeDeletion({enabled:true,policyApproved:true},f.p)==='failed');assert(!f.calls.includes('completed'))});
Deno.test('restore blocks tombstoned subject',()=>{assert(!restoreMayEnableAccount(true));assert(restoreMayEnableAccount(false))});
Deno.test('empty obligations allow planning only',()=>assert(!deletionBlocked(facts)));
Deno.test('scoped legal hold archives separately without retaining unrelated data',async()=>{const f=fixture();f.p.facts=async()=>({...facts,legalHold:true});assert(await executeDeletion({enabled:true,policyApproved:true},f.p)==='completed');assert(f.done.has('archive_restricted_retained_records')&&f.done.has('erase_unneeded_personal_data'))});
for(const scope of ['private','group'] as const)Deno.test('erase sent '+scope+' content and identity while preserving others',()=>{
 const records=[{id:'sent',senderId:'subject',scope,content:'private authored text',senderName:'private name',avatar:'avatar-path',attachments:[{path:'owned-image',uploaderId:'subject'},{path:'other-image',uploaderId:'other'}],legalHoldReason:'documented case'}, {id:'other',senderId:'other',scope,content:'preserved',senderName:'other',avatar:null,attachments:[]}];
 const original=JSON.stringify(records),plan=planMessageErasure('subject',records);
 assert(plan.length===1&&plan[0].replacement.content===null&&plan[0].replacement.senderId===null);
 assert(plan[0].replacement.senderName===null&&plan[0].replacement.avatar===null&&plan[0].replacement.attachments.length===0);
 assert(plan[0].removeObjects.join()==='owned-image'&&plan[0].reviewSharedObjects.join()==='other-image');
 assert(plan[0].archiveRestricted&&JSON.stringify(records)===original);
 assert(!JSON.stringify(plan).includes('private authored text'));
});
Deno.test('retention never preserves an entire profile based on a financial purpose',()=>{
 const result=retainRestrictedFields({invoice:'reference',amount:1000,phone:'private',name:'private',location:'private'}, {invoice:{documentedBasis:'LOCAL_APPROVED_FINANCIAL_BASIS',until:'2030-01-01'},amount:{documentedBasis:'LOCAL_APPROVED_FINANCIAL_BASIS',until:'2030-01-01'}},new Date('2026-10-26'));
 assert(Object.keys(result).join()==='invoice,amount'&&!Object.hasOwn(result,'phone'));
});
Deno.test('expired undocumented or invalid retention rules retain no fields',()=>{
 const result=retainRestrictedFields({a:1,b:2,c:3}, {a:{documentedBasis:'',until:'2030-01-01'},b:{documentedBasis:'expired',until:'2025-01-01'},c:{documentedBasis:'bad date',until:'invalid'}},new Date('2026-10-26'));
 assert(Object.keys(result).length===0);
});
