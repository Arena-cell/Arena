# PHASE 2 IMPLEMENTATION REPORT

Updated: 2026-10-08. Target: **arena-staging / gtcrijikfaglqcwqozel** only.

`PHASE 2 STATUS: NEEDS ACTION`

The financial architecture, Cash checkout, add-ons, server pricing and security boundaries are implemented. Thawani credentials are absent. Real Card collection, real signed provider delivery and real refunds have **not** passed acceptance testing. No paid result is simulated in the deployed application. Phase 3 and Production deployment are outside this work.

## PAYMENT

- Booking status and payment status are separate. Cash creates a fulfilled booking with `payment_method=cash`, `payment_status=unpaid`: payment is due at the arena.
- Card creates a pending checkout order. Without Thawani configuration the deployed payment endpoint returns HTTP 503 `PAYMENT_PROVIDER_NOT_CONFIGURED`; it does not claim a provider creation, charge or create a paid booking.
- Amounts use integer baisa, 1000 baisa = 1 OMR. The server computes the hourly charge, catalog prices, quantities, valid coupon and total. A client expected total can only reject a stale quote; it cannot set the price.
- Payment states: unpaid, pending, paid, failed, cancelled, refunded, partially_refunded. Fulfillment has separate pending/fulfilled/cancelled/refund_required states. Thawani checkout responses currently map unpaid/paid/cancelled; transport failures remain pending for recovery, rather than inventing proof of a final financial failure.
- User request keys are bound to user and exact request payload, persisted in the application for retries. Provider creation is claimed once; uncertain creation is recovered by client reference instead of blindly creating another charge.
- Redirects are navigation only. The server retrieves the authoritative provider session and compares session, client reference, currency and amount before applying a financial outcome. Duplicate/late events cannot reverse paid or repeat fulfillment.
- **Inventory strategy:** pending Card orders do not hold a court. After verified capture, court allocation and stock consumption occur transactionally under the existing arena lock/exclusion constraint. If the court, coupon, stock or capacity is unavailable, the order records captured funds and `refund_required`; no double booking is created. A real refund still needs provider processing.
- Refund ledger stores original/remaining amount, requested amount, reason, provider reference, status and timestamps. Admin may request bounded amounts; users/owners cannot. Server-only confirmation updates refunded balances once. The Thawani refund adapter is prepared; an automated live refund executor and provider payment-reference acceptance remain to be completed/tested with Sandbox credentials. No real refund has been issued.

## MATCH PAYMENTS

- New public matches are Card only. Legacy creation RPC cannot create an unpaid match.
- `pay_individually`: the host pays seat zero and each participant requires a verified paid entitlement before joining. The server assigns deterministic seat shares: 10.000 OMR / 3 = 3.334 + 3.333 + 3.333 exactly.
- `host_pays_all`: host pays the real full total. Only verified full payment enables participant coverage; later participants join without a payment gateway and see “Paid by host”. The booking value remains the real total.
- Private invitations remain required. Accepting an individual-payment request invites the player; it does not bypass their payment.
- Paid participants can leave and rejoin using the same entitlement without being charged twice. Paid seats are not automatically resold. Refund/abandoned-seat lifecycle policy needs real provider acceptance before launch.
- Financial match fulfillment was verified using isolated local provider outcomes only. No unpaid Staging match was made paid to exercise the interface.

## ADD-ONS

- Generic `addon_types`, `arena_addons`, `booking_addons` support additional services without a new column per service.
- Water is displayed only when enabled in the arena catalog. Consumables support optional stock and decrement on fulfillment. Cancellation does not automatically replenish consumed stock; Admin must make the deliberate stock adjustment.
- Rackets are rentals. Availability is the peak allocation over overlapping half-open intervals, so adjacent reservations reuse capacity. Catalog edits and checkout fulfillment share the arena lock to prevent overselling.
- Admin controls enablement, integer unit price and stock/capacity. Owner has read access for their arenas; their permissions were not expanded to edit prices or stock.
- Booking snapshots keep base price, addon code/name/kind/unit price and quantity. Later catalog or arena price edits do not rewrite historical orders.

## DATABASE

The following new migrations are applied on Staging. Their checksums were checked against private installation receipts; they must not be reapplied or edited. Dashboard execution was used, so these receipts are **not** Supabase CLI migration-history entries.

| Migration | Purpose |
|---|---|
| 202610040001_phase2_financial_schema.sql | Financial ledger, add-on catalogs/snapshots, refund and event records, read scopes |
| 202610040002_phase2_checkout.sql | Server quote, exact money split, stock/court allocation, idempotent Cash/Card checkout |
| 202610040003_phase2_payment_boundaries.sql | Provider claims/reconciliation, refunds, participant payment entitlement, legacy boundaries |
| 202610040004_phase2_lifecycle.sql | Cancellation/refund review, private invitation/payment lifecycle |
| 202610040005_phase2_match_summary.sql | Safe match pricing/coverage summary |
| 202610050001_phase2_paid_rejoin.sql | Reuse verified paid membership when rejoining |
| 202610080001_phase2_manual_booking_price_update.sql | Skip notification recipients without a user so owner manual bookings do not break arena price edits |

Existing `bookings.payment_status` was extended rather than duplicating the concept. Historical unpaid manual bookings are Cash; other historical bookings remain `legacy_unknown`, with no inferred paid state.

Before the initial installation: unresolved inventory = 0; historical non-unpaid rows = 0; existing Phase 1 receipts checked; private baseline snapshots captured. `arena_private.phase2_backup_20261004` contains bookings (7), matches (1), memberships (1), public function definitions (248) and constraints (30). Local source baseline: `C:/monther/MN/my_apps/phase2-baseline-20261004`. This is an in-project SQL snapshot and local source copy, **not an offsite/full database disaster backup**.

## SECURITY

- New financial/catalog tables have RLS. Authenticated users have scoped reads; direct financial writes are revoked for User, Owner and Admin. Required Admin catalog/refund requests use guarded RPCs.
- Service-only RPCs reconcile provider results and confirm refunds. Owner cannot change Card status, provider references, catalog prices or another arena's financial records.
- Financial match membership has a database trigger, closing direct/legacy join bypasses. Flutter cannot grant `covered_by_host`.
- Edge Functions use server credentials only and explicitly restrict the target to Staging. No card number/CVV is stored. No Thawani keys were added to Git or frontends.
- Provider adapter rejects Production mode in this phase. No real or fake payment-success switch exists in the application.
- Webhook validates documented HMAC over the exact raw body/timestamp and verifies the current provider session. Reconciliation job requires its own secret, not a user JWT.
- Current hosted webhook/job endpoints still have the Dashboard legacy JWT gate ON. This safely blocks unauthenticated provider/job calls until configuration; it must be switched OFF for these two endpoints when their own HMAC/job authentication is configured. `arena-payment` keeps JWT verification ON and verifies the real user again.
- Dashboard flags the existing Phase 1 `public_profiles` view as SECURITY DEFINER. It intentionally exposes only id, username, display/first/last name and avatar to authenticated users; no phone, birth date or financial fields. This pre-existing advisory was observed and not silently reported as absent.

## USER APP

- Booking review uses server catalog, quantity controls, three-decimal price summary and Cash/Card choice.
- Match review is Card only with “Pay my share” / “Pay for everyone”. Joining uses the server payment entitlement or verified host coverage.
- Payment request page explains missing credentials, supports authoritative verification/cancellation where safe, and exposes persistent request history in Settings.
- Web return handling loads only the authenticated user's order after the Phase 1 session/profile gate. URL success/cancel does not set payment state. Native Android/iOS return links are not configured or accepted as tested.
- Added an explicit empty state to payment history after visual review. Fresh Card UI test created a 5.000 OMR pending request and displayed “Thawani payment keys have not been configured yet. No payment was taken.” No provider page or paid result was fabricated.

## OWNER APP

- Booking details show base amount, add-on quantities/snapshots, discount, total, method and status, including Cash due at arena.
- Own-arena catalog is read-only. Booking value labels avoid calling confirmed-but-unpaid bookings collected revenue.
- Compilation/static checks passed. Fresh authenticated visual review passed: the same User cash booking shows base 5.000, water 0.500, racket 1.000, total 6.500 OMR, unpaid Cash due at arena. Own-arena catalog shows water stock 17 and racket capacity 8. Booking detail times now use Oman time and price uses three decimals.

## ADMIN WEB

- Arena availability details include safe add-on configuration via Admin RPC.
- Booking finance panel shows payer, payment method/status, fulfillment, real value, amount due, match mode, provider references, snapshots and refund records. It exposes no API secrets or card data.
- Admin catalog changes were exercised on Staging in the earlier session and used by the hosted inventory tests. Fresh finance-panel visual acceptance passed after the Admin session resumed: the same 6.500 OMR unpaid Cash order, quantities and payer were visible, alongside pending Card without a provider reference. Obsolete fixed-water columns were removed from the booking table to avoid showing false zero quantities for catalog orders.
- The final build injected Staging settings explicitly. The existing local Admin `.env` default was not changed; always inject Staging settings when testing. Never run the default against Production for this task.

## TEST RESULTS

Verified on 2026-10-08 unless stated otherwise:

| Check | Result |
|---|---|
| Phase 1 PostgreSQL regression, permissions, availability and races | PASS: 30 checks, fresh loopback database |
| Phase 2 PostgreSQL pricing, snapshots, financial permissions, Cash, Card outcomes, membership, refunds and rental concurrency | PASS: 41 checks, fresh loopback database |
| Thawani adapter contracts, missing keys, Production guard, verification, HMAC, uncertain transport | PASS: 7 tests; test fakes only |
| User flutter analyze | PASS, no issues; rerun after empty-state change |
| User flutter test | PASS: 23 tests |
| Owner flutter analyze | PASS, no issues |
| Owner flutter test | PASS: 2 tests |
| Admin build with Staging environment | PASS |
| Admin configured lint + FinancePanel lint | PASS; no Admin test script exists |
| Canonical three Edge Functions Deno type check | PASS |
| Hosted Staging Cash, quote, exact retry, RLS/direct-write rejection, cross-user visibility | PASS |
| Hosted Card missing configuration | PASS: HTTP 503, no provider claim/charge/paid booking |
| Hosted Admin-configured Water/Rackets, 17.000 OMR snapshot, overlap remaining 2, adjacent remaining 8 | PASS |
| Hosted webhook/job ordinary-user request rejection | PASS: HTTP 401 |
| Hosted migration receipts | PASS: seven installed versions; no rerun of prior migrations |
| Available User/Owner/Admin web financial UI | PASS for available web behavior: User Cash/add-on review, submit, persisted history; Card pending and explicit missing-key message; Owner breakdown/catalog and Admin ledger. Real provider/native journeys NOT RUN |
| Real Sandbox Card, signed Thawani webhook, actual refund and scheduled recovery | NOT RUN: credentials absent |
| Native callback/app-close payment recovery | NOT RUN on physical devices |

Provider success, failure/cancellation, duplicate event, partial/full/failed refund outcomes in the local database are **test evidence, not proof of a live provider integration**. Generated Dashboard bundles transpile and execute; canonical source passes Deno check. The inline generated TypeScript is not claimed to pass a separate strict implicit-any check.

## MANUAL ACTIONS REQUIRED

1. User/Owner/Admin Staging sessions were confirmed and financial Cash screens reviewed; no additional staff credentials are requested.
2. Obtain Thawani **Sandbox** merchant access and add credentials yourself as described below. Do not send secret keys in chat.
3. After configuration, complete supervised real Sandbox checkout/cancel, duplicate/late delivery, app-close/reopen verification, captured-but-unavailable refund review and provider refund tests. Automate/review the live refund executor before claiming refunds ready.
4. Activate scheduled reconciliation only after its secret/authentication is configured. No cron job was activated without credentials.
5. Establish the final HTTPS Staging return origin and native deep-link configuration if mobile acceptance is required. No Firebase configuration change is required by the implemented payment architecture.
6. Do not re-run the already applied installation bundles. Future schema changes require new migrations. Production is not authorized.

## PAYMENT PROVIDER REQUIRED

Provider selection is complete: **Thawani**. What remains is merchant Sandbox configuration and live acceptance, not choosing another provider. Database, server adapter, session/reference recovery, financial reconciliation boundaries, signed webhook handler and refund ledger are ready for that configuration. Real Card and real refunds are not ready for use yet.

### THAWANI CONFIGURATION REQUIRED

1. **Supabase Dashboard → arena-staging (`gtcrijikfaglqcwqozel`) → Edge Functions → Secrets:** add `THAWANI_SECRET_KEY`, `THAWANI_PUBLISHABLE_KEY`, `THAWANI_WEBHOOK_SECRET`, and a strong independently generated `PAYMENT_RECONCILE_SECRET`. All stay server-side, including the publishable key in this implementation. Built-in `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are supplied to Edge Functions; never copy them into Flutter/Admin.
2. Set server environment values `THAWANI_ENV=sandbox`, `THAWANI_SUCCESS_URL`, `THAWANI_CANCEL_URL`, and comma-separated exact `PAYMENT_ALLOWED_ORIGINS`. The committed `.env.example` is a list of names with empty values, not the place to commit real credentials.
3. For current local **web** Sandbox testing, success URL is `http://127.0.0.1:5178/?payment_return=success`; cancel URL is `http://127.0.0.1:5178/?payment_return=cancel`. The server appends `order_id`. Configure them in the merchant settings if allowlisting is required; the integration sends them when creating the session. If the merchant disallows local HTTP, use an actual HTTPS Staging host and provide that origin; no domain was invented or registered here.
4. Webhook URL: `https://gtcrijikfaglqcwqozel.supabase.co/functions/v1/thawani-webhook`. Configure the merchant webhook signing secret and supported checkout events. The handler still independently retrieves the session; a redirect or unsigned callback is never proof.
5. Supabase → Edge Functions → `thawani-webhook` → Settings: turn legacy JWT verification OFF only after its HMAC secret is configured. Do the same for `payment-reconcile` after its job secret is configured. Keep `arena-payment` JWT verification ON. Deploy from the reviewed source/config. The hosted toggle changes remain manual and have not been claimed complete.
6. Schedule POST to `https://gtcrijikfaglqcwqozel.supabase.co/functions/v1/payment-reconcile` with `Authorization: Bearer <PAYMENT_RECONCILE_SECRET>` from a secure server scheduler/Vault. Do not embed it in any browser or mobile client. Verify rejected invalid credentials and recovery before enabling the schedule.
7. Sandbox uses `https://uatcheckout.thawani.om/api/v1` and sandbox merchant keys. Test authoritative amount/reference matching, valid and invalid signatures, duplicate events, cancellation, network loss, delayed success and real provider refunds before financial acceptance.
8. **Future Production transition:** requires explicit authorization, reviewed new deployment/environment, Production merchant keys, HTTPS production callbacks/origins/webhook, job secrets, monitoring, refund acceptance and backup. The current server/adapter intentionally refuses Production; a deliberate reviewed gate change is required. None of these Production actions were performed.

Official contracts reviewed: [Create session](https://thawani-technologies.stoplight.io/docs/thawani-ecommerce-api/a2a9e57e10521-create-session), [Retrieve session](https://thawani-technologies.stoplight.io/docs/thawani-ecommerce-api/50259f1e290c9-retrieve-session), [Recover by client reference](https://thawani-technologies.stoplight.io/docs/thawani-ecommerce-api/dde52edbe8db7-retrieve-session-by-client-reference), [Webhook authentication](https://thawani-technologies.stoplight.io/docs/thawani-ecommerce-api/5534c91789a48-thawani-e-commerce-api), [Refund](https://thawani-technologies.stoplight.io/docs/thawani-ecommerce-api/cc21ee27b164f-create-a-refund). No undocumented provider endpoint/idempotency header was invented.

## CHANGES ALREADY APPLIED LOCALLY

The exact source list is in `PHASE_2_CHANGED_FILES.md`, compared with the preserved Phase 1 local baseline. Applied SQL bundles and generated/ignored build evidence are distinguished there. Phase 1 migrations were not edited. Existing unrelated local changes were preserved.

`PHASE 2 STATUS: NEEDS ACTION`
