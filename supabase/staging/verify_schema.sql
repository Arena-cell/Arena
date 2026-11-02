begin read only;
select 'phase1_migrations_recorded' check_name, (select count(*)=3 from arena_private.staging_installation) passed
union all select 'rls_enabled_sensitive_tables',not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in('profiles','bookings','matches','match_players','reviews','arenas','arena_courts','court_reservations','blocked_slots','admin_users','owner_stadium_assignments','staff_login_accounts') and not c.relrowsecurity)
union all select 'profile_role_update_denied',not has_column_privilege('authenticated','public.profiles','role','UPDATE')
union all select 'profile_completion_update_denied',not has_column_privilege('authenticated','public.profiles','onboarding_complete','UPDATE')
union all select 'private_schema_denied',not has_schema_privilege('authenticated','arena_private','USAGE') and not has_schema_privilege('anon','arena_private','USAGE')
union all select 'pin_hash_select_denied',not has_table_privilege('authenticated','arena_private.profile_credentials','SELECT')
union all select 'pin_pepper_select_denied',not has_table_privilege('authenticated','arena_private.pin_secret','SELECT')
union all select 'direct_sensitive_writes_denied',not exists(select 1 from unnest(array['bookings','matches','match_players','reviews','arena_courts','court_reservations','blocked_slots','admin_users','staff_login_accounts']) t where has_table_privilege('authenticated','public.'||t,'INSERT,UPDATE,DELETE'))
union all select 'no_legacy_profile_policies',not exists(select 1 from pg_policies where schemaname='public' and tablename in('profiles','bookings','matches','match_players','reviews','arena_courts','arenas','admin_users','owner_stadium_assignments','staff_login_accounts') and policyname not like 'phase1_%')
union all select 'username_unique_index',exists(select 1 from pg_indexes where schemaname='public' and indexname='profiles_username_canonical_uidx' and indexdef like 'CREATE UNIQUE%')
union all select 'shared_inventory_exclusion',exists(select 1 from pg_constraint where conrelid='public.court_reservations'::regclass and contype='x' and conname='court_reservations_no_overlap')
union all select 'inventory_sync_triggers', (select count(*)=3 from pg_trigger where not tgisinternal and tgname in('phase1_booking_inventory','phase1_match_inventory','phase1_block_inventory'))
union all select 'no_unresolved_conflicts',not exists(select 1 from public.inventory_migration_issues where resolved_at is null)
union all select 'no_duplicate_usernames',not exists(select lower(trim(username)) from public.profiles where username is not null group by lower(trim(username)) having count(*)>1)
union all select 'internal_allocator_execute_denied',not has_function_privilege('authenticated','arena_private.allocate_court(uuid,timestamptz,timestamptz)','EXECUTE')
union all select 'profile_rpc_anonymous_denied',not has_function_privilege('anon','public.complete_my_profile(text,text,date,text)','EXECUTE')
union all select 'profile_rpc_authenticated_allowed',has_function_privilege('authenticated','public.complete_my_profile(text,text,date,text)','EXECUTE')
union all select 'old_pin_rpc_removed',to_regprocedure('public.complete_my_profile(text,text,date,text,text)') is null
union all select 'availability_rpc_allowed',has_function_privilege('authenticated','public.arena_availability(uuid,date,date)','EXECUTE')
union all select 'auth_hook_grant',has_function_privilege('supabase_auth_admin','public.before_user_created_oman(jsonb)','EXECUTE');
commit;
