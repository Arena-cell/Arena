// Isolated localhost database only. Never creates payments or bank movements.
const fs = require('node:fs');
const cp = require('node:child_process');
const assert = require('node:assert/strict');
const db = fs.readFileSync('build/phase1-test-db.txt', 'utf8').trim();
assert.match(db, /^arena_phase1_test_\d+$/);
const args = ['-X', '-h', '127.0.0.1', '-p', '55439', '-U', 'postgres', '-d', db,
  '-v', 'ON_ERROR_STOP=1', '-qAt'];
const query = sql => cp.execFileSync('C:/Program Files/PostgreSQL/18/bin/psql.exe', args,
  {input: sql, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe']}).trim();
const source = fs.readFileSync('supabase/migrations/202610240001_contractual_commission_preview.sql', 'utf8');
if (query("select to_regprocedure('arena_private.contractual_commission_preview(bigint,jsonb,bigint,bigint)') is null") === 't') query(source);
let checks = 0;
function test(name, run) { run(); checks++; console.log(`PASS ${name}`); }
function quote(base, addons = [], discount = 0, refund = 0) {
  return JSON.parse(query(`select arena_private.contractual_commission_preview(${base},'${JSON.stringify(addons)}'::jsonb,${discount},${refund})`));
}
test('base 10 OMR: commission 0.800, owner 9.200', () => {
  const q = quote(10000); assert.equal(q.commission_baisa, 800); assert.equal(q.owner_net_baisa, 9200);
});
test('water is the sole exemption', () => {
  const q = quote(10000, [{addon_code:'water',line_amount_baisa:1000}]);
  assert.equal(q.gross_baisa,11000); assert.equal(q.commission_baisa,800); assert.equal(q.owner_net_baisa,10200);
});
test('rackets and future services are commissionable', () => {
  const q = quote(10000, [{addon_code:'racket',line_amount_baisa:2000},{addon_code:'coaching',line_amount_baisa:3000}]);
  assert.equal(q.eligible_baisa,15000); assert.equal(q.commission_baisa,1200);
});
test('mixed base, water, rental totals reconcile', () => {
  const q = quote(10000,[{addon_code:'water',line_amount_baisa:1000},{addon_code:'racket',line_amount_baisa:2000}]);
  assert.equal(q.gross_baisa,13000); assert.equal(q.commission_baisa,960); assert.equal(q.owner_net_baisa,12040);
});
test('internal split sums to commission even at rounding boundaries', () => {
  for (const amount of [0,1,6,7,19,20,99,3333,10001,5000000000]) {
    const q=quote(amount); assert.equal(q.internal_gateway_allocation_baisa+q.internal_arena_allocation_baisa,q.commission_baisa);
    assert.equal(q.owner_net_baisa+q.commission_baisa,q.gross_baisa);
  }
});
test('actual provider fee is unknown, never fabricated as 2.5%', () => {
  const q=quote(10000); assert.equal(q.actual_gateway_fee_baisa,null); assert.equal(q.actual_gateway_fee_verified,false);
});
test('owner projection omits all internal splits and gateway fields', () => {
  const q=JSON.parse(query("select arena_private.owner_commission_projection(arena_private.contractual_commission_preview(10000))"));
  assert.equal(q.commission_baisa,800); assert(!Object.keys(q).some(k=>/internal|gateway|arena_allocation/.test(k)));
});
test('unapproved discount and refund policies fail closed', () => {
  assert.throws(()=>quote(10000,[],100)); assert.throws(()=>quote(10000,[],0,100));
});
test('malformed, negative and fractional financial inputs rejected', () => {
  assert.throws(()=>quote(-1));
  for(const amount of [-1,1.5,'100']) assert.throws(()=>quote(1000,[{addon_code:'water',line_amount_baisa:amount}]));
  assert.throws(()=>quote(1000,[{addon_code:'',line_amount_baisa:100}]));
});
test('client roles cannot call the internal calculator', () => {
  for(const role of ['anon','authenticated']) assert.equal(query(`select has_function_privilege('${role}','arena_private.contractual_commission_preview(bigint,jsonb,bigint,bigint)','execute')`),'f');
});
console.log(`${checks} tests passed`);
