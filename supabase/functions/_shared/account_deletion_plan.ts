// Local, provider-independent execution contract. No live adapter or deployment.
export type DeletionState = 'blocked_obligations' | 'verified' | 'processing' | 'completed' | 'failed';
export interface DeletionFacts {
  activeBookings: boolean; activeMatches: boolean; unsettledMoney: boolean;
  pendingRefunds: boolean; ownerAssignments: boolean; legalHold: boolean;
}
export function deletionBlocked(f: DeletionFacts): boolean {
  // A scoped legal hold archives only necessary records; it is not authority
  // to retain all personal data or indefinitely block unrelated erasure.
  return f.activeBookings || f.activeMatches || f.unsettledMoney || f.pendingRefunds || f.ownerAssignments;
}
export const deletionSteps = [
  'record_restore_tombstone', 'block_access_revoke_sessions', 'disable_tokens_jobs',
  'archive_restricted_retained_records', 'erase_sent_private_and_group_text_identity',
  'remove_sent_chat_images', 'remove_profile_images', 'erase_unneeded_personal_data',
  'verify_no_access_or_personal_data',
] as const;
export interface DeletionPort {
  facts(): Promise<DeletionFacts>;
  // Must use a durable per-account lock and fences honored by all writers.
  locked<T>(task:()=>Promise<T>): Promise<T>;
  done(step:string): Promise<boolean>;
  step(name:string): Promise<void>;
  markDone(step:string): Promise<void>;
  verify(): Promise<boolean>;
  status(state:DeletionState): Promise<void>;
}
export async function executeDeletion(config:{enabled:boolean;policyApproved:boolean}, port:DeletionPort):Promise<DeletionState>{
  if(!config.enabled||!config.policyApproved) throw Error('DELETION_EXECUTION_NOT_ENABLED');
  return port.locked(async()=>{
    if(deletionBlocked(await port.facts())){await port.status('blocked_obligations');return 'blocked_obligations'}
    await port.status('processing');
    try{
      for(const step of deletionSteps){
        if(await port.done(step))continue;
        await port.step(step);await port.markDone(step);
      }
      if(!await port.verify())throw Error('DELETION_POSTCONDITIONS_FAILED');
      await port.status('completed');return 'completed';
    }catch{await port.status('failed');return 'failed'}
  });
}
export function restoreMayEnableAccount(tombstoneExists:boolean):boolean{return !tombstoneExists}
export interface MessageForErasure {
 id:string;senderId:string;scope:'private'|'group';content:string|null;senderName:string|null;
 avatar:string|null;attachments:{path:string;uploaderId:string}[];legalHoldReason?:string;
}
export function planMessageErasure(subject:string,messages:MessageForErasure[]){
 return messages.filter(m=>m.senderId===subject).map(m=>({
  id:m.id,scope:m.scope,
  // Preserve only non-identifying row position; never retain authored text in chat.
  replacement:{senderId:null,senderName:null,avatar:null,content:null,attachments:[],deleted:true},
  removeObjects:m.attachments.filter(a=>a.uploaderId===subject).map(a=>a.path),
  reviewSharedObjects:m.attachments.filter(a=>a.uploaderId!==subject).map(a=>a.path),
  archiveRestricted:Boolean(m.legalHoldReason?.trim()),
 }));
}
export function retainRestrictedFields(input:Record<string,unknown>,rules:Record<string,{documentedBasis:string;until:string}>,serverNow:Date):Record<string,unknown>{
 const retained:Record<string,unknown>={};
 for(const [field,rule] of Object.entries(rules)){
  const end=Date.parse(rule.until);
  if(rule.documentedBasis.trim()&&Number.isFinite(end)&&end>serverNow.getTime()&&Object.hasOwn(input,field))retained[field]=input[field];
 }
 return retained;
}
// A legal hold changes permissible erasure, not a magic permission to mark complete.
// No auth.deleteUser call: existing ON DELETE CASCADE/RESTRICT chains require a
// separately approved archival mapping before a real adapter can be implemented.
