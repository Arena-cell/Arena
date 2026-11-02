-- Publish only existing RLS-protected sources for live availability/financial updates.
begin;
do $$ declare t text;begin
 foreach t in array array['court_reservations','checkout_orders','payment_refunds'] loop
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
   execute format('alter publication supabase_realtime add table public.%I',t);
  end if;
 end loop;
end $$;
commit;
