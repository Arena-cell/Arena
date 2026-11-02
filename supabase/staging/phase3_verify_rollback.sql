-- STAGING ONLY. Real existing accounts, no fake provider outcomes. All fixture rows rollback.
begin;
do $$
declare a uuid:='a1000000-0000-4000-8000-000000000002';
 u1 uuid:='dd11863b-c437-4e50-b612-94a2c2891ea8';u2 uuid;
 m uuid:=gen_random_uuid();c uuid;outcome text;cnt integer;begin
 select p.id into u2 from profiles p join auth.users u on u.id=p.id
 where p.id<>u1 and p.onboarding_complete and p.profile_version=1 and p.gender='men'
 and u.phone_confirmed_at is not null and u.phone ~ '^\+?968[0-9]{8}$' order by p.id limit 1;
 if u2 is null then raise exception 'SECOND_REAL_TEST_USER_REQUIRED';end if;
 select id into c from arena_courts where arena_id=a and is_active order by court_number limit 1;
 insert into matches(id,arena_id,court_id,host_id,name,sport,starts_at,ends_at,max_players,price_per_player,gender,status,is_private)
 values(m,a,c,u1,'Phase3 rollback validation','football',now()+interval '3 hours',now()+interval '4 hours',2,1,'men','upcoming',true);
 insert into match_players(match_id,user_id,status) values(m,u1,'joined'),(m,u2,'joined');
 update matches set starts_at=now()+interval '80 minutes',ends_at=now()+interval '140 minutes' where id=m;
 outcome:=arena_private.decide_match(m);
 if outcome<>'confirmed' then raise exception 'HOSTED_CONFIRMATION_FAILED';end if;
 if arena_private.decide_match(m)<>'confirmed' then raise exception 'HOSTED_REPEAT_FAILED';end if;
 begin delete from match_players where match_id=m and user_id=u2;raise exception 'HOSTED_LEAVE_BYPASS';
 exception when others then if sqlerrm<>'WITHDRAWAL_LOCKED_AFTER_CONFIRMATION' then raise;end if;end;
 begin update matches set status='cancelled' where id=m;raise exception 'HOSTED_STATUS_BYPASS';
 exception when others then if sqlerrm<>'FINAL_MATCH_DECISION' then raise;end if;end;
 m:=gen_random_uuid();
 insert into matches(id,arena_id,court_id,host_id,name,sport,starts_at,ends_at,max_players,price_per_player,gender,status,is_private)
 values(m,a,c,u1,'Phase3 cancellation rollback','football',now()+interval '5 hours',now()+interval '6 hours',3,1,'men','upcoming',true);
 insert into match_players(match_id,user_id,status) values(m,u1,'joined'),(m,u2,'requested');
 update matches set starts_at=now()+interval '81 minutes',ends_at=now()+interval '141 minutes',court_id=(select id from arena_courts where arena_id=a and id<>c and is_active limit 1) where id=m;
 if arena_private.decide_match(m)<>'cancelled' then raise exception 'HOSTED_CANCELLATION_FAILED';end if;
 if exists(select 1 from court_reservations where source_id=m) then raise exception 'HOSTED_RELEASE_FAILED';end if;
 if (select decision_joined_count from matches where id=m)<>1 then raise exception 'PENDING_MEMBER_COUNTED';end if;
 select count(*) into cnt from notifications where data->>'match_id'=m::text and type='match_cancelled';
 if cnt<>2 then raise exception 'HOSTED_RECIPIENTS_FAILED';end if;
 perform arena_private.decide_match(m);
 if (select count(*) from notifications where data->>'match_id'=m::text and type='match_cancelled')<>cnt then raise exception 'HOSTED_DUPLICATE_NOTICE';end if;
 if has_function_privilege('authenticated','public.process_arena_scheduled_events()','execute') then raise exception 'SCHEDULER_PERMISSION_LEAK';end if;
 if has_function_privilege('authenticated','public.claim_arena_push_batch(integer)','execute') then raise exception 'PUSH_PERMISSION_LEAK';end if;
 if has_table_privilege('authenticated','public.matches','UPDATE') then raise exception 'MATCH_DIRECT_WRITE_LEAK';end if;
 if has_column_privilege('authenticated','public.notifications','delivery_status','UPDATE') then raise exception 'NOTIFICATION_WRITE_LEAK';end if;
 if not has_column_privilege('authenticated','public.notifications','read_at','UPDATE') then raise exception 'READ_MARK_PERMISSION_MISSING';end if;
end $$;
rollback;
select 'PASS: hosted decision, repeat, withdrawal lock, final status, pending exclusion, cancellation, court release, recipients, event deduplication and permission boundaries. Fixtures rolled back; no payments faked.' as phase3_verification;
