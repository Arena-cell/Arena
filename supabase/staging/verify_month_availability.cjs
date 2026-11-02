// Read-only hosted Staging check; public key and real user session only.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const path = require('node:path');
const session = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../build/staging-evidence/sessions.local.json')))[0];
const base = 'https://gtcrijikfaglqcwqozel.supabase.co';
async function windowRows(from, to) {
  const response = await fetch(base + '/rest/v1/rpc/arena_availability', {
    method: 'POST',
    headers: {apikey: 'sb_publishable_pxaampXaN_YJB3uqB-B3CA_dcYA-glr', Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json'},
    body: JSON.stringify({p_arena_id: 'a1000000-0000-4000-8000-000000000001', p_from: from, p_to: to}),
  });
  assert.equal(response.status, 200);
  return response.json();
}
(async () => {
  const rows = [];
  for (const [from, to] of [['2026-10-01','2026-10-08'], ['2026-10-08','2026-10-15'], ['2026-10-15','2026-10-22'], ['2026-10-22','2026-10-29'], ['2026-10-29','2026-11-01']]) {
    rows.push(...await windowRows(from, to));
  }
  assert.equal(rows.length, 31 * 48);
  assert.equal(new Set(rows.map(row => row.starts_at)).size, 31 * 48);
  for (let i = 1; i < rows.length; i++) assert.equal(Date.parse(rows[i].starts_at) - Date.parse(rows[i-1].starts_at), 30 * 60000);
  assert.ok(rows.some(row => row.starts_at === '2026-10-31T06:00:00+00:00' && row.available));
  console.log('PASS full October: 1488 unique consecutive half-hour rows, including available October 31');
})().catch(error => {console.error(error.message); process.exitCode = 1;});
