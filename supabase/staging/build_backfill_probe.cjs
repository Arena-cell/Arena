const fs=require('node:fs'),path=require('node:path');
const migration=fs.readFileSync(path.resolve(__dirname,'../migrations/202609290002_phase1_inventory.sql'),'utf8');
const start=migration.indexOf('do $$ declare r record;c record;');
const end=migration.indexOf('end $$;',start)+7;
if(start<0||end<7)throw Error('Backfill block not found');
const tables=['bookings','matches','arena_courts','court_reservations','inventory_migration_issues','blocked_slots'];
let sql=`-- Staging ONLY: gtcrijikfaglqcwqozel. Temporary tables, no persistent mutations.
-- Executes the exact existing migration backfill block with pg_temp shadow tables.
begin;
set local search_path=pg_temp,public,extensions;
`;
for(const table of tables) sql+=`create temporary table ${table} (like public.${table} including defaults including constraints including indexes) on commit drop;\n`;
sql+=`insert into arena_courts(arena_id,court_number) values
 ('a2000000-0000-4000-8000-000000000001',1),('a2000000-0000-4000-8000-000000000001',2);
insert into bookings(arena_id,starts_at,ends_at,total_price,status)
select 'a2000000-0000-4000-8000-000000000001','2035-02-01 10:00+04','2035-02-01 11:00+04',10,'upcoming' from generate_series(1,3);
${migration.slice(start,end)}
do $$ begin
 if (select count(*) from bookings)<>3
 or (select count(*) from bookings where court_id is not null)<>2
 or (select count(*) from inventory_migration_issues where resolved_at is null)<>1
 or (select count(*) from court_reservations)<>2 then
 raise exception 'BACKFILL_PROBE_FAILED';end if;
end $$;
select 'PASS' result,(select count(*) from bookings) preserved_bookings,
 (select count(*) from bookings where court_id is not null) assigned_courts,
 (select count(*) from inventory_migration_issues where resolved_at is null) preserved_conflicts;
rollback;
`;
fs.writeFileSync(path.join(__dirname,'verify_backfill.sql'),sql);
