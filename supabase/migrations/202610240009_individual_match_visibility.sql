-- Read models and existing notification queue; no new push infrastructure.
begin;
create or replace function public.match_lifecycle_summary(p_match uuid) returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare m matches%rowtype;r jsonb;begin
 r:=arena_private.match_lifecycle_summary_before_seats(p_match);select * into strict m from matches where id=p_match;
 if m.individual_policy='seats_24h_2h_v1' then
  r:=r||jsonb_build_object('individual_policy',m.individual_policy,'confirmed_seats',arena_private.individual_paid_seats(m.id,null),
   'confirmation_threshold',m.max_players,'precheck_threshold',(m.max_players::bigint*4+4)/5,'precheck_at',m.precheck_at,
   'precheck_outcome',m.precheck_outcome,'withdrawal_locked',m.decision_outcome='confirmed' or arena_private.match_decision_clock()>=m.decision_at,
   'max_seats_per_user',3);
 else r:=r||jsonb_build_object('individual_policy','legacy_90_80','max_seats_per_user',1);end if;
 return r;
end$$;
create or replace function public.match_payment_summary(p_match uuid) returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp as $$
declare m matches%rowtype;indices integer[];options jsonb:='[]';n integer;r jsonb;o checkout_orders%rowtype;begin
 r:=arena_private.match_payment_summary_before_seats(p_match);select * into strict m from matches where id=p_match;
 if m.individual_policy<>'seats_24h_2h_v1' then return r;end if;
 select * into o from checkout_orders where match_id=m.id and user_id=auth.uid() and fulfillment_status in('pending','fulfilled') and entitlement_revoked_at is null;
 if found then options:=jsonb_build_array(jsonb_build_object('quantity',o.seat_quantity,'amount_baisa',o.amount_due_baisa));
 elsif m.status<>'cancelled' and arena_private.match_decision_clock()<m.decision_at then
  select array_agg(s order by s) into indices from(select s from generate_series(0,m.max_players-1) s where not exists(
   select 1 from checkout_orders x where x.match_id=m.id and x.fulfillment_status in('pending','fulfilled') and x.entitlement_revoked_at is null
    and s=any(coalesce(x.seat_indices,array[x.seat_index]))) order by s limit 3) slots;
  for n in 1..coalesce(cardinality(indices),0) loop options:=options||jsonb_build_object('quantity',n,'amount_baisa',arena_private.seat_total(m.total_amount_baisa,m.max_players,indices[1:n]));end loop;
 end if;
 return r||jsonb_build_object('individual_policy',m.individual_policy,'seat_options',options,
  'next_share_baisa',case when jsonb_array_length(options)>0 then (options->0->>'amount_baisa')::bigint end);
end$$;
create or replace function public.my_match_withdrawal_summary(p_match uuid) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare m matches%rowtype;r jsonb;begin
 r:=arena_private.my_match_withdrawal_summary_before_seats(p_match);select * into strict m from matches where id=p_match;
 if m.individual_policy='seats_24h_2h_v1' then r:=r||jsonb_build_object('individual_policy',m.individual_policy,
  'allowed',m.status<>'cancelled' and m.decision_outcome='pending' and arena_private.match_decision_clock()<m.decision_at
   and exists(select 1 from match_players where match_id=m.id and user_id=auth.uid() and status='joined'),
  'deadline',m.decision_at,'server_now',arena_private.match_decision_clock(),'all_reserved_seats',true,
  'seat_quantity',(select seat_quantity from match_players where match_id=m.id and user_id=auth.uid()));end if;return r;
end$$;
create function public.match_checkout_quote(p_request jsonb) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare q jsonb;capacity integer;quantity integer;mode text;indices integer[];begin
 mode:=p_request->>'payment_mode';capacity:=(p_request->>'capacity')::integer;quantity:=coalesce((p_request->>'seat_quantity')::integer,1);
 if mode is null or mode not in('host_pays_all','pay_individually') or capacity is null or capacity not between 2 and 100 then raise exception 'INVALID_MATCH_PAYMENT';end if;
 q:=public.checkout_quote_with_discount((p_request->>'arena_id')::uuid,(p_request->>'starts_at')::timestamptz,(p_request->>'ends_at')::timestamptz,
  coalesce(p_request->'addons','[]'),null,p_request->>'promo_code');
 if mode='pay_individually' then
  if (p_request->>'starts_at')::timestamptz<=arena_private.match_decision_clock()+interval '24 hours' then raise exception 'INDIVIDUAL_MATCH_REQUIRES_24_HOURS';end if;
  if quantity not between 1 and 3 or quantity>capacity then raise exception 'INVALID_SEAT_QUANTITY';end if;
  if (q->>'total_amount_baisa')::bigint/capacity<100 then raise exception 'CARD_MINIMUM_100_BAISA_PER_PLAYER';end if;
  select array_agg(i order by i) into indices from generate_series(0,quantity-1)i;
  return q||jsonb_build_object('amount_due_baisa',arena_private.seat_total((q->>'total_amount_baisa')::bigint,capacity,indices),
   'individual_policy','seats_24h_2h_v1','seat_quantity',quantity);
 end if;return q||jsonb_build_object('amount_due_baisa',(q->>'total_amount_baisa')::bigint,'seat_quantity',1,'individual_policy','legacy_90_80');
end$$;

create or replace function public.phase3_match_notification() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid;t text;host_cancel boolean;en text;ar text;begin
 if tg_op='INSERT' then perform arena_private.notify(new.host_id,'match_created','match-created:'||new.id,jsonb_build_object('match_id',new.id),'Your match has been created.','تم إنشاء مباراتك.');
 elsif new.decision_outcome is distinct from old.decision_outcome and new.decision_outcome in('confirmed','cancelled') then
  t:='match_'||new.decision_outcome;host_cancel:=new.cancellation_reason='HOST_PAYS_ALL_CREATOR_CANCELLED';
  en:=case when t='match_confirmed' then 'Match confirmed. Withdrawal is now locked.' when host_cancel then 'The host cancelled the match for everyone. Any eligible refund awaits provider confirmation.' else 'Match cancelled: minimum participation was not reached. Any required refund is pending provider processing.' end;
  ar:=case when t='match_confirmed' then 'تأكدت المباراة. لا يمكن الانسحاب الآن.' when host_cancel then 'ألغى المنشئ المباراة للجميع. أي استرداد مستحق ينتظر تأكيد مزود الدفع.' else 'أُلغيت المباراة لعدم اكتمال العدد المطلوب. أي استرداد مستحق ينتظر معالجة مزود الدفع.' end;
  if new.individual_policy='seats_24h_2h_v1' then
   if t='match_confirmed' then en:='All seats are paid. The match is finally confirmed at the two-hour checkpoint; withdrawal is locked.';ar:='اكتمل دفع جميع المقاعد وتأكدت المباراة نهائيًا عند حاجز الساعتين. الانسحاب مقفل.';
   elsif new.cancellation_reason='PAID_SEATS_BELOW_80_AT_24H' then en:='Match cancelled: fewer than 80% of seats were paid at the 24-hour checkpoint. Eligible refunds await provider confirmation.';ar:='أُلغيت المباراة لعدم دفع 80% من المقاعد عند حاجز 24 ساعة. الاستردادات المستحقة تنتظر تأكيد مزود الدفع.';
   else en:='Match cancelled: paid seats did not reach 100% at the two-hour checkpoint. Eligible refunds await provider confirmation.';ar:='أُلغيت المباراة لعدم اكتمال دفع 100% من المقاعد عند حاجز الساعتين. الاستردادات المستحقة تنتظر تأكيد مزود الدفع.';end if;
  end if;
  for u in select new.host_id union select user_id from match_players where match_id=new.id loop
   perform arena_private.notify(u,t,'match-decision:'||new.id,jsonb_build_object('match_id',new.id),en,ar);
  end loop;
 end if;return new;
end$$;
revoke all on function public.match_checkout_quote(jsonb) from public,anon,authenticated;
grant execute on function public.match_checkout_quote(jsonb) to authenticated;
revoke all on all functions in schema arena_private from public,anon,authenticated;
commit;
