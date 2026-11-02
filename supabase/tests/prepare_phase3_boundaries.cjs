// Build a NEW migration from reviewed immutable function sources. Never edit them.
const fs=require('node:fs'),path=require('node:path');
process.chdir(path.resolve(__dirname,'../..'));
const read=f=>fs.readFileSync('supabase/migrations/'+f,'utf8');
function fn(file,name){const s=read(file);const re=new RegExp('create (?:or replace )?function public\\.'+name+'\\([\\s\\S]*?end \\$\\$;','i');const m=s.match(re);if(!m)throw Error(name);return m[0].replace(/^create function/,'create or replace function');}
let parts=[];
for(const [file,name,lock] of [
 ['202609290003_phase1_rpc_boundaries.sql','join_match','join_match.match_id'],
 ['202609290003_phase1_rpc_boundaries.sql','request_match_join','p_match_id'],
 ['202609290003_phase1_rpc_boundaries.sql','leave_match','leave_match.match_id'],
 ['202610040004_phase2_lifecycle.sql','respond_match_join_request','p_match_id'],
 ['202610050001_phase2_paid_rejoin.sql','create_participant_checkout','p_match'],
 ['202610040003_phase2_payment_boundaries.sql','payment_reconcile',null],
 ['202610040003_phase2_payment_boundaries.sql','request_payment_refund',null],
 ['202610040003_phase2_payment_boundaries.sql','payment_confirm_refund',null],
]){
 let s=fn(file,name);
 // Inject after caller authentication/profile checks but BEFORE first row lock.
 if(lock){
  const needle=name==='leave_match'?'  perform 1 from matches':' select * into';
  const i=s.indexOf(needle);if(i<0)throw Error('Missing insertion '+name);
  s=s.slice(0,i)+` perform arena_private.lock_match(${lock});\n perform arena_private.decide_match(${lock});\n`+s.slice(i);
 }else if(name==='payment_confirm_refund'){
  s=s.replace(' perform 1 from checkout_orders where id=r.order_id for update;',
    ' perform arena_private.lock_payment_match(r.order_id);\n perform 1 from checkout_orders where id=r.order_id for update;');
 }else{
  s=s.replace(' select * into strict o from checkout_orders where id=p_order for update;',
    ' perform arena_private.lock_payment_match(p_order);\n select * into strict o from checkout_orders where id=p_order for update;');
 }
 parts.push(s);
}
fs.writeFileSync('supabase/migrations/202610080102_phase3_rpc_lock_order.sql',
 '-- Phase 3: retain Phase 1/2 contracts, enforce arena -> match -> order lock order.\nbegin;\n'+parts.join('\n\n')+`
create or replace function public.finalize_my_completed_events()
returns void language plpgsql security definer set search_path=public as $$
declare r record;begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 update bookings set status='previous' where user_id=auth.uid() and status in('upcoming','current') and ends_at<=now();
 for r in select id from matches where host_id=auth.uid() and status in('upcoming','confirmed','current') and ends_at<=now() order by arena_id,id loop
  perform arena_private.lock_match(r.id);
  perform arena_private.decide_match(r.id);
  update matches set status='previous' where id=r.id and status<>'cancelled';
 end loop;
end $$;
commit;
`);
