// Mutates only the two explicitly configured Staging test profiles, then restores usernames.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const sessions = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../build/staging-evidence/sessions.local.json')));
const base = 'https://gtcrijikfaglqcwqozel.supabase.co/rest/v1/';
async function profile(index, username) {
  const response = await fetch(base + 'profiles?id=eq.' + sessions[index].user.id + '&select=id,username', {
    method: username === undefined ? 'GET' : 'PATCH',
    headers: {apikey: 'sb_publishable_pxaampXaN_YJB3uqB-B3CA_dcYA-glr', Authorization: `Bearer ${sessions[index].access_token}`, 'Content-Type': 'application/json', Prefer: 'return=representation'},
    ...(username === undefined ? {} : {body: JSON.stringify({username})}),
  });
  return {status: response.status, data: await response.json()};
}
(async () => {
  assert.deepEqual(sessions.map(s => s.user.phone), ['96891234567', '96891234568']);
  const before = await Promise.all([profile(0), profile(1)]);
  before.forEach(r => {assert.equal(r.status, 200); assert.equal(r.data.length, 1);});
  try {
    const target = 'stage_race_' + Date.now();
    const race = await Promise.all([profile(0, target), profile(1, target.toUpperCase())]);
    assert.equal(race.filter(r => r.status === 200).length, 1);
    assert.equal(race.find(r => r.status !== 200).data.code, '23505');
    console.log('PASS simultaneous case-insensitive username claims: exactly one winner');
  } finally {
    const restored = await Promise.all(before.map((r, i) => profile(i, r.data[0].username)));
    restored.forEach((r, i) => {assert.equal(r.status, 200); assert.equal(r.data[0].username, before[i].data[0].username);});
    console.log('PASS original test usernames restored');
  }
})().catch(error => {console.error(error.message); process.exitCode = 1;});
