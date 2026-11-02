begin;
create table public.finance_audit_log (
  id bigint generated always as identity primary key,
  action text not null,actor_id uuid references auth.users(id),database_identity text not null,
  subject_id uuid,details jsonb not null default '{}',created_at timestamptz not null default clock_timestamp()
);
alter table public.finance_audit_log enable row level security;
revoke all on public.finance_audit_log from public,anon,authenticated;
grant select on public.finance_audit_log to authenticated;
create policy finance_audit_read on public.finance_audit_log for select to authenticated using(public.my_finance_access());
create trigger immutable_finance_audit before update or delete on public.finance_audit_log
for each row execute function arena_private.immutable_finance_snapshot();
create function arena_private.audit_financial_configuration() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$begin
 insert into finance_audit_log(action,actor_id,database_identity,subject_id,details)
 values(tg_table_name||'_'||lower(tg_op),auth.uid(),session_user,
 case when tg_table_name='finance_admins' then (to_jsonb(new)->>'user_id')::uuid else (to_jsonb(new)->>'id')::uuid end,
 jsonb_build_object('before',case when tg_op='UPDATE' then to_jsonb(old) else null end,'after',to_jsonb(new)));
 return new;
end$$;
create trigger audit_discount_configuration after insert or update on public.discount_campaigns
for each row execute function arena_private.audit_financial_configuration();
create trigger audit_finance_role after insert or update on arena_private.finance_admins
for each row execute function arena_private.audit_financial_configuration();

create table public.finance_refund_batches (
  refund_id uuid primary key references public.payment_refunds(id),
  request_key uuid not null unique,payload jsonb not null,
  approved_by uuid not null references auth.users(id),approved_at timestamptz not null default clock_timestamp()
);
create table public.finance_refund_lines (
  refund_id uuid not null references public.finance_refund_batches(refund_id),
  line_id uuid not null references public.booking_financial_lines(id),
  gross_reversal_baisa bigint not null check(gross_reversal_baisa>=0),
  arena_discount_reversal_baisa bigint not null check(arena_discount_reversal_baisa>=0),
  owner_discount_reversal_baisa bigint not null check(owner_discount_reversal_baisa>=0),
  cash_refund_baisa bigint not null check(cash_refund_baisa>=0),
  primary key(refund_id,line_id),
  check(gross_reversal_baisa=cash_refund_baisa+arena_discount_reversal_baisa+owner_discount_reversal_baisa)
);
create trigger immutable_refund_batch before update or delete on public.finance_refund_batches
for each row execute function arena_private.immutable_finance_snapshot();
create trigger immutable_refund_line before update or delete on public.finance_refund_lines
for each row execute function arena_private.immutable_finance_snapshot();
alter table public.finance_refund_batches enable row level security;
alter table public.finance_refund_lines enable row level security;
revoke all on public.finance_refund_batches,public.finance_refund_lines from public,anon,authenticated;
grant select on public.finance_refund_batches,public.finance_refund_lines to authenticated;
create policy admin_refund_batches_read on public.finance_refund_batches for select to authenticated using(public.is_platform_admin());
create policy admin_refund_lines_read on public.finance_refund_lines for select to authenticated using(public.is_platform_admin());

create function arena_private.financial_origin(p_order uuid) returns uuid
language sql stable set search_path=public,pg_temp as $$
 select case when o.purpose='participant' then m.checkout_order_id else o.id end
 from checkout_orders o left join matches m on m.id=o.match_id where o.id=p_order;
$$;
create function public.finance_allocate_refund(p_refund uuid,p_lines jsonb,p_request_key uuid) returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare r payment_refunds%rowtype;s booking_financial_snapshots%rowtype;l booking_financial_lines%rowtype;
 item jsonb;canonical jsonb;prior finance_refund_batches%rowtype;used record;
 gross bigint;ad bigint;od bigint;cash bigint;cash_total bigint:=0;
begin
 if not public.my_finance_access() then raise exception 'FINANCE_ADMIN_ONLY' using errcode='42501';end if;
 if p_request_key is null or p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines) not between 1 and 101 then raise exception 'APPROVED_REFUND_LINES_REQUIRED';end if;
 select jsonb_agg(x order by x->>'line_id') into canonical from jsonb_array_elements(p_lines) x;
 select * into strict r from payment_refunds where id=p_refund;
 perform arena_private.lock_payment_match(r.order_id);
 select * into strict r from payment_refunds where id=p_refund for update;
 if r.status='failed' then raise exception 'REFUND_FAILED';end if;
 select * into s from booking_financial_snapshots where origin_order_id=arena_private.financial_origin(r.order_id) for update;
 if not found then raise exception 'HISTORICAL_FINANCE_REVIEW_REQUIRED';end if;
 select * into prior from finance_refund_batches where refund_id=r.id or request_key=p_request_key;
 if found then
  if prior.refund_id<>r.id or prior.request_key<>p_request_key or prior.payload<>canonical then raise exception 'IDEMPOTENCY_PAYLOAD_MISMATCH';end if;
  return;
 end if;
 if (select count(*) from jsonb_array_elements(canonical))<>(select count(distinct x->>'line_id') from jsonb_array_elements(canonical) x) then raise exception 'DUPLICATE_REFUND_LINE';end if;
 insert into finance_refund_batches values(r.id,p_request_key,canonical,auth.uid(),clock_timestamp());
 for item in select value from jsonb_array_elements(canonical) loop
  if jsonb_typeof(item->'gross_reversal_baisa') is distinct from 'number'
    or jsonb_typeof(item->'arena_discount_reversal_baisa') is distinct from 'number'
    or jsonb_typeof(item->'owner_discount_reversal_baisa') is distinct from 'number'
    or jsonb_typeof(item->'cash_refund_baisa') is distinct from 'number'
    or item->>'gross_reversal_baisa'!~'^[0-9]{1,12}$' or item->>'arena_discount_reversal_baisa'!~'^[0-9]{1,12}$'
    or item->>'owner_discount_reversal_baisa'!~'^[0-9]{1,12}$' or item->>'cash_refund_baisa'!~'^[0-9]{1,12}$' then raise exception 'INVALID_REFUND_ALLOCATION';end if;
  select * into strict l from booking_financial_lines where id=(item->>'line_id')::uuid and snapshot_id=s.id;
  gross:=(item->>'gross_reversal_baisa')::bigint;ad:=(item->>'arena_discount_reversal_baisa')::bigint;
  od:=(item->>'owner_discount_reversal_baisa')::bigint;cash:=(item->>'cash_refund_baisa')::bigint;
  select coalesce(sum(x.gross_reversal_baisa),0) g,coalesce(sum(x.arena_discount_reversal_baisa),0) a,
   coalesce(sum(x.owner_discount_reversal_baisa),0) o,coalesce(sum(x.cash_refund_baisa),0) c into used
   from finance_refund_lines x join payment_refunds f on f.id=x.refund_id where x.line_id=l.id and f.status<>'failed';
  if gross+used.g>l.gross_baisa or ad+used.a>l.arena_discount_baisa or od+used.o>l.owner_discount_baisa or cash+used.c>l.paid_baisa then raise exception 'REFUND_EXCEEDS_LINE';end if;
  insert into finance_refund_lines values(r.id,l.id,gross,ad,od,cash);cash_total:=cash_total+cash;
 end loop;
 if cash_total<>r.amount_baisa then raise exception 'REFUND_ALLOCATION_TOTAL_MISMATCH';end if;
 insert into finance_audit_log(action,actor_id,database_identity,subject_id,details)
 values('approve_refund_line_allocation',auth.uid(),session_user,r.id,jsonb_build_object('cash_baisa',cash_total,'request_key',p_request_key));
end$$;

create function arena_private.booking_financial_position(p_snapshot uuid) returns jsonb
language plpgsql stable set search_path=public,pg_temp as $$
declare s booking_financial_snapshots%rowtype;o checkout_orders%rowtype;rev record;
 captured bigint;refunded bigint;unallocated integer;pending integer;hold text;
 remaining_eligible bigint;commission bigint;owner_due bigint;remaining_ad bigint;
begin
 select * into strict s from booking_financial_snapshots where id=p_snapshot;
 select * into strict o from checkout_orders where id=s.origin_order_id;
 select coalesce(sum(amount_due_baisa),0),coalesce(sum(refunded_amount_baisa),0) into captured,refunded
 from checkout_orders x where (x.id=o.id or (o.match_id is not null and x.match_id=o.match_id and x.purpose='participant'))
 and x.payment_method='card' and x.payment_status in('paid','partially_refunded','refunded');
 select count(*) filter(where f.status='succeeded' and not exists(select 1 from finance_refund_batches b where b.refund_id=f.id)),
 count(*) filter(where f.status in('requested','processing')) into unallocated,pending
 from payment_refunds f join checkout_orders x on x.id=f.order_id
 where x.id=o.id or (o.match_id is not null and x.match_id=o.match_id and x.purpose='participant');
 select coalesce(sum(x.gross_reversal_baisa),0) gross,
 coalesce(sum(x.gross_reversal_baisa) filter(where l.line_type='base' or l.addon_code<>'water'),0) eligible,
 coalesce(sum(x.arena_discount_reversal_baisa),0) ad,coalesce(sum(x.owner_discount_reversal_baisa),0) od
 into rev from finance_refund_lines x join booking_financial_lines l on l.id=x.line_id
 join payment_refunds f on f.id=x.refund_id where l.snapshot_id=s.id and f.status='succeeded';
 remaining_eligible:=s.eligible_baisa-rev.eligible;commission:=(remaining_eligible*800+5000)/10000;
 remaining_ad:=s.arena_discount_baisa-rev.ad;
 owner_due:=s.gross_baisa-rev.gross-commission-(s.owner_discount_baisa-rev.od);
 hold:=case when unallocated>0 then 'REFUND_LINE_ALLOCATION_REQUIRED'
  when pending>0 then 'REFUND_IN_PROGRESS'
  when s.owner_id is null then 'OWNER_PAYEE_REQUIRED'
  when o.fulfillment_status='refund_required' then 'PAYMENT_REQUIRES_REFUND'
  when captured<o.total_amount_baisa then 'PAYMENT_NOT_FULLY_COLLECTED'
  when owner_due<0 or remaining_ad>commission-(remaining_eligible*250+5000)/10000 then 'FINANCIAL_REVIEW_REQUIRED'
  else null end;
 return jsonb_build_object('snapshot_id',s.id,'origin_order_id',o.id,'policy_version',s.policy_version,
 'currency','OMR','gross_baisa',s.gross_baisa,'base_baisa',o.base_amount_baisa,'water_baisa',s.water_baisa,
 'discount_baisa',s.discount_baisa,'arena_discount_baisa',s.arena_discount_baisa,'owner_discount_baisa',s.owner_discount_baisa,
 'arena_discount_reversed_baisa',rev.ad,'owner_discount_reversed_baisa',rev.od,
 'eligible_baisa',s.eligible_baisa,'commission_baisa',commission,'original_commission_baisa',s.commission_baisa,
 'commission_reversed_baisa',s.commission_baisa-commission,'owner_net_baisa',greatest(owner_due,0),
 'collected_baisa',captured,'refunded_baisa',refunded,'hold_reason',hold,
 'remaining_arena_discount_baisa',remaining_ad,
 'internal_gateway_allocation_baisa',(remaining_eligible*250+5000)/10000,
 'internal_arena_allocation_baisa',commission-(remaining_eligible*250+5000)/10000,
 'actual_gateway_fee_baisa',null,
 'lines',(select coalesce(jsonb_agg(to_jsonb(l) order by l.line_type desc,l.line_key),'[]') from booking_financial_lines l where snapshot_id=s.id));
end$$;

create function public.booking_finance_summary(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare o checkout_orders%rowtype;s booking_financial_snapshots%rowtype;p jsonb;begin
 select * into strict o from checkout_orders where id=arena_private.financial_origin(p_order);
 if not public.is_arena_operator(o.arena_id) then raise exception 'NOT_AUTHORIZED' using errcode='42501';end if;
 select * into s from booking_financial_snapshots where origin_order_id=o.id;
 if not found then return jsonb_build_object('status','historical_not_recalculated','currency','OMR');end if;
 p:=arena_private.booking_financial_position(s.id);
 -- Explicit allowlist: no 2.5/5.5, gateway fee, provider cost or bank data.
 return jsonb_build_object('status','recorded','snapshot_id',s.id,'currency','OMR',
 'gross_baisa',p->'gross_baisa','base_baisa',p->'base_baisa','water_baisa',p->'water_baisa',
 'discount_baisa',p->'discount_baisa','arena_discount_baisa',p->'arena_discount_baisa','owner_discount_baisa',p->'owner_discount_baisa',
 'commission_baisa',p->'commission_baisa','commission_reversed_baisa',p->'commission_reversed_baisa',
 'owner_net_baisa',p->'owner_net_baisa','collected_baisa',p->'collected_baisa','refunded_baisa',p->'refunded_baisa',
 'hold_reason',p->'hold_reason','lines',p->'lines');
end$$;
create function public.admin_booking_finance_summary(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare sid uuid;begin
 if not public.is_platform_admin() then raise exception 'ADMIN_ONLY' using errcode='42501';end if;
 select id into sid from booking_financial_snapshots where origin_order_id=arena_private.financial_origin(p_order);
 if sid is null then return jsonb_build_object('status','historical_not_recalculated');end if;
 return arena_private.booking_financial_position(sid)||jsonb_build_object('status','recorded');
end$$;
revoke all on function public.finance_allocate_refund(uuid,jsonb,uuid),public.booking_finance_summary(uuid),public.admin_booking_finance_summary(uuid) from public,anon,authenticated;
grant execute on function public.finance_allocate_refund(uuid,jsonb,uuid),public.booking_finance_summary(uuid),public.admin_booking_finance_summary(uuid) to authenticated;
revoke all on all functions in schema arena_private from public,anon,authenticated;
commit;
