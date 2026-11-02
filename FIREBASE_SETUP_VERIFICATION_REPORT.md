# FIREBASE SETUP VERIFICATION REPORT

Checkpoint: 10 October 2026 (server setup verified 9 October). Staging only. Server configuration and hosted scheduling are verified; setup remains **NEEDS ACTION** until native delivery tests are completed.

## 1. Existing project and account

The signed-in Google account (`m***@gmail.com`, display A R) initially showed no accessible Firebase or Google Cloud projects. This does not exclude projects under other accounts. With explicit user approval, **Arena Staging / arena-staging-ae20f / 969230719482** was created on Spark. Optional Analytics, Gemini and Developer Program enrollment were disabled at creation. No paid billing was activated.

Firebase CLI authorization succeeded after explicit approval of Firebase and Google Cloud scopes; authenticated app inventory succeeded. Firebase CLI 15.33.0 is installed outside app source at `C:/Users/Dell/.codex/tools/arena-firebase-cli/`. FlutterFire CLI 1.4.1 is installed in the Dart pub cache. No permanent PATH change was required. Some Firebase CLI commands encounter a Windows Node exit assertion after completing; cloud state and resulting files were checked separately.

## 2. Registered applications

| App | Platform | Unchanged identifier | Firebase app ID |
|---|---|---|---|
| User | Android | com.example.playon | 1:969230719482:android:a6dd119be73db87a8d2c43 |
| Owner | Android | com.playon.arena_owner | 1:969230719482:android:f1af24d8972416598d2c43 |
| User | iOS | com.example.playon | 1:969230719482:ios:c1bd42e9df481ef08d2c43 |
| Owner | iOS | com.playon.arenaOwner | 1:969230719482:ios:b64a3ecf38d0c5138d2c43 |

All four belong to the verified Staging project. No duplicate registrations were created. Existing identifiers were not changed. `com.example.playon` is not accepted as a final publishing ID. Proposed permanent IDs: `om.playon.arena` and `om.playon.arena.owner`, subject to namespace ownership and explicit approval before any change.

## 3. Configuration completed

In both User and Owner projects, FlutterFire configured Android/iOS and generated/downloaded official `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`, `lib/firebase_options.dart` and `firebase.json`. JSON/plist files remain ignored. These client configurations contain public application metadata, not service-account credentials. Android JSON includes both project clients; Google Services selects the actual application ID.

Updated only Firebase initialization in User `lib/core/services/push_notification_service.dart` and Owner `lib/core/owner_push_service.dart`: foreground/background initialization now passes generated DefaultFirebaseOptions. Existing native-only platform guards remain. Native identifiers, payment/booking rules and applied migrations were preserved.

## 4. Server identity and secrets

Created dedicated **arena-push-staging@arena-staging-ae20f.iam.gserviceaccount.com**. Created custom role **projects/arena-staging-ae20f/roles/arenaFcmSender**, with exactly **cloudmessaging.messages.create**, and assigned it to this account. No general Firebase/Google Cloud administrator role was assigned to this sender.

With explicit approval, created its server key and saved it as **FIREBASE_SERVICE_ACCOUNT_JSON** in Supabase **arena-staging / gtcrijikfaglqcwqozel** Edge Function Secrets. Created strong independent **ARENA_SCHEDULER_SECRET** and **PUSH_DISPATCH_SECRET** there. Dashboard confirmed all three secret names. No existing custom secret was replaced. No secret was placed in Flutter, Admin frontend or Git. The temporary local service-account key was removed after confirmed secret installation. Worker secrets remain temporarily in ignored local build/firebase-evidence for pending device verification; no credential is tracked.

Real Google OAuth exchange using the dedicated service-account key: **PASS**. FCM HTTP v1 validation-only request reached payload validation and returned HTTP 400 INVALID_ARGUMENT for an intentionally invalid test token, rather than an authorization failure. This checks credentials/permission but is **not** a delivery test; no fake device token was registered in Supabase and no notification was sent by this check.

References: [FCM IAM permissions](https://docs.cloud.google.com/iam/docs/roles-permissions/firebasecloudmessaging), [service-account key creation](https://docs.cloud.google.com/iam/docs/reference/rest/v1/projects.serviceAccounts.keys/create), [Flutter setup](https://firebase.google.com/docs/flutter/setup).

## 5. Supabase pending activation

With explicit approval, disabled legacy JWT verification only for push-notifications and arena-scheduler; their server-secret handler authentication remains mandatory. Hosted missing/wrong secrets returned 401 UNAUTHORIZED for both. Correct push secret reached request validation (400 INVALID_NOTIFICATION_ID for an empty request); correct Scheduler secret returned HTTP 200 and processed three queue items. No device tokens existed, so this is not a send/delivery test.

Created Vault arena_scheduler_secret using the same Scheduler secret without replacing any existing secret. Applied the existing optional Staging activation script (no migration modified). arena-phase3-push-dispatch runs every 30 seconds. Database verification recorded active=true, Vault present=true, six successful cron runs and six HTTP 200 responses, device_tokens=0. Independent existing decision/reminder jobs were preserved.

## 6. Test results

| Check | Result |
|---|---|
| Authenticated Firebase project/app inventory | PASS |
| Four native application registrations | PASS |
| Official config project/package/app matching | PASS |
| User flutter analyze | PASS — no issues |
| User flutter test | PASS — 23 |
| Owner flutter analyze | PASS — no issues |
| Owner flutter test | PASS — 2 |
| Service-account Google OAuth | PASS |
| FCM validation-only authenticated request | PASS — validation reached; no delivery |
| Supabase three server secret names | PASS |
| Authorized hosted worker/scheduler | PASS — missing/wrong secrets rejected; correct Scheduler HTTP 200 |
| Vault/push schedule activation | PASS — six successful scheduled invocations / HTTP 200 |
| User Android debug build | PASS — APK built |
| Owner Android debug build | PASS — final APK built after Kotlin 2.1.21 / NDK 27.0.12077973 compatibility fixes |
| Real native Firebase initialization/token registration | PASS — User Android emulator; Owner pending |
| User background delivery / booking tap navigation | PASS — Android emulator, user confirmed |
| Native User/Owner token isolation / Owner delivery | NOT TESTED |
| Android physical-device delivery | NOT TESTED |
| iOS delivery | NOT TESTED |

Initial User analyze accidentally scanned Dart templates inside the locally installed Firebase CLI. Moving the CLI out of the app resolved this without suppressing application analysis. Prior SQL/Edge/Admin regression results are in PHASE_3_FIREBASE_PUSH_REPORT.md (226 local PostgreSQL checks; 7 Deno tests; Admin build/lint PASS). They are prior results and are not evidence of real FCM delivery.

## 7. Device availability and limitations

No physical Android/iOS device was connected. Pixel_8_Pro and Pixel_8a Google Play emulator images exist. Automatic background emulator launch was rejected by the tool policy; it was not retried through another execution mechanism. User background delivery and booking tap navigation subsequently passed on the emulator; remaining native tests are listed below. User Android debug build passed. Owner required Kotlin Gradle plugin 2.1.21 because Firebase Core 4.15 uses compilerOptions; its final rebuild passed on 10 October with Android NDK 27.0.12077973. User native runtime and background delivery passed on the subsequently connected emulator; Owner native acceptance remains pending.

iOS configuration files exist; Xcode resource inclusion, Push Notifications entitlement, APNs provisioning/certificate or key, Apple Developer access and iPhone verification remain unverified on this Windows host. These require macOS/Apple tooling.

## 8. Required actions

1. Worker authentication approval received and implementation verified. No manual server-secret entry remains.
2. Emulator is now available and User background push/tap passed. Complete Owner native sign-in and acceptance, remaining foreground/terminated and isolation checks; provide a physical Android device for physical-device proof.
3. iOS acceptance requires macOS/Xcode, Apple Developer provisioning/APNs and an iPhone. Server APNs credentials must not enter Git/frontend.

No further Firebase project creation or duplicate app registration is required. No application ID change is required for current Staging testing.

## 9. Protection and readiness

Only Firebase setup/notification configuration was changed. No Production changes, no booking/payment/refund policy changes, no 150-minute/90-minute/80% changes, no applied migration edits, no Phase 4.

**FIREBASE SETUP: NEEDS ACTION**

**USER ANDROID EMULATOR BACKGROUND PUSH: PASS; PHYSICAL ANDROID: NOT TESTED**

**IOS PUSH: NOT TESTED**
## Latest device checkpoint — 10 October 2026

User reported starting the emulator. Subsequent Flutter devices, Android SDK adb devices and emulator process checks still showed no connected Android device and no running emulator process. Asked the user to confirm the actual Android screen or provide the launch error; no successful initialization/token/delivery is inferred. Both User and Owner debug APK builds now pass. Owner changes additionally include android/settings.gradle.kts (Kotlin 2.1.21) and android/app/build.gradle.kts (NDK 27.0.12077973), scoped to Firebase/native build compatibility. Final build log: build/firebase-evidence/owner-android-build-final.log.

## Emulator connected — 10 October 2026

Flutter and Android SDK now detect emulator-5554 (sdk gphone16k x86 64 / Android 17 API 37). User Staging debug APK installed successfully and launched, current process 12585. Supabase initialization logged successfully. Current-process logs show no Firebase initialization/token sync/write errors; an earlier PlatformException belonged to old process 9855 and is excluded from this result. This absence of errors is not a token/delivery PASS. Requested the user to grant notifications and sign in within the emulator because native GUI control is unavailable. FCM token registration, actual push acceptance/delivery and tap navigation remain pending. Emulator results will not be represented as physical-device delivery proof.

## Staging Test OTP renewed — 10 October 2026

Phone provider was already enabled. Existing test-phone expiry was 5 October 2026, blocking emulator sign-in. With explicit user approval, changed only Test OTPs Valid Until to 17 October 2026; original test numbers/codes unchanged. Reopened Dashboard and verified selected date. Real Auth OTP request HTTP 200 and SMS verification HTTP 200 with a genuine Supabase session/user; no tokens printed or fake session used. User still needs to sign in within the emulator for native token registration. Production unchanged.

## Real Android FCM acceptance — 10 October 2026

After emulator sign-in, own-user authenticated RLS read confirmed one active Android device token (metadata only; token not printed). Android package diagnostics confirmed POST_NOTIFICATIONS granted. Created genuine Staging cash booking a91bc25d-8168-40c7-ba78-beff21e31cca, order cf10338e-588d-4da3-be5d-c9cde31f5f26, 10 October 2036 10:00–11:00 Oman, using create_checkout with a persisted idempotency key. payment_method=cash and payment_status=unpaid. Real booking_confirmation notification e1a7bf4e-fda8-4cb0-a1d1-30f346ea9259 was created by server events.

Scheduled dispatch produced delivery status sent, attempt_count=1, last_error_code=NULL, genuine provider_message_id under projects/arena-staging-ae20f/messages/. Two duplicate worker invocations returned skipped=1, sent=0, failed=0, confirming no extra send from those requests. User RLS delivery read returned no rows; privileged Dashboard metadata verified the result without weakening RLS. Notification-system diagnostics had no active matching notification record at inspection time. Asked the user to verify actual OS display and tap navigation; those checks remain pending and FCM acceptance is not reported as device delivery.

**Firebase initialization/token registration on Android emulator: PASS**
**Real FCM server acceptance: PASS**
**Duplicate server send prevention for tested event: PASS**
**OS display/tap navigation: PENDING USER VERIFICATION**
**Physical Android/iOS delivery: NOT TESTED**

## User-confirmed emulator delivery and navigation — 10 October 2026

The user explicitly confirmed that the Arena notification appeared in the Android emulator notification tray and tapping it opened the correct test booking (10 October 2036, 10:00–11:00 Oman). Evidence combines authenticated Android token metadata, granted notification permission, real server booking event, one FCM-accepted delivery with provider reference, duplicate requests skipped, and user-confirmed OS display/navigation. Background Android emulator delivery and booking tap navigation: **PASS**. This is not a physical Android-device or iOS acceptance test. Foreground/terminated delivery, token rotation/logout, native User/Owner token isolation and Owner native delivery still require their own acceptance checks. The cash test booking remains preserved as an unpaid historical test fixture; no payment/refund success was fabricated.

**USER ANDROID EMULATOR BACKGROUND PUSH / BOOKING TAP: PASS**
**PHYSICAL ANDROID PUSH: NOT TESTED**
**OWNER ANDROID EMULATOR BACKGROUND PUSH / TAP: PASS — user confirmed after fix**
**IOS PUSH: NOT TESTED**
**FIREBASE SETUP: NEEDS ACTION — remaining native acceptance checks**

## Owner native checkpoint — 10 October 2026

Installed and launched the existing Staging Owner APK on emulator-5554. Requested native Owner sign-in and notification permission; authentication/token/delivery are not inferred from installation. No additional cloud or booking changes at this checkpoint.


## Owner native registration verified — 10 October 2026

Owner Android process running; Supabase initialization completed. Staging database metadata confirms active Android token for Owner eac4c6b3-dc0f-42ab-a9e0-a4e8dc03fa34, updated 12:05:27 UTC, and separate User token remains active. Tokens were not displayed. Owner Firebase initialization/token registration PASS; cross-account RLS isolation and actual Owner delivery/navigation remain pending. Requested Home/background for actual delivery acceptance.


## Owner real FCM acceptance — 10 October 2026

Existing real owner booking_confirmation 2bee3797-1ac3-4420-aeaf-b9f3b38089fa targets booking a91bc25d-8168-40c7-ba78-beff21e31cca (10 October 2036, 10:00–11:00 Oman). Hosted delivery metadata: sent, attempt_count=1, last_error_code=NULL; genuine Firebase provider message reference. A subsequent authenticated dispatch returned HTTP 200, sent=0/failed=0/skipped=1; no duplicate push was sent. The original delivery occurred after Owner token registration, before this background checkpoint, so background delivery is not inferred. Requested user confirmation of Owner OS display and correct booking tap. No new booking, synthetic notification or financial state was created.


## Owner background OS notification verified
User reported previous notification absent; previous delivery had occurred during foreground. Permission granted and channel importance=4, not blocked. Created new genuine unpaid cash booking a2691da7-01cd-4643-b290-807b05c5470b, 10 October 2036 11:00–12:00 Oman, persisted idempotency key. New Owner event 57bc7fd9-44d8-4680-92ab-b409faf7d95d produced an active Android NotificationRecord under com.playon.arena_owner with matching event tag. OS notification presence PASS; tap/navigation pending user confirmation. Duplicate dispatch skipped. No financial success fabricated.


## Owner tap issue and clearer booking alert
User confirmed Owner OS notification arrived but tap dismissed without opening. Found FLUTTER_NOTIFICATION_CLICK in server payload with no corresponding Owner Activity intent filter; added DEFAULT action filter to Owner AndroidManifest.xml. Native retest pending rebuilt APK. Owner booking_confirmation payload now resolves public arena name server-side and says New booking at / تم إضافة حجز جديد لملعب; customer identity, booking time and financial details remain excluded. Handler deployed on Staging only. Deno check PASS; provider fake test PASS, expanded to owner arena-name case alongside success/token/error/privacy checks. No migration, auth permission or financial policy change. Screenshot: build/firebase-evidence/owner-push-text-deployed.png.


Owner fixed Staging APK build PASS (Java 17, explicit Staging Dart defines), installed on emulator. Android resolve-activity for FLUTTER_NOTIFICATION_CLICK now resolves com.playon.arena_owner/.MainActivity: PASS. Actual tap retest still pending. No Production binary was installed. Build log owner-tap-gradle-staging.log; launch owner-tap-fixed-launch.log.


## Fixed Owner native retest event
Created genuine unpaid cash booking 0dd94c9f-785a-4a80-8764-62e1fb617e00, 10 October 2036 12:00–13:00 Oman using persisted idempotency key in owner-tap-fixture.local.json. Owner notification 76ced62a-79a6-4b5b-aaaa-ec200d01366d: sent, attempt_count=1, no error; Android active NotificationRecord matching package and event confirmed on updated APK. Awaiting user tap/navigation and visible-text confirmation; not claiming those PASS yet.


## Owner tap acceptance confirmed — 10 October 2026

User explicitly replied that tapping the new Owner notification opened successfully after installation of the fixed APK. Combined with matching Android active notification record and server delivery sent once, Owner Android emulator background delivery and tap opening: PASS. Exact booking-detail identity and visible arena-name text were not separately confirmed in this reply; do not infer additional acceptance. The public arena-name message is implemented/deployed and provider fake tested. Physical Android, iOS, foreground/terminated acceptance and native cross-account RLS/logout isolation remain pending. Overall FIREBASE SETUP: NEEDS ACTION for remaining acceptance/dependencies. No Production changes.

