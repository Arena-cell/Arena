// Generates only NEW, unapplied policy boundaries; immutable prior sources stay intact.
const fs=require('node:fs'),path=require('node:path');
process.chdir(path.resolve(__dirname,'../..'));
const read=f=>fs.readFileSync('supabase/migrations/'+f,'utf8');
function fn(file,schema,name){const m=read(file).match(new RegExp('create (?:or replace )?function '+schema.replace('.','\\.')+'\\.'+name+'\\([\\s\\S]*?end \\$\\$;','i'));if(!m)throw Error(name);return m[0].replace(/^create function/,'create or replace function');}
function replace(s,a,b){if(!s.includes(a))throw Error('Missing source '+a);return s.replace(a,b);}
let fulfill=fn('202610040002_phase2_checkout.sql','arena_private','fulfill_order');
fulfill=replace(fulfill,' if o.fulfillment_status=\'fulfilled\' then return;end if;'," if o.entitlement_revoked_at is not null or o.cancellation_requested_at is not null then raise exception 'ENTITLEMENT_REVOKED';end if;\n if o.fulfillment_status='fulfilled' then return;end if;");
fulfill=replace(fulfill,"and fulfillment_status='fulfilled') then raise exception 'SEAT_UNAVAILABLE'","and fulfillment_status='fulfilled' and entitlement_revoked_at is null) then raise exception 'SEAT_UNAVAILABLE'");
let participant=fn('202610080102_phase3_rpc_lock_order.sql','public','create_participant_checkout');
participant=replace(participant," perform arena_private.lock_match(p_match);"," if prior is not null then select * into strict o from checkout_orders where id=(prior->>'id')::uuid and user_id=u;return to_jsonb(o);end if;\n perform arena_private.lock_match(p_match);");
participant=replace(participant," if host_order.payment_status<>'paid' or host_order.fulfillment_status<>'fulfilled' then raise exception 'HOST_PAYMENT_REQUIRED';end if;", " if not ((host_order.payment_status='paid' and host_order.fulfillment_status='fulfilled') or (m.payment_mode='pay_individually' and host_order.entitlement_revoked_at is not null and host_order.cancellation_policy_reason='MATCH_WITHDRAWAL_FULL_REFUND' and host_order.payment_status in('paid','partially_refunded','refunded'))) then raise exception 'HOST_PAYMENT_REQUIRED';end if;");
participant=replace(participant,"and user_id=u and fulfillment_status<>'cancelled';","and user_id=u and fulfillment_status<>'cancelled' and entitlement_revoked_at is null;");
participant=replace(participant,'generate_series(1,m.max_players-1)','generate_series(0,m.max_players-1)');
participant=replace(participant,"x.fulfillment_status<>'cancelled')", "x.fulfillment_status<>'cancelled' and x.entitlement_revoked_at is null)");
let entitlement=fn('202610040003_phase2_payment_boundaries.sql','public','enforce_match_payment_entitlement');
entitlement=replace(entitlement,"and payment_status='paid' and (match_id=m.id or id=m.checkout_order_id)","and payment_status='paid' and entitlement_revoked_at is null and not exists(select 1 from payment_refunds r where r.order_id=checkout_orders.id and r.status<>'failed') and (match_id=m.id or id=m.checkout_order_id)");
let decide=fn('202610080101_phase3_match_decisions.sql','arena_private','decide_match');
decide=replace(decide,"where id=m.checkout_order_id and fulfillment_status='fulfilled' and payment_status='paid') then return 'pending';end if;", "where id=m.checkout_order_id and ((fulfillment_status='fulfilled' and payment_status='paid') or (m.payment_mode='pay_individually' and entitlement_revoked_at is not null and cancellation_policy_reason='MATCH_WITHDRAWAL_FULL_REFUND' and payment_status in('paid','partially_refunded','refunded')))) then return 'pending';end if;");
let available=fn('202610040002_phase2_checkout.sql','arena_private','addon_available');
available=replace(available,"o.fulfillment_status='fulfilled'","o.fulfillment_status in('fulfilled','refund_required') and b.released_at is null");
let catalog=fn('202610040002_phase2_checkout.sql','public','admin_set_arena_addon');
catalog=replace(catalog,"o.fulfillment_status='fulfilled'","o.fulfillment_status in('fulfilled','refund_required') and b.released_at is null");
let summary=fn('202610040005_phase2_match_summary.sql','public','match_payment_summary');
summary=replace(summary,'generate_series(1,m.max_players-1)','generate_series(0,m.max_players-1)');
summary=replace(summary,"o.fulfillment_status<>'cancelled')", "o.fulfillment_status<>'cancelled' and o.entitlement_revoked_at is null)");
fs.writeFileSync('supabase/migrations/202610090102_phase3_refund_entitlement_boundaries.sql','-- New policy boundaries preserving pricing/provider contracts.\nbegin;\n'+[fulfill,participant,entitlement,decide,available,catalog,summary].join('\n\n')+'\ncommit;\n');
console.log('Prepared new 202610090102 boundaries.');
