-- Manual evidence-backed accounting only: no bank API, no payment/refund success.
begin;
create table arena_private.owner_bank_accounts (
  owner_id uuid primary key references auth.users(id),bank_name text not null,
  holder_name text not null,account_number text not null,
  verified boolean not null default false,evidence_reference text not null,
  updated_by uuid not null references auth.users(id),updated_at timestamptz not null default clock_timestamp(),
  check(length(account_number) between 6 and 40)
);
create table public.finance_bank_settlements (
  id uuid primary key default gen_random_uuid(),order_id uuid not null references public.checkout_orders(id),
  request_key uuid not null unique,bank_reference text not null unique,evidence_reference text not null,
  settled_at timestamptz not null,gross_baisa bigint not null check(gross_baisa>=0),
  gateway_fee_baisa bigint not null check(gateway_fee_baisa>=0),
  gateway_fee_refunded_baisa bigint not null check(gateway_fee_refunded_baisa>=0),
  refund_debit_baisa bigint not null check(refund_debit_baisa>=0),
  bank_net_baisa bigint not null,recorded_by uuid not null references auth.users(id),
  recorded_at timestamptz not null default clock_timestamp(),
  check(bank_net_baisa=gross_baisa-gateway_fee_baisa+gateway_fee_refunded_baisa-refund_debit_baisa),
  check(gross_baisa>0 or gateway_fee_refunded_baisa>0 or refund_debit_baisa>0)
);
create table public.finance_company_bank_funding (
  id uuid primary key default gen_random_uuid(),request_key uuid not null unique,
  bank_reference text not null unique,evidence_reference text not null,
  received_at timestamptz not null,amount_baisa bigint not null check(amount_baisa>0),
  recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp()
);
create table public.owner_bank_transfers (
  id uuid primary key default gen_random_uuid(),owner_id uuid not null references auth.users(id),
  request_key uuid not null unique,bank_reference text not null unique,evidence_reference text not null,
  transferred_at timestamptz not null,amount_baisa bigint not null check(amount_baisa>0),
  recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp()
);
create table public.owner_bank_transfer_allocations (
  transfer_id uuid not null references public.owner_bank_transfers(id),
  snapshot_id uuid not null references public.booking_financial_snapshots(id),
  amount_baisa bigint not null check(amount_baisa>0),primary key(transfer_id,snapshot_id)
);
create table arena_private.owner_transfer_bank_details (
  transfer_id uuid primary key references public.owner_bank_transfers(id),
  bank_name text not null,holder_name text not null,account_number text not null
);
revoke all on arena_private.owner_bank_accounts,arena_private.owner_transfer_bank_details from public,anon,authenticated;

-- The same bank statement line cannot be counted once as a gateway settlement
-- and again as company funding (or as an unrelated outgoing transfer).
create table arena_private.finance_bank_reference_claims (
  reference text primary key,record_kind text not null,record_id uuid not null,
  unique(record_kind,record_id)
);
insert into arena_private.finance_bank_reference_claims
 select bank_reference,'finance_bank_settlements',id from public.finance_bank_settlements
 union all select bank_reference,'finance_company_bank_funding',id from public.finance_company_bank_funding
 union all select bank_reference,'owner_bank_transfers',id from public.owner_bank_transfers;
revoke all on arena_private.finance_bank_reference_claims from public,anon,authenticated;
create function arena_private.claim_financial_bank_reference() returns trigger
language plpgsql security definer set search_path=pg_catalog as $$begin
 insert into arena_private.finance_bank_reference_claims values(upper(trim(new.bank_reference)),tg_table_name,new.id);
 return new;
end$$;
create trigger claim_financial_bank_reference before insert on public.finance_bank_settlements
for each row execute function arena_private.claim_financial_bank_reference();
create trigger claim_financial_bank_reference before insert on public.finance_company_bank_funding
for each row execute function arena_private.claim_financial_bank_reference();
create trigger claim_financial_bank_reference before insert on public.owner_bank_transfers
for each row execute function arena_private.claim_financial_bank_reference();

-- Accounting records are append-only; corrections require an explicit future
-- reversal workflow, never silent editing of an executed bank movement.
do $$declare t text;begin
 foreach t in array array['finance_bank_settlements','finance_company_bank_funding','owner_bank_transfers','owner_bank_transfer_allocations'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy finance_read on public.%I for select to authenticated using(public.my_finance_access())',t);
  execute format('create trigger immutable_bank_record before update or delete on public.%I for each row execute function arena_private.immutable_finance_snapshot()',t);
 end loop;
end$$;

create function arena_private.require_finance_confirmation(p_confirmed boolean,p_reference text,p_evidence text,p_date timestamptz)
returns void language plpgsql stable set search_path=public,pg_temp as $$begin
 if not public.my_finance_access() then raise exception 'FINANCE_ADMIN_ONLY' using errcode='42501';end if;
 if p_confirmed is distinct from true then raise exception 'EXTERNAL_CONFIRMATION_REQUIRED';end if;
 if p_reference is null or length(trim(p_reference)) not between 3 and 120 or p_evidence is null or length(trim(p_evidence)) not between 3 and 240
 or p_date is null or p_date>clock_timestamp()+interval '5 minutes' then raise exception 'BANK_EVIDENCE_REQUIRED';end if;
end$$;
create function public.finance_save_owner_bank_account(p_owner uuid,p_bank text,p_holder text,p_account text,p_evidence text,p_confirmed boolean)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare normalized text:=upper(regexp_replace(p_account,'\s','','g'));begin
 perform arena_private.require_finance_confirmation(p_confirmed,'bank-account-verification',p_evidence,clock_timestamp());
 if normalized is null or normalized!~'^[A-Z0-9]{6,40}$' or nullif(trim(p_bank),'') is null or nullif(trim(p_holder),'') is null then raise exception 'INVALID_BANK_ACCOUNT';end if;
 if not exists(select 1 from arenas where owner_id=p_owner) and not exists(select 1 from owner_stadium_assignments where user_id=p_owner) then raise exception 'OWNER_NOT_FOUND';end if;
 insert into arena_private.owner_bank_accounts values(p_owner,trim(p_bank),trim(p_holder),normalized,true,trim(p_evidence),auth.uid(),clock_timestamp())
 on conflict(owner_id) do update set bank_name=excluded.bank_name,holder_name=excluded.holder_name,account_number=excluded.account_number,
 verified=true,evidence_reference=excluded.evidence_reference,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
 insert into finance_audit_log(action,actor_id,database_identity,subject_id,details)
 values('verify_owner_bank_account',auth.uid(),session_user,p_owner,jsonb_build_object('last_four',right(normalized,4)));
end$$;
create function public.finance_owner_bank_accounts() returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$begin
 if not public.my_finance_access() then raise exception 'FINANCE_ADMIN_ONLY' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(to_jsonb(b)),'[]') from arena_private.owner_bank_accounts b);
end$$;

create function public.finance_record_bank_settlement(p_order uuid,p_gross bigint,p_fee bigint,p_fee_refunded bigint,p_refund_debit bigint,
 p_date timestamptz,p_reference text,p_evidence text,p_request_key uuid,p_confirmed boolean) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare o checkout_orders%rowtype;prior finance_bank_settlements%rowtype;v_id uuid;tot record;begin
 perform arena_private.require_finance_confirmation(p_confirmed,p_reference,p_evidence,p_date);
 perform pg_advisory_xact_lock(hashtextextended('arena-finance-bank-ledger',0));
 perform arena_private.lock_payment_match(p_order);
 select * into strict o from checkout_orders where id=p_order for update;
 select * into prior from finance_bank_settlements where request_key=p_request_key or bank_reference=upper(trim(p_reference));
 if found then
  if (prior.order_id,prior.gross_baisa,prior.gateway_fee_baisa,prior.gateway_fee_refunded_baisa,prior.refund_debit_baisa,
   prior.settled_at,prior.bank_reference,prior.evidence_reference,prior.request_key) is distinct from
   (p_order,p_gross,p_fee,p_fee_refunded,p_refund_debit,p_date,upper(trim(p_reference)),trim(p_evidence),p_request_key) then raise exception 'DUPLICATE_BANK_REFERENCE_OR_PAYLOAD_MISMATCH';end if;
  return prior.id;
 end if;
 if o.payment_method<>'card' or o.payment_status not in('paid','partially_refunded','refunded') then raise exception 'VERIFIED_CAPTURE_REQUIRED';end if;
 if p_gross is null or p_fee is null or p_fee_refunded is null or p_refund_debit is null or least(p_gross,p_fee,p_fee_refunded,p_refund_debit)<0 or p_request_key is null then raise exception 'INVALID_SETTLEMENT';end if;
 select coalesce(sum(gross_baisa),0) g,coalesce(sum(gateway_fee_baisa),0) f,
 coalesce(sum(gateway_fee_refunded_baisa),0) fr,coalesce(sum(refund_debit_baisa),0) r into tot from finance_bank_settlements where order_id=o.id;
 if tot.g+p_gross>o.amount_due_baisa or tot.f+p_fee>tot.g+p_gross
 or tot.fr+p_fee_refunded>tot.f+p_fee or tot.r+p_refund_debit>o.refunded_amount_baisa then raise exception 'SETTLEMENT_EXCEEDS_VERIFIED_AMOUNT';end if;
 insert into finance_bank_settlements(order_id,request_key,bank_reference,evidence_reference,settled_at,gross_baisa,gateway_fee_baisa,gateway_fee_refunded_baisa,refund_debit_baisa,bank_net_baisa,recorded_by)
 values(o.id,p_request_key,upper(trim(p_reference)),trim(p_evidence),p_date,p_gross,p_fee,p_fee_refunded,p_refund_debit,p_gross-p_fee+p_fee_refunded-p_refund_debit,auth.uid()) returning id into v_id;
 insert into finance_audit_log(action,actor_id,database_identity,subject_id,details)
 values('record_verified_bank_settlement',auth.uid(),session_user,v_id,jsonb_build_object('order_id',o.id,'gross_baisa',p_gross,'actual_gateway_fee_baisa',p_fee));
 return v_id;
end$$;
create function public.finance_record_company_bank_funding(p_amount bigint,p_date timestamptz,p_reference text,p_evidence text,p_request_key uuid,p_confirmed boolean)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare prior finance_company_bank_funding%rowtype;v_id uuid;begin
 perform arena_private.require_finance_confirmation(p_confirmed,p_reference,p_evidence,p_date);
 perform pg_advisory_xact_lock(hashtextextended('arena-finance-bank-ledger',0));
 select * into prior from finance_company_bank_funding where request_key=p_request_key or bank_reference=upper(trim(p_reference));
 if found then
  if (prior.amount_baisa,prior.received_at,prior.bank_reference,prior.evidence_reference,prior.request_key) is distinct from
   (p_amount,p_date,upper(trim(p_reference)),trim(p_evidence),p_request_key) then raise exception 'DUPLICATE_BANK_REFERENCE_OR_PAYLOAD_MISMATCH';end if;
  return prior.id;
 end if;
 insert into finance_company_bank_funding(request_key,bank_reference,evidence_reference,received_at,amount_baisa,recorded_by)
 values(p_request_key,upper(trim(p_reference)),trim(p_evidence),p_date,p_amount,auth.uid()) returning id into v_id;
 insert into finance_audit_log(action,actor_id,database_identity,subject_id,details)
 values('record_company_bank_funding',auth.uid(),session_user,v_id,jsonb_build_object('amount_baisa',p_amount));
 return v_id;
end$$;

alter function arena_private.booking_financial_position(uuid) rename to booking_financial_position_core;
create function arena_private.booking_financial_position(p_snapshot uuid) returns jsonb
language plpgsql stable set search_path=public,pg_temp as $$
declare p jsonb;s booking_financial_snapshots%rowtype;o checkout_orders%rowtype;
 settled bigint;fee bigint;fee_returned bigint;transferred bigint;bank_pending boolean;hold text;due bigint;begin
 p:=arena_private.booking_financial_position_core(p_snapshot);
 select * into strict s from booking_financial_snapshots where id=p_snapshot;
 select * into strict o from checkout_orders where id=s.origin_order_id;
 select coalesce(sum(b.gross_baisa),0),sum(b.gateway_fee_baisa),sum(b.gateway_fee_refunded_baisa)
 into settled,fee,fee_returned from finance_bank_settlements b join checkout_orders x on x.id=b.order_id
 where x.id=o.id or(o.match_id is not null and x.match_id=o.match_id and x.purpose='participant');
 select coalesce(sum(amount_baisa),0) into transferred from owner_bank_transfer_allocations where snapshot_id=s.id;
 due:=(p->>'owner_net_baisa')::bigint;hold:=p->>'hold_reason';
 if hold is null and settled<(p->>'collected_baisa')::bigint then hold:='BANK_SETTLEMENT_PENDING';end if;
 if transferred>due and hold is null then hold:='OWNER_OVERPAYMENT_REVIEW_REQUIRED';end if;
 return p||jsonb_build_object('settled_gross_baisa',settled,'actual_gateway_fee_baisa',fee,
 'gateway_fee_refunded_baisa',fee_returned,'transferred_baisa',transferred,
 'untransferred_baisa',greatest(due-transferred,0),'owner_overpayment_baisa',greatest(transferred-due,0),
 'available_for_transfer_baisa',case when hold is null then greatest(due-transferred,0) else 0 end,
 'hold_reason',hold,'transfer_status',case when transferred=0 and due=0 then 'no_amount_due' when transferred=0 then 'awaiting_transfer' when transferred<due then 'partially_transferred' when transferred=due then 'fully_transferred' else 'adjustment_required' end);
end$$;

create function public.finance_record_executed_transfer(p_owner uuid,p_allocations jsonb,p_date timestamptz,p_reference text,p_evidence text,p_request_key uuid,p_confirmed boolean)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare b arena_private.owner_bank_accounts%rowtype;prior owner_bank_transfers%rowtype;canonical jsonb;prior_alloc jsonb;
 item jsonb;s booking_financial_snapshots%rowtype;position jsonb;amount bigint;total bigint:=0;pool bigint;v_id uuid;begin
 perform arena_private.require_finance_confirmation(p_confirmed,p_reference,p_evidence,p_date);
 if p_allocations is null or jsonb_typeof(p_allocations)<>'array' or jsonb_array_length(p_allocations) not between 1 and 1000 or p_request_key is null then raise exception 'TRANSFER_ALLOCATIONS_REQUIRED';end if;
 select jsonb_agg(x order by x->>'snapshot_id') into canonical from jsonb_array_elements(p_allocations) x;
 if jsonb_array_length(canonical)<>(select count(distinct x->>'snapshot_id') from jsonb_array_elements(canonical) x) then raise exception 'DUPLICATE_TRANSFER_ALLOCATION';end if;
 perform pg_advisory_xact_lock(hashtextextended('arena-finance-bank-ledger',0));
 select * into prior from owner_bank_transfers where request_key=p_request_key or bank_reference=upper(trim(p_reference));
 if found then
  select jsonb_agg(jsonb_build_object('snapshot_id',snapshot_id,'amount_baisa',amount_baisa) order by snapshot_id::text) into prior_alloc from owner_bank_transfer_allocations where transfer_id=prior.id;
  if (prior.owner_id,prior.transferred_at,prior.bank_reference,prior.evidence_reference,prior.request_key,prior_alloc) is distinct from
   (p_owner,p_date,upper(trim(p_reference)),trim(p_evidence),p_request_key,canonical) then raise exception 'DUPLICATE_BANK_REFERENCE_OR_PAYLOAD_MISMATCH';end if;
  return prior.id;
 end if;
 select * into strict b from arena_private.owner_bank_accounts where owner_id=p_owner and verified for share;
 for item in select value from jsonb_array_elements(canonical) loop
  if jsonb_typeof(item->'amount_baisa') is distinct from 'number' or item->>'amount_baisa'!~'^[1-9][0-9]{0,11}$' then raise exception 'INVALID_TRANSFER_AMOUNT';end if;
  amount:=(item->>'amount_baisa')::bigint;
  select * into strict s from booking_financial_snapshots where id=(item->>'snapshot_id')::uuid and owner_id=p_owner for update;
  position:=arena_private.booking_financial_position(s.id);
  if amount>(position->>'available_for_transfer_baisa')::bigint then raise exception 'TRANSFER_EXCEEDS_AVAILABLE_ENTITLEMENT';end if;
  total:=total+amount;
 end loop;
 select (select coalesce(sum(bank_net_baisa),0) from finance_bank_settlements)
 +(select coalesce(sum(amount_baisa),0) from finance_company_bank_funding)
 -(select coalesce(sum(amount_baisa),0) from owner_bank_transfers) into pool;
 if total>pool then raise exception 'VERIFIED_BANK_FUNDS_INSUFFICIENT';end if;
 insert into owner_bank_transfers(owner_id,request_key,bank_reference,evidence_reference,transferred_at,amount_baisa,recorded_by)
 values(p_owner,p_request_key,upper(trim(p_reference)),trim(p_evidence),p_date,total,auth.uid()) returning id into v_id;
 insert into arena_private.owner_transfer_bank_details values(v_id,b.bank_name,b.holder_name,b.account_number);
 insert into owner_bank_transfer_allocations select v_id,(x->>'snapshot_id')::uuid,(x->>'amount_baisa')::bigint from jsonb_array_elements(canonical) x;
 insert into finance_audit_log(action,actor_id,database_identity,subject_id,details)
 values('record_executed_owner_transfer',auth.uid(),session_user,v_id,jsonb_build_object('amount_baisa',total,'owner_id',p_owner));
 return v_id;
end$$;

-- Extend the existing Owner allowlist; never expose internal/provider/bank fields.
do $$declare src text;needle text:=$n$'hold_reason',p->'hold_reason','lines',p->'lines'$n$;begin
 select pg_get_functiondef('public.booking_finance_summary(uuid)'::regprocedure) into src;
 if position(needle in src)=0 then raise exception 'OWNER_FINANCE_SOURCE_DRIFT';end if;
 execute replace(src,needle,$n$'hold_reason',p->'hold_reason','lines',p->'lines',
 'transferred_baisa',p->'transferred_baisa','untransferred_baisa',p->'untransferred_baisa',
 'owner_overpayment_baisa',p->'owner_overpayment_baisa','transfer_status',p->'transfer_status'$n$);
end$$;
revoke all on function public.finance_save_owner_bank_account(uuid,text,text,text,text,boolean),public.finance_owner_bank_accounts(),
 public.finance_record_bank_settlement(uuid,bigint,bigint,bigint,bigint,timestamptz,text,text,uuid,boolean),
 public.finance_record_company_bank_funding(bigint,timestamptz,text,text,uuid,boolean),
 public.finance_record_executed_transfer(uuid,jsonb,timestamptz,text,text,uuid,boolean) from public,anon,authenticated;
grant execute on function public.finance_save_owner_bank_account(uuid,text,text,text,text,boolean),public.finance_owner_bank_accounts(),
 public.finance_record_bank_settlement(uuid,bigint,bigint,bigint,bigint,timestamptz,text,text,uuid,boolean),
 public.finance_record_company_bank_funding(bigint,timestamptz,text,text,uuid,boolean),
 public.finance_record_executed_transfer(uuid,jsonb,timestamptz,text,text,uuid,boolean) to authenticated;
revoke all on all functions in schema arena_private from public,anon,authenticated;
commit;
