// LOCAL ONLY: database JWT claims and auth.mfa_factors are test fixtures.
// Does not claim actual GoTrue TOTP enrollment or real recovery acceptance.
const fs=require('node:fs'),cp=require('node:child_process'),assert=require('node:assert/strict');
const db=fs.readFileSync('build/phase1-test-db.txt','utf8').trim();assert.match(db,/^arena_phase1_test_\d+$/);
const exe='C:/Program Files/PostgreSQL/18/bin/psql.exe',args=['-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',db,'-v','ON_ERROR_STOP=1','-qAt'];
function sql(s){try{return cp.execFileSync(exe,args,{input:s,encoding:'utf8',stdio:['pipe','pipe','pipe']}).trim()}catch(e){throw Error(e.stderr.toString())}}
assert(sql('show data_directory').replaceAll('\\','/').endsWith('/playon/build/phase1-pgdata'));
const admin='10000000-0000-4000-8000-000000000004',player='10000000-0000-4000-8000-000000000001',q=x=>`'${String(x).replaceAll("'","''")}'`;
const role=(user,aal='aal1',iat=Math.floor(Date.now()/1000)+60)=>`set local role authenticated;set local request.jwt.claim.sub=${q(user)};set local request.jwt.claims=${q(JSON.stringify({sub:user,role:'authenticated',aal,iat}))};`;
const factor=`insert into auth.mfa_factors(id,user_id,factor_type,status) values(gen_random_uuid(),${q(admin)},'totp','verified');`;
const setup=`begin;insert into arena_private.admin_mfa_state(user_id) values(${q(admin)}) on conflict do nothing;`;
function run(user,aal,query,extra=''){return sql(setup+extra+role(user,aal)+query+';rollback;')}
const denied=(user,aal,query,extra='')=>assert.throws(()=>run(user,aal,query,extra),/permission denied|ADMIN_AAL2_REQUIRED|MFA_ACTIVATION_NOT_READY/);
let count=0;const test=(name,fn)=>{fn();count++;console.log('PASS '+name)};
test('preparation does not lock existing admin',()=>assert.equal(run(admin,'aal1','select is_platform_admin()'),'t'));
test('player cannot issue recovery codes',()=>denied(player,'aal2','select generate_admin_recovery_codes()',factor));
test('admin AAL1 cannot issue recovery codes',()=>denied(admin,'aal1','select generate_admin_recovery_codes()',factor));
test('claimed AAL2 without verified TOTP denied',()=>denied(admin,'aal2','select generate_admin_recovery_codes()'));
test('issue exactly 10 unique high entropy recovery codes',()=>{const codes=JSON.parse(run(admin,'aal2','select generate_admin_recovery_codes()',factor));assert.equal(codes.length,10);assert.equal(new Set(codes).size,10);assert(codes.every(x=>/^[a-f0-9]{32}$/.test(x)))});
test('recovery table inaccessible to clients',()=>denied(admin,'aal2','select * from arena_private.admin_mfa_recovery_codes',factor));
test('codes stored only as 32-byte hashes',()=>assert.equal(sql(setup+factor+role(admin,'aal2')+'do $$begin perform generate_admin_recovery_codes();end$$;reset role;select count(*)=10 and bool_and(octet_length(code_hash)=32) from arena_private.admin_mfa_recovery_codes where user_id='+q(admin)+';rollback;'),'t'));
test('confirmation requires saved codes',()=>denied(admin,'aal2','select confirm_admin_mfa_setup(false)',factor));
test('authenticated cannot activate enforcement',()=>denied(admin,'aal2',`select activate_admin_mfa(${q(admin)})`,factor));
test('server activation rejects unconfirmed setup',()=>assert.throws(()=>sql(setup+factor+`set local role service_role;select activate_admin_mfa(${q(admin)});rollback;`),/MFA_ACTIVATION_NOT_READY/));
const enforced=factor+`update arena_private.admin_mfa_state set enforced=true where user_id=${q(admin)};`;
test('enforced admin AAL1 loses server admin privilege',()=>assert.equal(run(admin,'aal1','select is_platform_admin()',enforced),'f'));
test('enforced admin AAL2 retains privilege',()=>assert.equal(run(admin,'aal2','select is_platform_admin()',enforced),'t'));
test('MFA cannot grant admin role to player',()=>assert.equal(run(player,'aal2','select is_platform_admin()',enforced),'f'));
test('enforced AAL1 cannot read financial snapshots',()=>assert.equal(run(admin,'aal1','select count(*) from booking_financial_snapshots',enforced),'0'));
test('enforced AAL1 cannot read bank accounts through RPC',()=>assert.throws(()=>run(admin,'aal1','select finance_owner_bank_accounts()',enforced),/FINANCE_ADMIN_ONLY/));
const backup='ab'.repeat(16),seed=factor+`insert into arena_private.admin_mfa_recovery_codes(user_id,code_hash) values(${q(admin)},extensions.digest(${q(admin+':'+backup)},'sha256'));`;
test('wrong code rejected',()=>assert.equal(run(admin,'aal1',"select begin_admin_mfa_recovery('wrong')->>'ok'",seed),'false'));
test('recovery code cannot be used by another user',()=>assert.equal(run(player,'aal1',`select begin_admin_mfa_recovery(${q(backup)})->>'ok'`,seed),'false'));
test('recovery is single use',()=>assert.equal(run(admin,'aal1',`do $$begin perform begin_admin_mfa_recovery(${q(backup)});end$$;select begin_admin_mfa_recovery(${q(backup)})->>'ok'`,seed),'false'));
test('successful recovery never grants admin access',()=>assert.equal(run(admin,'aal1',`do $$begin perform begin_admin_mfa_recovery(${q(backup)});end$$;select is_platform_admin()`,seed),'f'));
test('recovery locks stale AAL2 session as well',()=>assert.equal(run(admin,'aal2',`do $$begin perform begin_admin_mfa_recovery(${q(backup)});end$$;select is_platform_admin()`,seed),'f'));
test('five failures start persistent rate limit',()=>assert.equal(sql(setup+seed+role(admin)+"do $$begin for i in 1..5 loop perform begin_admin_mfa_recovery('bad');end loop;end$$;reset role;select blocked_until>clock_timestamp() from arena_private.admin_mfa_state where user_id="+q(admin)+';rollback;'),'t'));
test('user cannot inspect recovery tickets',()=>denied(admin,'aal1',`select admin_mfa_recovery_factors(${q(admin)},'forged')`,seed));
test('invalid ticket gives no factor IDs to worker',()=>assert.equal(sql(setup+seed+`set local role service_role;select admin_mfa_recovery_factors(${q(admin)},'forged') is null;rollback;`),'t'));
test('direct audit fabrication denied',()=>denied(admin,'aal2',`insert into arena_private.admin_mfa_audit(user_id,event) values(${q(admin)},'forged')`,factor));
test('global enforcement applies to admins without a per-user state row',()=>assert.equal(run(admin,'aal1','select is_platform_admin()',`delete from arena_private.admin_mfa_state where user_id=${q(admin)};update arena_private.admin_mfa_policy set enforced=true;`),'f'));
test('global enforcement retains verified admin AAL2 access',()=>assert.equal(run(admin,'aal2','select is_platform_admin()',factor+'update arena_private.admin_mfa_policy set enforced=true;'),'t'));
test('client cannot disable global MFA policy',()=>denied(admin,'aal2','update arena_private.admin_mfa_policy set enforced=false',factor));
test('complete confirmation is required before service activates global MFA',()=>assert.equal(sql(setup+factor+role(admin,'aal2')+`do $$begin perform generate_admin_recovery_codes();perform confirm_admin_mfa_setup(true);end$$;reset role;set local role service_role;select activate_admin_mfa(${q(admin)});reset role;`+role(admin,'aal1')+'select not is_platform_admin();rollback;'),'t'));
console.log(count+' MFA database tests passed');
