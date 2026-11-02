# ARENA — PHASE 3 FIREBASE PUSH REPORT

Verified 9 October 2026. Supabase **arena-staging / gtcrijikfaglqcwqozel** only.
Production was not accessed or modified. Phase 4 was not started.

## 1. Previously implemented infrastructure

Reviewed Phase 1 implementation/Staging verification, Phase 2 implementation/changed-files, Phase 3 implementation/changed-files, refund-policy and final-completion reports; current token client, notification triggers, queue leases, scheduler, worker and financial event tests.

Reused `notifications` inbox, unread/read state, event keys, `device_tokens`, `notification_push_deliveries`, existing decision/reminder database scheduler, `arena-scheduler`, and HTTP v1 `push-notifications`. No parallel inbox, queue, payment or refund system was created.

Existing queue supports due dates, attempts, leases, recovery and capped exponential backoff. Database decisions/reminders work independently of FCM. Existing real-state triggers cover booking, match participation/decision, verified payment and refund events. No notification preference table or app-level push switch was found; device OS notification permission is the current permission control. No new preference policy was invented.

Preflight on Staging: 33 pending notifications, 11 historical notifications, zero device tokens, zero active push-dispatch jobs, zero `arena_scheduler_secret` Vault entries and zero unresolved inventory conflicts. Dashboard showed **No custom secrets created**. Firebase project existence could not be established from these repositories; no project ID or credentials were invented.

## 2. Added and repaired

- Owner now initializes Firebase on supported mobile platforms, requests permission, registers tokens on sign-in/refresh/resume, and handles foreground/background/terminated entry paths.
- Both apps reactivate registered tokens (`is_active=true`), handle missing APNs tokens safely, retry token synchronization on resume, and contain token lookup failures.
- Logout removes the current user's device record and rotates its FCM token. Other devices remain registered. Native/offline logout behavior still requires device acceptance; network failure is logged without exposing token values.
- Foreground notifications use an in-app banner. iOS automatic foreground alert is disabled to avoid a second visible alert; repeated foreground IDs are suppressed in the current process.
- Both Android applications create the `arena_updates` high-importance channel. Owner now declares Internet/Android 13 notification permission. Server payload selects this channel and uses a stable notification tag.
- Owner tap resolves the authenticated user's real inbox row under RLS, rechecks current arena assignment, resolves booking/match/order from the database, and opens the actual booking or filtered match view. Untrusted push targets are not authorization. Owner navigation errors are contained.
- New additive inbox trigger fans out relevant existing booking/match/verified finance events to owners with current arena permissions. Disabled staff restrictions are reused; recursive fanout is prevented; event keys deduplicate per owner. It does not mutate booking, inventory, pricing or financial records.
- Worker persists Firebase success only after a successful HTTP response with a provider message ID. Database save/deactivation errors now fail visibly to the scheduler instead of being ignored. `UNREGISTERED` deactivates the token; payload `INVALID_ARGUMENT` does not indiscriminately delete tokens.

`sent` means **Firebase accepted the request**, never proof of delivery, reading or user attention. Duplicate event keys/per-device claims prevent ordinary repeated sends. An ambiguous provider/network acknowledgment can still cause a retry; FCM transport is not an exactly-once system. Android stable tags and foreground ID suppression reduce repeated display. Native retry/display acceptance is pending.

## 3. Exact application identities and configuration

| App | Android Application ID | iOS Bundle ID |
|---|---|---|
| User | `com.example.playon` | `com.example.playon` |
| Owner | `com.playon.arena_owner` | `com.playon.arenaOwner` |

Identifiers were preserved. Both apps now depend on `firebase_core` and `firebase_messaging`. Android Google Services plugin applies only when the real config file exists. Neither app currently has `google-services.json` or `GoogleService-Info.plist`. APNs credentials/provisioning are not established.

### Files changed in this request

User project `C:/monther/MN/my_apps/playon/`:

- `.gitignore` — ignore local Firebase configuration/service-account JSON.
- `lib/core/services/push_notification_service.dart` — lifecycle/reactivation/foreground fixes.
- `android/app/src/main/AndroidManifest.xml` — default notification channel.
- `android/app/src/main/kotlin/com/example/playon/MainActivity.kt` — channel creation.
- `supabase/functions/push-notifications/handler.ts` — channel/tag and checked database writes.
- `supabase/migrations/202610090105_phase3_firebase_owner_events.sql` — new owner fanout trigger.
- `supabase/tests/run_firebase_push.cjs` — new token/privacy/owner-event SQL tests.
- `supabase/tests/phase3_push_fake_test.ts` — accepted/failure/retry/channel/privacy simulations, tests only.
- `supabase/tests/phase3_financial_cases.cjs` — financial notification assertions now check the original payer, allowing the additional legitimate owner recipient.
- `PHASE_3_FIREBASE_PUSH_REPORT.md` — this report.

Owner project `C:/monther/MN/my_apps/arena_owner/`:

- `.gitignore` — Firebase local-file exclusion.
- `pubspec.yaml`, `pubspec.lock` — Firebase dependencies.
- `lib/core/owner_push_service.dart` — new Owner client service using existing inbox/tokens.
- `lib/main.dart` — navigator, initialization, authenticated navigation activation, logout cleanup.
- `lib/match_operations.dart` — optional exact match filter for notification entry.
- `android/settings.gradle.kts` — Google Services plugin declaration.
- `android/app/build.gradle.kts` — conditional configuration/minimum Android SDK 23.
- `android/app/src/main/AndroidManifest.xml` — Internet, notification permission/channel.
- `android/app/src/main/kotlin/com/playon/arena_owner/MainActivity.kt` — channel creation.
- `ios/Runner/Info.plist` — remote-notification background mode.
- Flutter-generated platform registration files may be regenerated by dependency resolution; these are generated artifacts, not credentials.

Admin source was not modified. Existing delivery monitoring/safe retry UI is reused.

## 4. Database and Staging verification

Migration `202610090105_phase3_firebase_owner_events.sql` applied once to confirmed Staging, SHA256:

`da385dfa7b106e929b4a9fa954d1f5336a703450a94f3079dc118568f8da1d29`

Guarded installer requires the exact applied 104 receipt, rejects repeat installation and unresolved inventory conflicts. Backup `arena_private.firebase_backup_20261009` contains six existing notification/worker function definitions; access revoked from public/anon/authenticated. This is an in-project recovery snapshot, not an off-site database backup.

Hosted rollback-only verification proved: one owner event after duplicate enqueue, no outsider owner event, device-token RLS enabled, users cannot execute worker claims or insert forged notifications. Verification events were rolled back. Paid orders/refunds remained zero; inventory conflicts remained zero. No historical add-ons were corrected or changed.

Updated `push-notifications` deployed through the Staging Dashboard. Gateway JWT verification remains **ON**; no shared-secret schedule activated without configuration. Actual unauthenticated POST to both hosted worker/scheduler returned **401**.

Ignored local evidence: `build/firebase-evidence/` (preflight, guarded installer, rollback verification, generated deployment source, screenshots). Do not replay the installation SQL; use the recorded receipt.

## 5. Test results

| Check | Result and scope |
|---|---|
| Phase 1 PostgreSQL/RLS/concurrency | PASS — 30 checks |
| Phase 2 pricing/inventory/payment regression | PASS — 41 checks, local provider fakes only |
| Phase 3 decisions/scheduler/queue regression | PASS — 72 checks |
| Cancellation/refund policy regression | PASS — 38 checks |
| Host cancellation regression | PASS — 33 checks |
| New Firebase token/privacy/owner SQL | PASS — 12 checks |
| Edge security/provider simulations | PASS — 7 Deno tests; FCM scenarios include accepted, unregistered, invalid payload and delayed retry |
| Actual Staging host-policy regression | PASS — 6 checks; no real financial capture/refund |
| Hosted owner fanout/RLS verification | PASS — rollback-only transaction |
| Hosted unauthorized worker/scheduler | PASS — 401 for both |
| User `flutter analyze` / `flutter test` | PASS — no issues / 23 tests |
| Owner `flutter analyze` / `flutter test` | PASS — no issues / 2 tests |
| Admin build/lint | PASS — explicitly configured for Staging |
| Real FCM token registration/refresh/logout | NOT TESTED — no configured native app/device |
| Real foreground/background/terminated delivery and tap | NOT TESTED — Android/iOS |
| APNs/iOS provisioning | NOT TESTED — Windows host, no connected iPhone |
| Real provider payment/refund push | NOT TESTED — Thawani credentials unavailable |

Total local PostgreSQL checks: **226**. Earlier applied migration hashes remain unchanged, including 103/104. Ordinary cancellation **150 minutes**, match decision/withdrawal **90 minutes**, integer **80%**, Court allocation/double-booking protection and financial authorization were not modified.

## 6. Firebase manual configuration

1. Open [Firebase Console](https://console.firebase.google.com/). Select the existing Arena project if available; otherwise create a project intended for Staging. Do not accidentally attach Production Firebase credentials.
2. Project settings → General → Your apps → Add app → Android. Register **each exact Android ID above**. Download its own `google-services.json` into the corresponding `android/app/` directory. Never swap User and Owner files. Rebuild both apps.
3. Add each iOS app using the exact Bundle ID above. Place each downloaded `GoogleService-Info.plist` in its app's `ios/Runner/`. On macOS, add it in Xcode with Runner target membership. Enable Push Notifications capability and Background Modes → Remote notifications for Runner. Use actual Apple signing/provisioning; no fake team ID/entitlement was created here.
4. Firebase Project settings → Cloud Messaging → ensure HTTP v1 API is enabled. Under each iOS app, upload your APNs authentication key with its real Key ID/Apple Team ID. Do this yourself; do not send APNs secrets in chat.
5. Firebase Project settings → Service accounts → generate a private JSON key for the intended project, or use a dedicated account with messaging permission. Keep it outside the repositories. Add its JSON yourself as the server secret below. Never place it in either Flutter app or Admin.

Official references: [Flutter setup](https://firebase.google.com/docs/flutter/setup), [FCM platform/APNs setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started), [message lifecycle](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages), [HTTP v1 server authentication](https://firebase.google.com/docs/cloud-messaging/send/v1-api).

## 7. Supabase Secrets and safe activation

In **arena-staging / gtcrijikfaglqcwqozel → Edge Functions → Secrets**, add yourself:

| Secret | Value/location |
|---|---|
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Real Firebase service-account JSON; server only |
| `ARENA_SCHEDULER_SECRET` | Strong independently generated secret; server only |
| `PUSH_DISPATCH_SECRET` | Different strong independently generated secret; server only |

In Supabase Staging **Vault**, create `arena_scheduler_secret` with exactly the same value as `ARENA_SCHEDULER_SECRET`. Do not paste its value into SQL snippets, Git or chat. Existing built-in server Supabase keys stay server side; do not copy them into Flutter/Admin.

After secrets and a real device are ready, verify the custom handlers reject missing/wrong shared secrets and accept authorized server invocation. Only then review the deliberate gateway transition for `arena-scheduler` and `push-notifications`; the supplied custom authentication replaces gateway JWT for server scheduling. This transition was **not performed**. Do not simply disable JWT now.

Then review/run `supabase/staging/phase3_activate_push_after_secrets.sql` only on this Staging project. It guards Vault configuration and activates the existing 30-second dispatch job. Preserve the independent database decision/reminder cron. Confirm authorized dispatch, token registration and Firebase message IDs before reporting active delivery.

No secret values were read, printed, generated as fake credentials, or committed.

## 8. Actual-device acceptance still required

Current `flutter devices` lists Windows/Chrome/Edge only; no Android/iPhone. Connect an Android device with Google Play Services, run each app with explicit Staging URL/key/environment, and grant notification permission. Validate own-token registration, refresh, multiple devices and logout/account switching. Trigger a genuine nonfinancial Staging booking/match event and verify correct user/owner receipt, unchanged outsider inbox, server message ID, foreground banner, background/terminated notification, and authorized correct target after tapping.

Repeat on macOS/iPhone after APNs setup. Check expired token handling and a controlled temporary transport failure/retry. Queue insertion, web inbox display and transport fakes are not native delivery evidence. Never manufacture payment/refund success to test push; defer real financial events to verified Thawani Sandbox acceptance.

## 9. Remaining actions

- Confirm/select real Firebase Staging project and add the four app registrations/configuration files.
- Add the three Supabase server secrets and matching Vault entry privately.
- Complete the protected gateway/scheduler activation and verify authorized hosted dispatch.
- Connect native devices and execute actual lifecycle/navigation/token acceptance.
- Complete APNs/macOS setup and later real verified Thawani financial notification acceptance.

**FIREBASE IMPLEMENTATION: NEEDS ACTION**

**ANDROID PUSH: PENDING**

**IOS PUSH: PENDING**
