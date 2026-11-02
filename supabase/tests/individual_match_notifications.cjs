// Inspect real SQL events produced by the loopback provider-fake integration suite.
// Never connects to hosted Supabase and never sends a push notification.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict');
const db=fs.readFileSync('build/phase1-test-db.txt','utf8').trim();assert.match(db,/^arena_phase1_test_\d+$/);
const args=['-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-qAt'];
const sql=s=>cp.execFileSync('C:/Program Files/PostgreSQL/18/bin/psql.exe',args,{input:s,encoding:'utf8',stdio:['pipe','pipe','pipe']}).trim();
assert(sql('show data_directory').replaceAll('\\','/').endsWith('/playon/build/phase1-pgdata'));
const q=s=>`'${String(s).replaceAll("'","''")}'`;let count=0;const test=(n,f)=>{f();count++;console.log('PASS '+n)};
for(const [reason,type,en,ar] of [
 ['PAID_SEATS_BELOW_80_AT_24H','match_cancelled','24-hour','24 ساعة'],
 ['PAID_SEATS_NOT_FULL_AT_2H','match_cancelled','two-hour','الساعتين'],
 [null,'match_confirmed','two-hour','الساعتين'],
]){
 const id=sql(`select id from matches where name='Seat LOCAL' and individual_policy='seats_24h_2h_v1' and ${reason?`cancellation_reason=${q(reason)}`:"decision_outcome='confirmed'"} order by created_at desc,id limit 1`);assert(id,'Run individual_match_seats.cjs first');
 const members=Number(sql(`select count(*) from match_players where match_id=${q(id)}`));assert(members>0);
 const rows=JSON.parse(sql(`select jsonb_agg(to_jsonb(n)) from notifications n where event_key=${q('match-decision:'+id)} and type=${q(type)}`));
 test(`${reason||'FINAL_CONFIRMATION'} reaches every participant exactly once`,()=>{assert.equal(rows.length,members);assert.equal(new Set(rows.map(r=>r.user_id)).size,members)});
 test(`${reason||'FINAL_CONFIRMATION'} contains correct bilingual reason and navigation target`,()=>{for(const row of rows){assert.equal(row.data.match_id,id);assert(row.body_en.includes(en));assert(row.body_ar.includes(ar));if(type==='match_cancelled')assert(!/has been refunded|تم استرداد/.test(row.body_en+' '+row.body_ar))}});
 const before=sql(`select count(*) from notifications where data->>'match_id'=${q(id)}`);sql(`select arena_private.decide_match(${q(id)});select arena_private.decide_match(${q(id)})`);
 test(`${reason||'FINAL_CONFIRMATION'} retry does not duplicate inbox/owner events`,()=>assert.equal(sql(`select count(*) from notifications where data->>'match_id'=${q(id)}`),before));
}
console.log(count+' individual match notification tests passed');
