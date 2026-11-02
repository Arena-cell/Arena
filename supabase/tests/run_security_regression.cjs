// Repeatable LOCAL-ONLY security gate. Apply the security drafts to the local
// test database first. No migration, cloud connection or deployment occurs.
const fs = require('node:fs');
const cp = require('node:child_process');
const path = require('node:path');
const assert = require('node:assert/strict');
process.chdir(path.resolve(__dirname, '../..'));
const db = fs.readFileSync('build/phase1-test-db.txt', 'utf8').trim();
assert.match(db, /^arena_phase1_test_\d+$/);
const directory = cp.execFileSync('C:/Program Files/PostgreSQL/18/bin/psql.exe', [
  '-X', '-h', '127.0.0.1', '-p', '55439', '-U', 'postgres', '-d', db, '-qAt', '-c', 'show data_directory',
], { encoding: 'utf8' }).trim().replaceAll('\\', '/');
assert(directory.endsWith('/playon/build/phase1-pgdata'));
for (const suite of ['security_social_regression', 'admin_mfa_regression', 'security_concurrency', 'security_token_inbox']) {
  const result = cp.spawnSync(process.execPath, [path.join(__dirname, `${suite}.cjs`)], { stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
console.log('LOCAL SECURITY GATE PASSED; hosted acceptance is a separate required step.');
