-- Internal calculation primitive only. Does not activate a policy, backfill
-- historical orders, collect commission, record bank settlement or pay owners.
begin;
create function arena_private.contractual_commission_preview(
  p_base_baisa bigint, p_addons jsonb default '[]'::jsonb,
  p_discount_baisa bigint default 0, p_refunded_baisa bigint default 0
) returns jsonb language plpgsql immutable set search_path=pg_catalog as $$
declare
  item jsonb; code text; amount bigint;
  eligible bigint:=p_base_baisa; water bigint:=0; gross bigint:=p_base_baisa;
  commission bigint; gateway_allocation bigint;
begin
  if p_base_baisa is null or p_base_baisa not between 0 and 5000000000
    or p_addons is null or jsonb_typeof(p_addons)<>'array'
    or jsonb_array_length(p_addons)>100
    or p_discount_baisa is null or p_discount_baisa<0
    or p_refunded_baisa is null or p_refunded_baisa<0 then
    raise exception 'INVALID_FINANCE_PREVIEW';
  end if;
  -- No silent choice of discount funding or partial-refund allocation.
  if p_discount_baisa<>0 then raise exception 'FINANCE_DISCOUNT_POLICY_REQUIRED';end if;
  if p_refunded_baisa<>0 then raise exception 'FINANCE_REFUND_POLICY_REQUIRED';end if;
  for item in select value from jsonb_array_elements(p_addons) loop
    code:=item->>'addon_code';
    if jsonb_typeof(item)<>'object' or code is null
      or code!~'^[a-z][a-z0-9_]{1,39}$'
      or jsonb_typeof(item->'line_amount_baisa')<>'number'
      or item->>'line_amount_baisa' is null
      or item->>'line_amount_baisa'!~'^[0-9]{1,10}$' then
      raise exception 'INVALID_FINANCE_ADDON';
    end if;
    amount:=(item->>'line_amount_baisa')::bigint;
    if amount>5000000000 then raise exception 'INVALID_FINANCE_ADDON';end if;
    gross:=gross+amount;
    if code='water' then water:=water+amount;
    else eligible:=eligible+amount;end if;
  end loop;
  -- Integer baisa; nearest baisa, half up. Internal allocations reconcile
  -- exactly to the rounded 8% contractual commission.
  commission:=(eligible*800+5000)/10000;
  gateway_allocation:=(eligible*250+5000)/10000;
  return jsonb_build_object(
    'preview_only',true,'currency','OMR','policy_version','proposed_20261024',
    'gross_baisa',gross,'eligible_baisa',eligible,'water_baisa',water,
    'commission_basis_points',800,'commission_baisa',commission,
    'owner_net_baisa',gross-commission,
    'internal_gateway_allocation_baisa',gateway_allocation,
    'internal_arena_allocation_baisa',commission-gateway_allocation,
    'actual_gateway_fee_baisa',null,'actual_gateway_fee_verified',false,
    'rounding','nearest_baisa_half_up');
end $$;
revoke all on function arena_private.contractual_commission_preview(bigint,jsonb,bigint,bigint)
  from public,anon,authenticated;

create function arena_private.owner_commission_projection(p_preview jsonb)
returns jsonb language sql immutable set search_path=pg_catalog as $$
  select jsonb_build_object('preview_only',true,'currency',p_preview->'currency',
    'gross_baisa',p_preview->'gross_baisa','eligible_baisa',p_preview->'eligible_baisa',
    'water_baisa',p_preview->'water_baisa','commission_basis_points',p_preview->'commission_basis_points',
    'commission_baisa',p_preview->'commission_baisa','owner_net_baisa',p_preview->'owner_net_baisa');
$$;
revoke all on function arena_private.owner_commission_projection(jsonb) from public,anon,authenticated;
commit;
