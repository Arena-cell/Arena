# ARENA FIREBASE FINAL ACCEPTANCE REPORT

Verification date: 10 October 2026. Environment: Supabase `gtcrijikfaglqcwqozel` and Firebase `arena-staging-ae20f` only.

## 1. Final state

Server delivery and regression checks passed. Complete native acceptance remains PARTIAL: the Android emulator currently displays Arena but does not respond to app taps or the emulator Home control; ADB diagnostic requests also remain pending. No physical Android or iPhone acceptance was performed. FCM acceptance is not evidence of device display or correct navigation.

## 2. Previously successful work preserved

Existing Firebase project, four registered apps, FlutterFire configuration, encrypted server credentials, Vault scheduler secret, authenticated workers, notification inbox/queue, and scheduling were retained. Earlier user-confirmed User background delivery opened the correct booking. Earlier Owner delivery opened the app after its intent-filter repair; that confirmation alone does not prove the correct booking details.

## 3. Proven issues

The installed User Android application did not resolve `FLUTTER_NOTIFICATION_CLICK`. Both iOS Xcode projects omitted their existing GoogleService-Info.plist files from the resource graph. Owner lacked a push entitlement. Both iOS background modes omitted fetch. These are configuration findings, not proof of APNs delivery.

## 4. Minimal repairs

Added User notification-click intent filter; rebuilt and installed the Staging APK, then verified activity resolution to MainActivity. Added official existing Firebase plist resources to both Xcode projects. Added Owner aps-environment entitlement and build settings. Added iOS background fetch alongside remote-notification. Added native configuration regression tests. No notification service refactoring or business-rule changes.

## 5. Files changed in this cycle

- User: `android/app/src/main/AndroidManifest.xml`.
- User: `ios/Runner/Info.plist`.
- User: `ios/Runner.xcodeproj/project.pbxproj`.
- User: new `supabase/tests/firebase_native_config.test.mjs`.
- Owner: `ios/Runner/Info.plist`.
- Owner: `ios/Runner.xcodeproj/project.pbxproj`.
- Owner: new `ios/Runner/Runner.entitlements`.
- User: this report.

Generated Android build/cache files changed during builds. They are not application-source changes. Admin source and previously applied migrations were not changed. Earlier uncommitted changes remain preserved. Before/after Git evidence and source hashes are in ignored `build/firebase-final-evidence`; private session/worker files there must not be committed or shared.

## 6. Fresh test results

| Check | Result | Scope |
|---|---|---|
| User analyze / Flutter tests | PASS / 23 passed | Local |
| Owner analyze / Flutter tests | PASS / 2 passed | Local |
| User / Owner Android debug builds | PASS | Explicit Staging configuration, JDK 17 |
| Admin build / available lint | PASS | Staging build; existing lint scope |
| Phase 1 PostgreSQL | 30 passed | Isolated local PostgreSQL |
| Phase 2 PostgreSQL | 41 passed | Isolated local PostgreSQL |
| Phase 3 PostgreSQL | 72 passed | Isolated local PostgreSQL |
| Refund policy PostgreSQL | 38 passed | Isolated local PostgreSQL |
| Host cancellation PostgreSQL | 33 passed | Isolated local PostgreSQL |
| Firebase PostgreSQL | 12 passed | Isolated local PostgreSQL |
| Edge tests | 7 passed | Local, provider fakes where applicable |
| Thawani tests | 7 passed | Local provider fakes only |
| Native configuration tests | 4 passed | Static regression; not Xcode compilation |
| Hosted account isolation / worker authentication | 10 passed | Real Staging sessions |
| Known secret/private-key scan in nonignored source | PASS, zero findings | Source scan, not a blanket log certification |

SQL total: 226 passed. Logs are retained in `build/firebase-final-evidence`. Local race/RLS/refund tests do not substitute for real provider or device testing.

## 7. User Android

Previous real background notification and correct booking navigation: user confirmed. Current repair: installed activity resolution passed. A genuine cash booking and its cancellation each produced an inbox event and Firebase accepted one delivery. Foreground Snackbar was not visibly observed; do not count that as PASS. Current emulator responsiveness prevents reliable additional foreground/background/terminated navigation, burst, and restart acceptance. Match and financial detail navigation have not received complete native acceptance in this cycle.

## 8. Owner Android

Previous real notification reception and app opening were user confirmed. Owner click intent filter remains present; fresh debug build passed. Correct booking/match/multiple-arena detail navigation and all lifecycle variants remain unverified. Merely opening the app is insufficient. Existing server Owner notification text includes the actual public arena name; locale determines the language.

## 9. iOS

Configuration defects were repaired locally without changing Bundle IDs. User remains `com.example.playon`; Owner remains `com.playon.arenaOwner`. No macOS/Xcode compile, provisioning, APNs token, background/terminated delivery, or physical iPhone test occurred. Follow [official Firebase Flutter FCM setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started): enable capabilities with valid provisioning and upload an APNs authentication key with its Key ID and Team ID in Firebase Cloud Messaging settings. Do not commit APNs credentials. The sample User identifier remains unsuitable as an automatically approved publishing identifier; it was not changed.

## 10. Account and notification protection

Two genuine Staging user sessions could not read other users' device tokens or inbox notifications; forged inbox inserts were denied. Worker and scheduler rejected absent and incorrect credentials with HTTP 401. Authorized calls succeeded. Local SQL covers token ownership and safe worker behavior, including invalid-token/retry handling; this is not a real expired FCM-token acceptance test. Logout/login/token rotation/account switching, Owner A versus Owner B device delivery, and a second device remain untested end-to-end. No Service Role or Firebase service-account secret was added to Flutter/Admin.

## 11. Scheduler and FCM

Hosted scheduling remained active: decision/reminder processing every five seconds and dispatch every thirty seconds. The sampled ten-minute history contained 139 successful jobs. Vault secret existence was checked without displaying its value. Authorized repeated dispatch skipped an already processed event. New genuine booking confirmation and cancellation each returned `sent=1`, `failed=0`; this means provider acceptance only. No JWT, credential, Vault, schedule, or cloud-project changes were made in this cycle.

Coverage distinction: booking confirmation/cancellation reached real inbox/queue/worker/Firebase. Device delivery has earlier user evidence, but complete fresh native coverage is pending. Reminder catch-up, match joins/withdrawals/90–80 decisions/cancellation, duplicate events, retry, and financial notifications passed their isolated regression tests; their complete real Android end-to-end event matrix is not established. Real Thawani payment/refund events remain PENDING.

## 12. Test data and historical records

Existing 10 October 2036 bookings:

| Booking ID | Oman time | State |
|---|---|---|
| a91bc25d-8168-40c7-ba78-beff21e31cca | 10:00–11:00 | Upcoming, cash, unpaid |
| a2691da7-01cd-4643-b290-807b05c5470b | 11:00–12:00 | Upcoming, cash, unpaid |
| 0dd94c9f-785a-4a80-8764-62e1fb617e00 | 12:00–13:00 | Upcoming, cash, unpaid |

These test bookings occupy Staging Court 1 availability. Each has zero add-ons/refunds and two notification relationships. None was deleted or cancelled in this cycle. Safe cleanup requires reviewing associated orders, allocations, notifications and any newly attached relationships, recording a backup, then obtaining approval before invoking normal cancellation; no bulk direct deletion.

New dedicated cancellation fixture: `733c0747-928f-4218-99da-46c99e2525e8`, 11 October 2036, 10:00–11:00 Oman. Created through the normal authenticated cash checkout with no add-ons, then cancelled through the normal cancellation RPC solely for lifecycle testing. No electronic money was collected or refunded. This is separate from historical cleanup.

The four previously audited historical add-on rows were read for fingerprints and were not modified. No stock or fulfillment assumptions were applied to them.

## 13. Remaining risks and incomplete checks

Native emulator freeze blocks reliable remaining acceptance. Foreground display is unresolved rather than declared successful. Full token lifecycle/isolation across account switches and devices remains pending. No real financial-provider success, refund, APNs, or physical-device result is claimed. iOS static checks do not establish signing or runtime readiness.

## 14. Personal intervention required

1. Restore the existing Android emulator to a responsive state, without wiping its data. Then continue both applications' lifecycle/tap/burst and inbox acceptance.
2. Authentication screens require the account holder to log in; after the emulator is responsive, perform authorized test-account login/logout/switching when requested. Do not send passwords or secret keys.
3. Provide a physical Android device and, for iOS, macOS/Xcode, valid Apple provisioning/APNs setup and an iPhone for actual delivery acceptance.
4. Add eventual Thawani Sandbox credentials yourself in server secrets and complete real payment/refund verification. No fake financial state will be used.
5. Approve a concrete reviewed cleanup plan if the three historical Staging bookings should be cancelled. No cleanup has been executed.

## 15. Preservation and final assessment

Production was not modified. Applied migrations were not edited. No new migrations were needed. Existing 150-minute booking cancellation, 90-minute match decision/withdrawal, 80% threshold, host cancellation, availability/double-booking protection, pricing, commissions, add-on stock, Thawani contracts, permissions, application identifiers and Omani OTP configuration were preserved. Phase 4 was not started.

### Follow-up — 11 October 2026 (Muscat)

The account holder started a responsive Pixel 8a (`emulator-5556`) and logged into the authorized User test account. The prior Pixel 8 Pro diagnostic connection remained unresponsive. Installed the verified User and Owner Staging APKs on Pixel 8a successfully. An initial Firebase token synchronization error recovered after background/resume: a second active Android token row was registered for the User account. Android notification permission was confirmed granted.

A dedicated cash/no-add-on booking `280a98c4-6109-4be2-995e-7705a1e9419d` for 12 October 2036, 10:00–11:00 Oman was created and cancelled through normal authenticated RPCs. Its cancellation reached the native Firebase receiver in Android logs. Foreground banner/navigation was not visually established. Repeated worker dispatch skipped both already processed device deliveries.

A separate background cash/no-add-on fixture `0859a2e0-7490-4deb-99e8-2a78b8e2fd29` for 13 October 2036, 10:00–11:00 Oman remains an active test booking. Firebase accepted two device deliveries, but the Pixel 8a system notification was absent during observed notification-tray checks, including a delayed recheck. Do not count this as native delivery PASS. No financial success was fabricated and none of the three historical bookings was cleaned up. Review the additional active fixture in any future approved cleanup plan.

After the account holder authenticated Owner on Pixel 8a, real foreground reception was recorded by its Firebase receiver. A new cash/no-add-on fixture `07625eda-89e1-42f8-8811-d8098e085947`, 14 October 2036, 10:00–11:00 Oman, was created and cancelled through normal authenticated operations. Owner was backgrounded before cancellation. The system notification appeared; clicking it opened Booking details showing Staging Two Courts, cancelled status, the correct 14 October date and 10:00–11:00 interval. Owner background delivery and correct cancelled-booking routing: PASS on this emulator.

The User notification group contained three distinct real events, including the latest cancellation. Clicking the latest launched User through its startup/splash sequence, then opened My bookings directly to the cancelled Staging Two Courts booking for 14 October 2036, 10:00–11:00, Court 1, 10.000 OMR. User system delivery and correct cancelled-booking routing: PASS. Startup took approximately one minute on this emulator; blank/startup frames alone were not classified as navigation success. Process termination at tap time was not independently established, so this is not a proven terminated-lifecycle PASS. The earlier missing tray notification therefore does not establish a persistent delivery failure: later genuine notifications were visibly received, while exact latency for the earlier event remains unmeasured.

Native acceptance remains PARTIAL overall: foreground banner/action, deliberate termination, match navigation, full account-switch/token-rotation isolation and physical-device coverage are incomplete. No application code changed in this follow-up; no completed regression checks were rerun unnecessarily.

- FIREBASE SERVER: PASS
- USER ANDROID EMULATOR: PARTIAL
- OWNER ANDROID EMULATOR: PARTIAL
- ANDROID PHYSICAL DEVICE: NOT TESTED
- IOS PHYSICAL DEVICE: NOT TESTED
- SECURITY & TOKEN ISOLATION: PARTIAL
- PHASE 1–3 REGRESSION: PASS
- THAWANI REAL PAYMENT/REFUND: PENDING
- OVERALL FIREBASE READINESS: PARTIAL
