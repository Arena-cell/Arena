-- New user checkouts only. Existing Cash history/retries/cancellations and
-- Owner manual reservations are preserved. No payment is marked paid.
begin;
create function arena_private.reject_new_cash_checkout()
returns trigger language plpgsql set search_path=pg_catalog as $$
begin
  if new.payment_method='cash' then
    raise exception 'CASH_TEMPORARILY_DISABLED' using errcode='P0001';
  end if;
  return new;
end $$;
revoke all on function arena_private.reject_new_cash_checkout() from public,anon,authenticated;
create trigger disable_new_cash_checkout before insert on public.checkout_orders
for each row execute function arena_private.reject_new_cash_checkout();
commit;
