# PHASE 3 REFUND POLICY IMPLEMENTATION REPORT

Verification date: 9 October 2026, Asia/Muscat. Scope: ordinary cancellation, match withdrawal refunds and related inventory only. Environment: **arena-staging**, `gtcrijikfaglqcwqozel`. Production was not modified; Phase 4 was not started.

Reviewed the Phase 1 implementation/Staging reports, Phase 2 implementation/changed-files reports, Phase 3 implementation/changed-files reports, booking/match/payment/add-on migrations, existing SQL functions, Edge payment handler and three application integrations. Existing local changes were preserved. Previously applied migrations were not edited.

## 1. Ordinary Booking Cancellation — 150 minutes

- The existing `cancel_arena_booking` RPC now checks the ordinary booking owner and server time **after acquiring the existing arena and booking locks**. `starts_at - server_now >= interval '150 minutes'` permits the exact boundary. Less time, and already-started bookings, are rejected.
- Booking updates, cancellation audit, entitlement revocation, Court release, add-on release and refund request creation commit together. Historical bookings and original payment records remain.
- Repeated cancellation of an already-cancelled booking is safe, including after its original deadline. Concurrent requests cannot restore stock or create refunds twice.
- Pending ordinary checkout cancellation uses `cancel_pending_booking_checkout`. Existing `cancel_unstarted_checkout` delegates ordinary requests to this policy, closing the legacy deadline bypass. A booking trigger also protects legacy definer updates made on behalf of the customer.
- Existing Owner/Admin operational cancellation authority is preserved; this change does not grant new cancellation or financial privileges. Manual bookings are not converted into ordinary user bookings.

## 2. Match Withdrawal — 90 minutes

- The existing 90-minute decision, integer 80% calculation, final decision lock, capacity and post-confirmation join rules remain. Withdrawal is strictly before the decision boundary; confirmed participants cannot withdraw through RPC or legacy membership changes.
- Individual paid withdrawal removes the confirmed participant and revokes payment entitlement, preserving the ledger and requesting its full remaining electronic refund.
- A new join request needs a new pending payment entitlement; an old idempotency key returns its old revoked order rather than producing another charge. Refunded/refund-requested entitlement cannot authorize a new seat.
- Withdrawal of an individually paying host does not stall the match decision or make its active rental inventory available. A replacement may use the released seat under existing capacity/pricing rules.
- A participant covered by a host has no personal payment to refund.
- **Host-pays-all creator withdrawal is deliberately rejected** with `HOST_PAYS_ALL_WITHDRAWAL_REQUIRES_POLICY_DECISION`; no ownership transfer or invented financial redistribution was implemented.

## 3. Full Refund Policy

- Eligible ordinary cancellation, paid individual withdrawal and automatic match cancellation request **100% of the unrefunded captured electronic amount**, including paid add-ons. Amounts remain integer baisa; no arena pricing or commission calculation was changed.
- Refund requests belong to the original checkout/payment and payer. Existing successful refunds and nonfailed reserved requests are deducted when computing the remaining requestable amount. Refunds cannot exceed captured funds.
- Refund request keys are deterministic. Duplicate cancellation, payment event and refund completion are idempotent. Original provider/payment evidence is retained.
- Requested refund is not successful refund. Real payment remains `paid` until a verified refund result changes it; fulfillment may be `refund_required`. Failed requests remain visible for review rather than silently becoming successful.
- Unpaid Cash cancellation creates no electronic refund. Cash ledger/history remains truthful. No assumption was added that recorded cash is refundable through Thawani.
- A pending Card cancellation revokes fulfillment without fabricating a provider cancellation or refund. A subsequently verified late capture enters the refund-required path, never re-confirms the booking, creates no Court allocation and consumes no new stock.

## 4. Thawani Integration Status

The existing provider adapter, provider contract and server verification were preserved. The hosted `arena-payment` handler now rejects payment starts for cancelled, revoked or nonpending fulfillment orders before contacting the provider. Verification remains possible for late results; a checkout URL is returned only while the order is still payable. The updated function was deployed to Staging with its JWT gate retained.

**No keys are available. No actual Card charge or actual refund was issued.** Provider success/refund cases were tested with local-only fakes. The existing live refund executor/merchant refund-reference acceptance still requires completion and Sandbox testing; this request prepares safe refund requests, not a falsely completed refund service. Redirects remain navigation, never proof.

## 5. Add-ons Inventory Restoration

- New fulfilled orders record whether inventory was tracked, how much was actually debited and initial delivered quantity. A private lifecycle trigger runs before existing automatic match cancellation can release new host add-ons.
- Consumables restore only debited, undelivered, previously unrestored quantities. Delivered quantities are never returned. Cancellation and inventory edits serialize on the existing arena lock.
- Admin-only `admin_record_addon_delivery` records monotonic delivered quantity, actor and time for tracked active consumables. User and Owner cannot use it. No bulk historical assumption was introduced.
- Rentals release their time reservation on parent cancellation; half-open intervals and existing Court/inventory locks remain. Active matches retain rental quantities while an individual host refund is pending; Admin cannot lower stock below those active reservations.
- Generic add-on kind/snapshot fields are reused. Service add-ons are not treated as consumables, and cancelled snapshots retain historical prices.
- **Four pre-existing fulfilled add-on rows have unknown delivery/debit evidence.** They were preserved without automatic restock. Final raw unknown count is six because the cancelled, never-fulfilled pending Card test also has two rows with no debit. These two are not historical stock discrepancies.

## 6. Court Availability

The Phase 1 allocation/exclusion system was reused. Cancellation removes only the associated reservation; blocks, other bookings and confirmed matches remain. The actual Staging cash test returned its Court to availability immediately and restored its Water quantity while releasing rackets. Local tests retain an existing block and book the newly available remaining Court without double booking.

## 7. User App

Server-derived cancellation panels were added to ordinary booking details/list and pending ordinary checkout details. They show the 150-minute policy, expected electronic refund, confirmation dialog, disabled deadline and actual refund request state. The panel refreshes server eligibility periodically, disposes its timer and verifies state after interrupted requests. Cancelled payment orders cannot reopen checkout.

Match details keep the 90-minute rule and confirmed withdrawal lock; show the user's server-derived refund entitlement and host-pays-all creator restriction. Arena styling was preserved.

Actual User C created a no-charge Cash booking for **10 October, 16:00–16:30, 5.000 OMR**, confirmed cancellation through the dialog and saw `CANCELLED` in the retained history. An expired booking displayed a disabled cancellation action. A delayed same-screen card refresh exposed a setState closure returning a Future. It now uses a synchronous block; the parent refresh starts before reloading the child policy, and the child explicitly displays cancellation. Final analyze/tests passed. A fresh 17:00–17:30 Cash create/cancel cycle verified the card changed to CANCELLED and moved into history in the same screen without navigation. A 16:30–17:00 intermediate test booking was also cancelled and retained.

## 8. Owner App

Booking finance shows cancelled status, true payment/refund status, unchanged base/add-on snapshots, restoration quantities and release evidence. Cancelled unpaid Cash is labelled **Cancelled cash booking — no electronic refund**, not an amount due at the arena. Owner cannot confirm a refund or record Admin-only delivery. Actual Staging Owner details displayed the cancelled 13.000 OMR test booking, Water restored 2 and released rackets.

## 9. Admin Web

Finance view shows original payer, cancellation policy reason/time/actor, paid/total/requested/refunded amounts, true refund/provider references and delivered/restored/released add-on evidence. Existing booking audit columns remain. Delivery recording appears only for Admin, with server enforcement; no manual successful-refund control was added.

Actual Admin view was inspected for the 13.000 OMR cancelled Cash order and cancelled pending Card order, including restoration and zero fabricated refunds. After a final page reload, the staff session required renewal. The user renewed login, and the fresh Admin view verified User C's 5.000 OMR cancelled booking, actor/time/reason and zero requested/refunded Cash amounts. The Staging build and lint passed.

## 10. Security / RLS

Users cannot directly change booking/payment/refund/restored-stock state or cancel another user's order. Time guards protect legacy paths; refund-requested entitlement cannot authorize a seat. Owner cannot cancel another arena, mark Card paid, confirm refunds or record delivery. Admin can request only bounded refunds and record permitted delivery; provider result confirmation stays server-only. Private/trigger functions are not exposed to anonymous/authenticated clients. Public policy summaries enforce own booking/order or existing operator scope and do not leak another player's finance.

Actual Staging sessions verified unauthorized cancellation and direct payment/refund/restoration writes were denied. The hosted cancelled-order start guard returned 409 before any provider session creation. No secrets were added to Flutter/Admin or Git.

## 11. Database Migrations

Both new migrations were applied **once, transactionally, to Staging**, after identity/preflight/backup checks. Installation receipts match these SHA-256 values. Do not replay them or regenerate them with the preparation helper.

| Migration | SHA-256 | Staging |
|---|---|---|
| `202610090101_phase3_refund_cancellation_policy.sql` | `21afc0229a1963dbe582bad1d9a440719760b2991732a51d5cb11be0c1d99a4f` | Applied |
| `202610090102_phase3_refund_entitlement_boundaries.sql` | `df3269fbadf9dd3a429313f498e5265de4fd07f5c99853579ee74ecbe2e7f017` | Applied |

No duplicate migration versions were found. Phase 1 hashes still match the reviewed baseline. Existing migrations were preserved; function replacements are contained in the new migrations only.

## 12. Regression Test Results

| Suite/check | Result | Scope/limits |
|---|---|---|
| Phase 1 PostgreSQL/RLS/concurrency | 30 PASS | Fresh local database with prior schema and policy installed |
| Phase 2 pricing/payment/inventory/security | 41 PASS | Local; only obsolete paid-rejoin expectations updated for the authorized new policy |
| Phase 3 decision/scheduling/finance/security | 72 PASS | Local; same deliberate rejoin expectation change |
| Refund policy PostgreSQL/RLS/concurrency | 38 PASS | 180/150 inclusive/149/started, Cash/Card/late capture, full refund, delivered/unknown stock, retries, cancellation/stock race, cutoff after lock, blocks, match entitlement and local fake provider completion |
| Hosted refund-policy public-client checks | 8 PASS | Real two-user Auth sessions; Cash cancel/retry/restock/availability, unauthorized/direct writes, cancelled payment start, pending Card cancel |
| Hosted Phase 3 public-client checks | 9 PASS | Decision/withdrawal/queue/privacy/inbox regression |
| Hosted Phase 2 public-client checks | PASS | Pricing/Cash/idempotency/Card pending/RLS/forged reconciliation/missing keys/CORS/unauthenticated request |
| User `flutter analyze` / `flutter test` | PASS / 23 PASS | Final source |
| Owner `flutter analyze` / `flutter test` | PASS / 2 PASS | Final source |
| Admin Staging build / lint | PASS / PASS | Includes explicit lint of Finance/Phase3 operations panels; no configured Admin unit-test suite |
| Thawani adapter Node tests | 7 PASS | Fakes only |
| Edge Deno tests / payment handler check | 7 PASS / PASS | Includes actual handler with test-only capture/fetch, cancelled/revoked guard and missing-key response |
| Git whitespace validation | PASS | Existing unrelated local edits retained |
| Real Thawani charge/full refund/late webhook | NOT TESTED | Credentials unavailable |
| Renewed-session Admin/newest fixture | PASS | User C cancellation audit/amounts verified after login |
| Post-fix uninterrupted User cancellation cycle | PASS | Fresh 17:00 booking changed to CANCELLED/history without navigation |
| Native push delivery | NOT TESTED | Existing FCM dependency; no new financial-success push fabricated |

Exact 150-minute eligibility is tested against the deterministic server predicate; the real cancellation RPC is also tested waiting across the cutoff under a held arena lock and correctly rejecting after lock acquisition. Local fake financial outcomes were never applied to hosted Staging. Existing notification queue hooks are reused for cancellations/refund events, rather than a parallel notification system.

## 13. Staging Verification

- Verified Dashboard name/ref before every SQL/deployment operation: **arena-staging / gtcrijikfaglqcwqozel**.
- Preflight: 10 bookings, zero captured payments/refunds, eight Phase 3 baseline receipts, zero unresolved inventory conflicts and zero duplicate participant entitlement groups.
- Recovery snapshot: `arena_private.refund_policy_backup_20261009`, **326 rows**, including existing bookings/matches/participants/orders/add-ons/arena inventory/Court reservations and 284 function definitions. Access revoked from public/anon/authenticated. This is an in-project recovery snapshot, **not an offsite dump or independently tested PITR backup**.
- Final readonly verification: both correct new receipts; all **10 original bookings retained**; zero historical add-on quantities restored; Water stock **17**; zero captured payments and zero refunds; **four new ordinary test bookings cancelled**, zero cancelled bookings retaining a Court reservation; zero inventory conflicts; existing database scheduler active; earlier 90/80 fixtures still confirmed with count 2 and cancelled with count 1.
- One original expired booking transitioned `upcoming` → `previous` during verification (9 October 10:00–10:30 Muscat). It was not cancelled or deleted; this is existing lifecycle behavior. No other original booking status changed.
- Retained fixtures: User A 13.000 OMR Cash booking cancelled with Water ×2/rackets ×2; User A pending Card request cancelled without booking or stock debit; User C three 5.000 OMR Cash UI bookings at 16:00, 16:30 and 17:00 cancelled. All are no-charge test activity. Original ledger/history remains.
- Evidence screenshots are ignored local files under `C:/monther/MN/my_apps/playon/build/refund-policy-evidence/`: preflight, migration receipts, deployed guard, final SQL, User dialog/cancelled card and Owner finance.

## 14. Pending Manual Actions

1. Application acceptance completed: Admin session renewed and fixture audit verified; final User Cash cycle verified immediate cancelled/history display. No further login action is required for this report.
2. Reconcile the four historical fulfilled add-on records with actual stock/debit/delivery evidence. Do not bulk-fill delivery=0 or blindly add stock. New Admin delivery recording is for known tracked rows; historical reconciliation requires reviewed evidence and a separate narrowly scoped correction if needed.
3. Obtain Thawani **Sandbox** credentials and add them yourself to Staging Dashboard → Edge Functions → Secrets: `THAWANI_SECRET_KEY`, `THAWANI_PUBLISHABLE_KEY`, `THAWANI_WEBHOOK_SECRET`, `PAYMENT_RECONCILE_SECRET`. Do not send keys in chat or commit them. Configure `THAWANI_ENV=sandbox`, exact `THAWANI_SUCCESS_URL`, `THAWANI_CANCEL_URL`, and `PAYMENT_ALLOWED_ORIGINS` as in the Phase 2 report.
4. Use the existing Staging webhook `https://gtcrijikfaglqcwqozel.supabase.co/functions/v1/thawani-webhook`. Configure its HMAC/job authentication before any existing manual gateway/scheduler activation. Keep `arena-payment` JWT verification ON. Complete/review the actual refund executor and provider reference mapping, then test real Sandbox full refund, failed/retried refund, duplicate completion, late capture after cancellation and original-payer return. Requested refund must remain pending until genuine provider confirmation.
5. Existing Phase 3 native FCM credentials/device-delivery verification remains separate and pending. No push success on Android/iOS is claimed here. No Production action is required or authorized by this report.

## 15. Decisions Requiring Approval

**Host-pays-all creator self-withdrawal before 90 minutes:** decide what should happen to the match and its host funding before enabling this path. The implementation blocks only that path; it does not transfer ownership, retain funding while pretending the host left, or distribute the host's money. Covered participant withdrawal and automatic cancellation/full host refund requests are implemented.

## CHANGES ALREADY APPLIED LOCALLY

User root `C:/monther/MN/my_apps/playon/`:

- New: `lib/features/bookings/pages/booking_cancellation_panel.dart`.
- Modified: `lib/features/bookings/pages/my_bookings_page.dart`, `lib/features/bookings/pages/checkout_page.dart`, `lib/features/games/pages/match_details_page.dart`.
- New migrations: the two files listed in section 11 under `supabase/migrations/`.
- Modified: `supabase/functions/arena-payment/index.ts`.
- New tests/helpers: `supabase/tests/prepare_refund_policy.cjs`, `supabase/tests/run_refund_policy.cjs`, `supabase/tests/refund_payment_edge_test.ts`.
- Modified test runners: `supabase/tests/run_phase1.cjs`, `supabase/tests/run_phase2.cjs`, `supabase/tests/phase3_financial_cases.cjs`.
- New Staging tooling: `supabase/staging/refund_policy_preflight.sql`, `supabase/staging/refund_policy_backup.sql`, `supabase/staging/refund_policy_verify.sql`, `supabase/staging/verify_refund_policy_client.cjs`.
- Modified Staging tooling: `supabase/staging/build_phase3_install.cjs`.
- New report: `PHASE_3_REFUND_POLICY_REPORT.md`.

Owner: `C:/monther/MN/my_apps/arena_owner/lib/booking_payment.dart` modified.

Admin: `C:/monther/MN/my_apps/playon_admin/src/FinancePanel.tsx` and `src/ArenaAdminApp.tsx` modified.

Generated/ignored: local isolated PostgreSQL fixtures, Flutter/build caches, explicitly Staging-configured Admin build, deployment/install bundles, screenshots and real-session evidence. Auth token files were refreshed privately; no tokens/keys are included in the report or source. Owner/Admin directories have no Git repository, so their changes were reviewed directly; User Git status/diff was reviewed without resetting prior work.

`PHASE 3 REFUND POLICY STATUS: NEEDS ACTION`

The server cancellation/refund-request/inventory policy is installed and tested on Staging. Overall READY is withheld for actual provider refund acceptance, the explicitly unresolved host-pays-all creator policy and historical inventory reconciliation above.
