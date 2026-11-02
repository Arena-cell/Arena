# PHASE 2 STAGING VERIFICATION

2026-10-08 — verified target: arena-staging, `gtcrijikfaglqcwqozel`.

| Area | Result | Evidence / limitation |
|---|---|---|
| Staging identity | PASS | Dashboard name and exact project URL |
| Migrations | PASS | Seven new receipt versions/checksums; original six verified before the seventh installation |
| Backup/preflight | PASS, limited backup | 287 private snapshot records; local source baseline. Not offsite/full database backup |
| RLS / financial RPC | PASS | Five new tables have RLS; authenticated direct order UPDATE false; reconcile EXECUTE false; public-client rejection tests passed |
| Cash | PASS | Server order fulfilled, booking unpaid; exact retry same order |
| Server price/add-on snapshots | PASS | Hosted water ×2/rackets ×6 + base = 17.000 OMR |
| Rental availability | PASS | Overlap remaining two, adjacent eight; oversell rejected |
| Double booking / concurrency | PASS locally | Phase 1 court races and Phase 2 rental races on loopback PostgreSQL |
| Pending Card without credentials | PASS | Deployed endpoint 503; provider not claimed; no fake paid |
| Webhook/job unauthorized caller | PASS | Deployed endpoints reject ordinary user JWT, HTTP 401 |
| Real Thawani checkout | NOT RUN | Sandbox keys absent |
| Real Thawani signature/status delivery | NOT RUN | Merchant configuration absent; hosted JWT gate still enabled |
| Real refunds / scheduled recovery | NOT RUN | Credentials and live executor acceptance pending |
| User session reopening | PASS | Browser reopened directly into signed-in Home; no email verification/PIN |
| Available web financial UI | PASS | User Cash/add-on checkout and persisted history, Card pending/missing-key message, Admin ledger and Owner breakdown/catalog. Real provider/native journeys NOT RUN |
| Local regression and financial checks | PASS | 30 Phase 1 + 41 Phase 2 PostgreSQL checks |
| Provider adapter tests | PASS | Seven test-only fake/contract checks |
| User / Owner static analysis and tests | PASS | No analysis issues; 23 / 2 Flutter tests |
| Admin build/lint | PASS | Explicit Staging settings; new FinancePanel separately linted; no test script configured |
| Canonical Edge Functions type check | PASS | All three entry points checked by Deno |

Hosted readback: migrations=7, RLS tables=5, backup rows=287, unresolved inventory=0, Card paid=0. The notification null-recipient filter installed in the seventh migration was separately read back as present. No Production writes or fake financial success were performed.

The existing Phase 1 public_profiles SECURITY DEFINER view is flagged by Dashboard; its reviewed authenticated public-column projection is described in the implementation report.

`PHASE 2 STATUS: NEEDS ACTION`

See `PHASE_2_IMPLEMENTATION_REPORT.md` for exact configuration steps and remaining acceptance work. This verification does not assert real payment readiness.
