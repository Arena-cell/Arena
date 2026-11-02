-- Calculates approved cumulative per-line refunds only. No provider calls,
-- payment state changes, payout records, or guessed refund allocations.
begin;
create function arena_private.itemized_refund_preview(p_lines jsonb)
returns jsonb language plpgsql immutable set search_path=pg_catalog as $$
declare
  item jsonb; seen text[]:='{}'; key text; code text; original bigint; refunded bigint;
  base_count integer:=0; gross bigint:=0; refunds bigint:=0;
  original_eligible bigint:=0; remaining_eligible bigint:=0;
  original_commission bigint; remaining_commission bigint;
begin
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines) not between 1 and 101 then
    raise exception 'APPROVED_REFUND_LINES_REQUIRED';
  end if;
  for item in select value from jsonb_array_elements(p_lines) loop
    key:=item->>'line_id';code:=item->>'addon_code';
    if jsonb_typeof(item)<>'object' or key is null or char_length(key) not between 1 and 100
      or key=any(seen) or item->>'line_type' is null or item->>'line_type' not in('base','addon')
      or jsonb_typeof(item->'original_baisa') is distinct from 'number'
      or jsonb_typeof(item->'refunded_baisa') is distinct from 'number'
      or item->>'original_baisa'!~'^[0-9]{1,10}$'
      or item->>'refunded_baisa'!~'^[0-9]{1,10}$' then
      raise exception 'INVALID_APPROVED_REFUND_LINE';
    end if;
    seen:=array_append(seen,key);
    original:=(item->>'original_baisa')::bigint;refunded:=(item->>'refunded_baisa')::bigint;
    if original>5000000000 or refunded>original then raise exception 'REFUND_EXCEEDS_LINE';end if;
    if item->>'line_type'='base' then
      base_count:=base_count+1;
      if code is not null then raise exception 'INVALID_BASE_LINE';end if;
    elsif code is null or code!~'^[a-z][a-z0-9_]{1,39}$' then
      raise exception 'INVALID_ADDON_CODE';
    end if;
    gross:=gross+original;refunds:=refunds+refunded;
    if item->>'line_type'='base' or code<>'water' then
      original_eligible:=original_eligible+original;
      remaining_eligible:=remaining_eligible+original-refunded;
    end if;
  end loop;
  if base_count<>1 then raise exception 'EXACTLY_ONE_BASE_LINE_REQUIRED';end if;
  original_commission:=(original_eligible*800+5000)/10000;
  remaining_commission:=(remaining_eligible*800+5000)/10000;
  return jsonb_build_object('preview_only',true,'currency','OMR',
    'original_gross_baisa',gross,'approved_refund_baisa',refunds,
    'remaining_gross_baisa',gross-refunds,'remaining_eligible_baisa',remaining_eligible,
    'original_commission_baisa',original_commission,'commission_baisa',remaining_commission,
    'commission_reversal_baisa',original_commission-remaining_commission,
    'owner_net_baisa',gross-refunds-remaining_commission,
    'actual_gateway_fee_baisa',null,'gateway_refunded_fee_baisa',null);
end $$;
revoke all on function arena_private.itemized_refund_preview(jsonb) from public,anon,authenticated;
commit;
