# PHASE 1 STAGING VERIFICATION

Updated: 2026-10-04, Asia/Muscat. Phase 1 only. Production was not changed.

**PHASE 1 STATUS: READY**

Final checkpoint completed on 2026-10-04: the user confirmed fresh sign-in for both existing staff accounts after hook activation. Browser verification then showed the authenticated Admin arena management screen and Owner dashboard with the October 4 booking. Passwords remained with the user. READY applies to the tested web Staging scope, not Production deployment or native-device certification.

## Verification results

| Check | Result | Evidence and scope |
|---|---|---|
| Supabase Staging | PASS | arena-staging / gtcrijikfaglqcwqozel; all launched apps use explicit Staging configuration |
| Migrations | PASS | Original three applied once in order; no-PIN follow-up applied once; schema audit 20 checks; hosted temporary-table backfill PASS 3 preserved / 2 assigned / 1 conflict retained |
| Security/RLS | PASS | Local 30 PostgreSQL checks, hosted schema audit and real-session profile isolation, role/completion escalation denial, admin insertion denial, direct booking denial, restricted hook execution |
| Phone OTP | PASS | Existing phones 567/568 and fresh phone 569; real Supabase Auth sessions; incorrect OTP rejected; unconfigured phone blocked without SMS; non-Oman signup rejected |
| Profile creation | PASS | Fresh phone 569 → OTP → Name / Username / DOB / gender → application; no PIN; existing completed profile protected; hosted concurrent case-insensitive username claims have exactly one winner, original usernames restored |
| Session persistence | PASS | Web reload and new tab restore completed user without Email Verification or PIN; Owner/Admin sessions restored too. Native Android/iOS process lifecycle was not tested |
| Availability | PASS | User booking appears in Owner/Admin; future Owner block reflected in User/Admin; complete October 1488 rows, including October 31 |
| Owner integration | PASS | Manual booking, overlap rejection, block creation, inventory and restored session; user confirmed fresh sign-in after hook activation, authenticated dashboard verified |
| Admin integration | PASS | Bookings and shared availability UI, restored session; user confirmed fresh sign-in after hook activation, authenticated management screen verified |
| Double Booking Protection | PASS | Hosted real-session simultaneous single-court: one winner; two-court: two distinct courts, third denied; half-hour, adjacent, idempotency, overlap and match collision checks passed |
| Release OTP Bypass Protection | PASS | Actual compiled Flutter release probe rejected ARENA_DEV_OTP before Auth initialization |

All listed acceptance checks passed within the evidence scope described above.

## Applied migrations — do not rerun

1. 202609290001_phase1_security_profile.sql
2. 202609290002_phase1_inventory.sql
3. 202609290003_phase1_rpc_boundaries.sql
4. 202610020001_phase1_remove_account_pin.sql

Original three SHA-256 receipts are in arena_private.staging_installation; these are not Supabase CLI migration history. No blind db push. The empty Staging baseline was checked before the initial installation. Production ref mbgqnlbuslrgamkzdqpd is excluded.

The PIN requirement was canceled by the user. The old five-argument profile RPC was removed; completion no longer reads/writes credentials. Historical private hashes remain inaccessible and unused. No Production data was deleted.

## Actual cross-app tests

- User C: 96891234569 / configured test OTP; Staging Player C, stage_test_c, DOB 2000-01-01, male. Completed profile without PIN and restored session.
- User UI booking: Single Court, October 4, 10:00–10:30 Oman, Court 1, 5 OMR. Admin shows the same interval/price; Owner shows the same online booking.
- Owner UI block: Single Court, October 4, 18:00–19:00 Oman. Owner inventory shows the block. User UI disables 18:00/18:30 and enables adjacent 19:00. A real User RPC overlap attempt was rejected with TIME_NO_LONGER_AVAILABLE. Admin shows the same block and omits the blocked periods from its available list.
- Earlier Owner manual booking: Single Court October 2, 18:00–19:00. Overlapping block rejected; same-time block on Two Courts accepted, leaving the other court available in Admin.
- Hosted booking concurrency fixtures on October 3 are retained for evidence. Do not rerun verify_bookings.cjs on the occupied date.
- Hosted backfill probe used temporary shadow tables and ROLLBACK. It tests the original algorithm on hosted PostgreSQL, not a copy of Production data.

## Fixes found during verification

- Admin PGRST201 ambiguity: explicitly select reward_coupons!bookings_coupon_id_fkey.
- Month availability was truncated at 1000 PostgREST rows, making dates after October 21 appear unavailable. User repository now requests seven-day windows. Read-only hosted check confirms 1488 distinct consecutive October slots. UI permits October 31.
- Periodic availability refresh removed the booking grid and interrupted scrolling. Keep the populated grid mounted during refresh; clear data on month changes. Apply the same loading behavior to match scheduling.
- Match cards use a minimum height and content-sized column to avoid the observed four-pixel overflow.
- verify_phone.cjs now uses unconfigured phone 96891234570 for the negative SMS-hook test because 569 became an authorized test fixture.

## Validation

Latest User flutter analyze: no issues. Latest flutter test: 23 passed after the above code changes. Earlier Owner analyze and 2 tests passed; Admin build/lint passed after the query fix. Local PostgreSQL 30 checks passed after PIN removal. Hosted verify_phone, verify_user_security, verify_month_availability and verify_username_race passed; hosted bookings/concurrency and backfill passed as described above. No service-role key used in Flutter or test clients.

## MANUAL ACTIONS REQUIRED

No outstanding manual action for the tested web Staging acceptance. The requested Owner/Admin sign-out and fresh sign-in were completed by the user and the resulting authenticated screens verified. No migration or Dashboard security change is required. Test Phone configuration is already saved: 96891234567=123456,96891234568=234567,96891234569=345678. User reported expiry October 5, 2026. When it expires, renew on Staging only if further tests are needed; credential changes must be entered by the user.

Send SMS hook staging_deny_real_sms remains fail-closed for non-test numbers. Before User Created hook before_user_created_oman is active. New staff provisioning after enabling that hook is not verified; do not assume email-only admin creation bypasses it. Existing staff login is the current test scope.

Firebase Phone Auth is not used. No Firebase, FCM, payment or Production setup changes were made. A future Production rollout, real SMS configuration and native device acceptance are separate from this web Staging evidence; no permission to deploy Production is implied.

## Evidence

Local screenshots under build/staging-evidence: no-pin-schema-checks.png, release-otp-guard.png, backfill-staging.png, oman-hook-enabled.png, new-user-no-pin-home.png, new-user-session-restored.png, admin-user-booking.png, owner-user-booking.png, owner-block-oct4.png, user-owner-block.png, admin-owner-block.png, admin-final-signin.png, owner-final-signin.png. sessions.local.json contains temporary test sessions and must remain ignored and unshared.
