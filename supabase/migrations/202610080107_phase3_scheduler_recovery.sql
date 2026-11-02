-- One failing match must not prevent other due events from being processed.
begin;
alter table matches add column decision_attempt_count integer not null default 0;
alter table matches add column decision_next_attempt_at timestamptz not null default now();
alter table matches add column decision_last_error text;
alter table arena_scheduled_job_runs add column failed_match_id uuid;
create index phase3_job_history on arena_scheduled_job_runs(started_at desc);
create or replace function public.process_arena_scheduled_events() returns jsonb
language plpgsql security definer set search_path=public as $$
declare r record;j uuid;d integer:=0;n integer:=0;errors integer:=0;err text;begin
 if not pg_try_advisory_xact_lock(hashtextextended('arena-phase3-scheduler',0)) then return jsonb_build_object('busy',true);end if;
 insert into arena_scheduled_job_runs(outcome) values('running') returning id into j;
 for r in select id from matches where decision_outcome='pending' and status<>'cancelled'
  and decision_at<=clock_timestamp() and decision_next_attempt_at<=clock_timestamp()
  order by arena_id,id limit 200 loop
  begin
   if arena_private.decide_match(r.id)<>'pending' then d:=d+1;end if;
  exception when others then
   get stacked diagnostics err=message_text;
   errors:=errors+1;
   update matches set decision_attempt_count=decision_attempt_count+1,decision_last_error=left(err,200),
    decision_next_attempt_at=clock_timestamp()+make_interval(secs=>least(3600,30*(2^least(decision_attempt_count,7))::integer)) where id=r.id;
   insert into arena_scheduled_job_runs(outcome,processed_at,failed_match_id,last_error)
   values('failed',clock_timestamp(),r.id,left(err,200));
  end;
 end loop;
 begin n:=enqueue_due_event_reminders();
 exception when others then
  get stacked diagnostics err=message_text;errors:=errors+1;
  insert into arena_scheduled_job_runs(outcome,processed_at,last_error) values('failed',clock_timestamp(),left(err,200));
 end;
 update arena_scheduled_job_runs set outcome=case when errors>0 then 'failed' else 'succeeded' end,
  processed_at=clock_timestamp(),decision_count=d,reminder_count=n,
  last_error=case when errors>0 then 'DUE_EVENT_FAILURE: see per-match job records' end where id=j;
 -- Keep every meaningful/failed run; routine heartbeat is at most once per five minutes.
 if d=0 and n=0 and errors=0 and exists(select 1 from arena_scheduled_job_runs
   where id<>j and outcome='succeeded' and started_at>now()-interval '5 minutes') then
  delete from arena_scheduled_job_runs where id=j;
 end if;
 delete from arena_scheduled_job_runs where outcome='succeeded' and started_at<now()-interval '7 days';
 return jsonb_build_object('job_id',j,'decisions',d,'reminders',n,'failed_events',errors);
end $$;
commit;
