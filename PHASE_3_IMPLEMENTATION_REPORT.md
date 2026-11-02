# PHASE 3 IMPLEMENTATION REPORT

Verification date: 9 October 2026, Asia/Muscat.

Environment: **arena-staging — `gtcrijikfaglqcwqozel` only**. No Production deployment or Production data changes. Phase 4 was not started. Previously applied Phase 1/2 migrations were preserved; all Phase 3 database changes use new migration versions.

**PHASE 3 STATUS: NEEDS ACTION**

The database decision engine, automatic cancellation, withdrawal restrictions, durable inbox, scheduler and application views are implemented and verified. Native FCM delivery is not configured/tested. Real Thawani capture/refund acceptance remains dependent on the unavailable provider credentials. No payment or refund was marked successful on hosted Staging using a fake.

## Verification summary

PASS below describes the implemented component and the tested scope; it does not imply native push or live provider acceptance.

| Check | Status |
|---|---|
| 90/80 Decision | PASS |
| Automatic Cancellation | PASS |
| Withdrawal Lock | PASS |
| Join After Confirmation | PASS |
| Refund Safety | PASS — database/local provider fakes; real refund NOT TESTED |
| Notification Queue | PASS — durable inbox, leases, retries and RLS |
| Scheduled Jobs | PASS — database decisions/reminders active; push dispatch awaits secrets |
| FCM Push Delivery | NOT TESTED |
| User App | PASS — analyze/tests and Staging web acceptance; native push NOT TESTED |
| Owner App | PASS — analyze/tests and Staging web acceptance |
| Admin Web | PASS — build/lint and authenticated Staging acceptance |
| RLS/Security | PASS |

## 1. Match 90/80 Rule

- `decision_at = starts_at - interval '90 minutes'`; timestamps remain UTC in PostgreSQL and are displayed in Oman time.
- A single PostgreSQL transaction locks the arena, match and relevant financial orders in a consistent order. It counts eligible `joined` memberships from the database, then applies `joined_count * 5 >= max_players * 4`.
- The UI threshold is integer ceiling of four-fifths of capacity. Capacities 5/10/12/14/20 require 4/8/10/12/16 respectively.
- Pending requests/invitations and incomplete profiles/payment entitlements are excluded. Phase 2 verified individual payments and verified full-host coverage determine financial eligibility. Existing legacy no-charge records remain supported without inventing a payment.
- The decision ledger records the final outcome, time and eligible count once. Re-running the decision or admitting another player does not alter that snapshot.
- Existing ended matches were labelled `historical`, preserving their original status and avoiding retrospective cancellation/refund.
- The logical cutoff is enforced by server entry points even when the scheduler is late. The active cron runs every five seconds: execution is subject to scheduler/lock latency, not a hard real-time guarantee.

## 2. Join/Leave Restrictions

- Before the cutoff, the existing leave policy is preserved. Leaving removes membership eligibility but retains the financial entitlement/ledger.
- After a confirmed decision, RPCs and database triggers reject withdrawal with `WITHDRAWAL_LOCKED`. Legacy definer functions, direct deletion/status changes, Owner and Admin paths cannot bypass the guard.
- Confirmed matches still accept eligible new players while there is capacity and before start. Existing invitation, gender/profile and payment checks remain effective.
- Joins after start or into cancelled matches fail. Joins never reverse the final decision.
- Local concurrent join/leave/decision and payment/decision transactions were tested with separate PostgreSQL clients.

## 3. Auto Cancellation

- Under-threshold decisions set the match to cancelled with `MINIMUM_PARTICIPATION_NOT_REACHED`.
- Existing inventory triggers remove the match reservation in the same transaction, preserving half-open court intervals and double-booking protection.
- Cancelled match and participant notifications are committed independently of external push delivery. A Firebase outage does not prevent the database decision.
- A failing match is isolated in a savepoint, logged and retried with backoff; it does not block other due matches or reminders.

## 4. Refund Integration

- Uses Phase 2 `checkout_orders` / `payment_refunds`; no duplicate financial ledger was introduced.
- Automatic cancellation creates deterministic, unique refund requests only for genuinely captured electronic amounts. Remaining refundable amount excludes completed refunds and existing nonfailed requests.
- Host-pays-all refunds concern the host's captured order. Individual payments concern each payer's captured order; unpaid/pending orders do not generate a fictitious refund.
- Original payments are retained. A captured payment whose match is already cancelled cannot create a seat: the order is retained for refund processing instead.
- Refund-required/requested is not refunded. Completion continues to require the existing verified provider path. Local provider fakes were used only in tests, never in hosted application code or Staging payments.
- Paid public rejoin retains the existing entitlement and does not charge twice. Private rejoin still follows the existing invitation policy.

**Policy decisions still requiring product approval:** whether voluntary pre-cutoff withdrawal should request a refund, the permitted amount/fees and deadlines, and how host withdrawal should affect covered participants. No new voluntary-withdrawal refund policy was invented. Current behavior retains the paid entitlement and excludes the withdrawn player from the decision count.

## 5. Notifications

- Reuses the existing `notifications`, device tokens and per-device delivery records. No parallel inbox system was created.
- Booking confirmation/status/cancellation and late-safe booking reminders; match creation/join/request participation changes, confirmation/cancellation and reminders; verified financial success/failure and refund requested/verified-completed events feed the durable inbox.
- `due_at`, `processed_at`, `attempt_count`, `next_attempt_at`, delivery status and processing leases support recovery and inspection.
- Unique recipient/event keys prevent normal duplicate events. Worker leases and per-device claims prevent ordinary duplicate sends; stale workers cannot complete another worker's lease.
- Push payloads contain generic text and allowlisted routing IDs, not amounts, names, card data or sensitive financial details.
- FCM `UNREGISTERED` disables the token while retaining audit records; generic `INVALID_ARGUMENT` is not assumed to prove token expiry. This follows [FCM error documentation](https://firebase.google.com/docs/cloud-messaging/error-codes).
- The old eleven inbox rows are `historical`, not falsely labelled delivered and not replayed as new pushes.
- External delivery cannot promise exactly once: an uncertain network acknowledgement can still lead to retry delivery. Stored event keys and confirmed per-device delivery records suppress ordinary duplicates.

**Actual state:** Staging inbox events are visible, but new push deliveries remain pending. Native FCM delivery has not been demonstrated.

## 6. Scheduling

- `pg_cron` enabled on Staging. Active job: `arena-phase3-decisions-reminders`, schedule `5 seconds`, calling `public.process_arena_scheduled_events()`.
- Due decisions and reminders are selected by deadlines, not a narrow time window. An outage is followed by catch-up for applicable events.
- Per-match retry counters, retry timestamps and errors are retained. Admin can safely retry due processing without changing financial results.
- Meaningful/failing job runs are retained; idle heartbeat logging is limited to one per five minutes, with successful application log retention of seven days. Extension cron history should also be monitored operationally.
- `arena-scheduler` and updated `push-notifications` were deployed to Staging. Their application handlers require dedicated server secrets and exact Staging identity.
- The hosted gateway JWT checks remain ON until shared secrets/FCM are configured. The optional push scheduling SQL has **not** been executed; no unauthenticated public worker was enabled.
- Optional push activation uses Vault + `pg_net` + cron, as described in [Supabase scheduled functions documentation](https://supabase.com/docs/guides/functions/schedule-functions). Database decisions already work without the HTTP worker.

## 7. User App Changes

- Match details show server status, eligible participant count, threshold, decision time, cancellation reason, withdrawal restriction and own payment/refund state.
- Confirmed withdrawal is disabled with an explanation; server errors also enforce the rule under races.
- Realtime subscriptions refresh match/member and financial state.
- Inbox realtime updates maintain unread state; notification routing prioritizes match/booking/order targets over arena metadata.
- Native push navigation waits until authenticated navigation/profile setup is ready; resolves the recipient's real inbox row under RLS before navigating. Sign-out clears pending routing state.
- Booking notifications target the specific booking; order notifications use the current user's order.
- Staging web acceptance: restored existing user session, opened the genuine confirmation notification, and saw `confirmed`, count 2/2, threshold 2, decision time and withdrawal explanation. The fixture is now past its start, so the action is also disabled as unavailable.

## 8. Owner App Changes

- Added match decision view restricted to owned arenas: status, eligible count, threshold, decision time/outcome/snapshot and cancellation reason.
- Shows court release for cancellation and withdrawal lock for confirmation.
- Schedule refreshes after decision view and inventory changes through existing staff RLS.
- No new Owner financial privileges or payment/refund success controls.
- Actual signed-in Staging view showed the confirmed 2/2 match, cancelled 1/3 match and court-release explanation.

## 9. Admin Web Changes

- Match table shows decision outcome, server eligible count, required count, time and cancellation reason.
- New operations panel shows recent scheduler runs, failed runs separately, notification delivery state/attempts/next retry, and safe retry actions.
- Existing Phase 2 finance/refund views remain the financial source of truth. No manual provider-success override was added.
- Actual Admin session on the explicitly Staging-configured local app showed both scheduler fixtures and pending/historical delivery states.
- Build used Staging variables. The existing local default environment was not used to connect these tests to Production.

## 10. Database Migrations

All eight new migrations below were applied on Staging and recorded in `arena_private.staging_installation` with SHA-256 receipts. Existing applied migrations were not edited or re-applied.

| Version / filename | Purpose |
|---|---|
| `202610080101_phase3_match_decisions.sql` | Final decisions, integer threshold, withdrawal guards, bounded cancellation refund requests |
| `202610080102_phase3_rpc_lock_order.sql` | Consistent lock ordering and decision guards across existing entry points |
| `202610080103_phase3_notifications_scheduler.sql` | Durable inbox events, late-safe reminders, scheduler and permissions |
| `202610080104_phase3_push_queue.sql` | Token lifecycle, leases, retry/backoff and safe delivery retry |
| `202610080105_phase3_lifecycle_summary.sql` | Privacy-safe authorized server lifecycle summary |
| `202610080106_phase3_historical_delivery.sql` | Truthful historical inbox classification |
| `202610080107_phase3_scheduler_recovery.sql` | Independent failed-match retry and bounded heartbeat logging |
| `202610080108_phase3_realtime.sql` | RLS-protected inventory/order/refund realtime publication |

Full Phase 3 file inventory: [PHASE_3_CHANGED_FILES.md](PHASE_3_CHANGED_FILES.md). Generated deployment inputs and screenshots are ignored local build artifacts, not secrets committed to Git.

## 11. Security/RLS

- Ordinary users cannot directly set match decisions, payment/refund results, dispatch push or execute scheduled processing.
- Users can update only their own inbox `read_at`, not delivery status/recipient/payload.
- Staff-only inventory visibility was preserved. Ordinary users use availability RPCs rather than reading staff reservation rows.
- Match summary follows existing match visibility rules; unrelated users cannot inspect private matches.
- Device claims validate recipient/token ownership and active status. Workers require server authorization; no Service Role or FCM private key is present in Flutter/Admin.
- Final decisions and confirmed membership withdrawal remain guarded at database level even through legacy privileged functions.

## 12. Test Results

| Suite | Actual result |
|---|---|
| Phase 1 local PostgreSQL regression | 30 passed |
| Phase 2 local PostgreSQL financial/inventory regression | 41 passed |
| Phase 3 PostgreSQL/RLS/concurrency | 69 passed in main run, plus 3 added cash-reminder cases passed separately: 72 checks tested |
| Edge handler authorization/configuration + FCM transport fake | 6 passed; mocks only in local tests |
| Edge Functions type checks | PASS |
| User `flutter analyze` | No issues |
| User `flutter test` | 23 passed |
| Owner `flutter analyze` | No issues |
| Owner `flutter test` | 2 passed |
| Admin build with explicit Staging environment | PASS |
| Admin existing lint + additional Phase3Operations lint | PASS; no Admin automated test script exists |
| Hosted Phase 2 regression | PASS, including cash-unpaid, authoritative pricing, idempotency, denied forged financial writes and missing-provider configuration |
| Hosted rollback SQL verification | PASS |
| Hosted real-session Phase 3 permissions | 9 checks passed |
| Hosted actual cron execution | PASS — both final decisions, cancellation inventory release, reminder/event deduplication |
| User/Owner/Admin browser acceptance | PASS for lifecycle/inbox/operations views |
| Real Thawani capture/refund | NOT TESTED — credentials unavailable |
| Android/iOS foreground/background/terminated push | NOT TESTED — no configured Firebase client or connected native device |

Coverage includes 79/80/100/0 percent; capacities 5/10/12/14/20; repeat/late decisions; join/leave/payment races; withdrawal bypasses; joining after confirmation and rejection after start; individual/host refund requests and duplicates; paid rejoin; late captured payment; cash reminder catch-up; queue claims/stale workers/retry/invalid token; scheduler fault isolation/recovery; denied direct writes and unauthenticated workers.

Financial success/refund completion tests use the isolated loopback database only. Hosted SQL fixtures were legacy no-charge records; they are not evidence of successful Card payment.

## 13. Staging Verification

1. Reviewed reports, current schema, applied receipts, booking/payment functions and inventory conflicts before changes.
2. Preflight: ten bookings, one historical match, zero captured electronic payments, zero unresolved inventory migration conflicts, no pre-existing Phase 3 versions.
3. Created private `arena_private.phase3_backup_20261008`: 329 records including original booking/match/order/inventory/inbox data, function definitions and constraints. This is an in-project recovery snapshot, **not** an offsite full database dump/PITR guarantee.
4. Applied new versions atomically with source hashes and installation receipts; enabled database cron on the confirmed Staging project.
5. Hosted rollback tests left no financial fake records. Two clearly labelled retained scheduler fixtures verified real background execution:
   - `f3000000-0000-4000-8000-000000000001`: confirmed, eligible 2/2, reservation retained.
   - `f3000000-0000-4000-8000-000000000002`: cancelled, eligible 1/3, reservation released.
   They were explicitly legacy no-charge scheduler tests; their interval was chosen for catch-up testing and is not a customer checkout example.
6. Final read-back on 9 October: cron active, 8,650 successful cron runs at observation, recent application job runs succeeded with no errors; exactly two fixture reminders and three decision notifications, still ten original bookings, zero captured payments and zero unresolved inventory conflicts.
7. Updated server functions deployed only to Staging; actual User/Owner/Admin web views verified against the same fixtures.

Local proof screenshots are in `build/phase3-evidence/`, including `staging-final-scheduler.png`, `user-confirmed-match.png`, `owner-match-decisions.png`, `admin-match-decisions.png` and `push-final-deployed.png`. Do not re-run fixture-creation or applied installation SQL as a verification step.

## 14. Manual Actions Required

Complete these on **arena-staging only**, without sharing secret values in chat.

1. **Firebase native configuration:** choose the intended Firebase project and register the actual Android package/iOS bundle IDs. Add the matching `google-services.json` at `android/app/` and `GoogleService-Info.plist` to the iOS Runner target. Neither file is currently present. Enable the required iOS Push Notifications/Background Modes capabilities and upload the APNs authentication key to Firebase Project settings → Cloud Messaging. Follow [official Flutter FCM setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started). Client configuration is distinct from a server private key; never include the service-account JSON in the app.
2. **Server secrets:** Supabase Dashboard → arena-staging → Edge Functions → Secrets. Add `FIREBASE_SERVICE_ACCOUNT_JSON` (server service-account JSON authorized for the same Firebase project), and independently generated strong `ARENA_SCHEDULER_SECRET` and `PUSH_DISPATCH_SECRET`. Existing Supabase service credentials are server-provided; never copy Service Role to frontend environment files.
3. **Vault:** Dashboard → Vault, add secret named `arena_scheduler_secret` with the **same value** as `ARENA_SCHEDULER_SECRET`; keep it private. Do not paste its value into a SQL snippet committed to source control.
4. **Worker gateway:** only after secrets are saved, review the deployed shared-secret handlers, then set legacy JWT verification OFF for `arena-scheduler` and `push-notifications` in each function's settings. They use server-to-server shared-secret authentication instead of a user JWT. This has not been changed by the agent. Verify wrong/missing credentials return 401 and authorized invocation succeeds before scheduling push.
5. **Push schedule:** review and run `supabase/staging/phase3_activate_push_after_secrets.sql` on the confirmed Staging project. It enables `pg_net` and the 30-second push-dispatch cron using Vault. It is not a migration to replay and has not been executed. Existing five-second database cron should remain active.
6. **Device acceptance:** connect a real Android/iOS device, run the Staging app, grant notification permission and verify own token registration. Trigger a genuine Staging event; verify inbox, server delivery record and actual device notification in foreground/background/terminated states, correct target after opening, unread state and sign-out/recipient privacy. Test invalid-token recovery and worker retry. Do not mark native push PASS based on a web inbox or FCM mock.
7. **Thawani:** follow the existing Phase 2 configuration report and add provider secrets manually server-side when available. Test Sandbox capture and real verified refund end-to-end before financial integration acceptance; no Phase 3 code requires a fabricated key.
8. **Product policy:** approve the voluntary pre-cutoff refund policy described in section 4 before implementing a new financial behavior.

No remaining Phase 3 schema migration requires manual application. Production activation/deployment is outside this phase and must be reviewed separately.

## 15. Pending Thawani/FCM Dependencies

- FCM server credentials, native client configuration, APNs configuration where applicable, secure push schedule activation and actual native delivery acceptance remain outstanding.
- True payment/refund verification requires Thawani Sandbox credentials. Captured amounts must remain refund-required/requested until the real provider confirms completion.
- The decision/reminder database scheduler is already active and was tested with all applications independent of processing; push dispatch is intentionally not reported active.
- Do not change the final status to READY until required configuration and actual Staging/device acceptance are completed and recorded.

`PHASE 3 STATUS: NEEDS ACTION`
