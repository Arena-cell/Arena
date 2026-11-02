begin;
insert into auth.users(id,phone,phone_confirmed_at) values('fd160000-0000-4000-8000-000000000003','96899001603',now()) on conflict do nothing;
insert into staff_login_accounts(user_id,username,account_type,active) values('fd160000-0000-4000-8000-000000000003','prefs_owner','owner',true) on conflict do nothing;
insert into arenas(id,owner_id,name,location,price_per_hour,opening_time,closing_time,court_count,audience_gender) values('fd160000-0000-4000-8000-000000000004','fd160000-0000-4000-8000-000000000003','Preferences test','Muscat',10,'08:00','23:00',1,'men');
update user_preferences set private_profile=true where user_id='fd160000-0000-4000-8000-000000000001';
set role authenticated;
set request.jwt.claim.sub='fd160000-0000-4000-8000-000000000003';
do $$ begin if can_view_public_profile('fd160000-0000-4000-8000-000000000001') then raise exception 'Unrelated owner sees private profile'; end if; end $$;
reset role;
insert into bookings(id,user_id,arena_id,starts_at,ends_at,total_price,status) values('fd160000-0000-4000-8000-000000000005','fd160000-0000-4000-8000-000000000001','fd160000-0000-4000-8000-000000000004','2038-01-01 10:00+04','2038-01-01 11:00+04',10,'cancelled');
set role authenticated;
set request.jwt.claim.sub='fd160000-0000-4000-8000-000000000003';
do $$ begin if not can_view_public_profile('fd160000-0000-4000-8000-000000000001') then raise exception 'Booking owner access lost'; end if; end $$;
rollback;

