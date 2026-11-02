# ARENA ANDROID PHYSICAL ACCEPTANCE REPORT

Date: 11 October 2026, Muscat. Final checkpoint: PARTIAL. The observations below retain the test chronology; this acceptance matrix supersedes earlier pending statements where a later confirmation is recorded.

| Physical check | Result | Evidence / limit |
|---|---|---|
| Both Staging apps installed and running | PASS | Verified package IDs, explicit-Staging builds, successful installs, user login |
| User foreground confirmation and tap | PASS | Account B received only its confirmation and opened correct booking while requested foreground state |
| User background cancellation and tap | PASS | Account-holder confirmation for 18 October fixture |
| User terminated cancellation and cold-start tap | PASS on retest | Both no process and stopped=false verified before B cancellation; account holder confirmed receipt and correct Cancelled booking |
| Earlier User terminated confirmation | NOT RECEIVED | C event on 17 October; root cause unresolved; retained rather than erased by retest |
| Owner background cancellation and tap | PASS | 16 October fixture, name/date/time and red status explicitly confirmed |
| Owner terminated confirmation and tap | PASS | 17 October fixture; account holder answered Owner yes |
| Owner foreground notification/action | PASS | Account holder confirmed cancellation banner and correct destination for 21 October fixture |
| User logout and C → B isolation | PASS | Physical registration removed; C notification absent; B own event and correct destination confirmed |
| Owner A → Owner B switch isolation | NOT TESTED | No second physical Owner-account sequence performed |
| Match notification navigation | NOT TESTED physically | No fake paid match created; real provider-dependent match flow remains unavailable without Thawani verification |
| Phone reboot delivery | NOT TESTED | Phone was not rebooted |
| Worker auth / duplicate prevention | PASS | Post-deploy missing/wrong secrets rejected; repeated event skipped registered deliveries |
| Fresh regression checks | PASS | Analyze/tests, debug builds, 226 isolated SQL tests, expanded Edge transport test |

No physical full-matrix claim is made. Acceptance relies on account-holder device observations plus limited ADB diagnostics; no personal-device screen capture or unrelated app inspection was required.

## 1. Device

Physical Android model `23129RAA4G`, Android 14 / API 34, arm64. ADB and Flutter identified the phone; initial unauthorized state was resolved by the account holder. No personal data was intentionally collected. No reset, wipe or data clearing occurred.

## 2. Installation and startup

Neither `com.example.playon` nor `com.playon.arena_owner` was initially installed. Both APKs were verified debuggable with their existing application IDs. Both were rebuilt with explicit Supabase Staging `gtcrijikfaglqcwqozel` defines and installed successfully after the account holder resolved USB installation restrictions. Firebase project remains `arena-staging-ae20f`. User was launched; the account holder reported login to both apps.

## 3. Firebase and tokens

A new active Android device registration appeared for the authorized User test account. The real physical-phone User Firebase receiver logged receipt of the genuine booking event. No FCM token, access token, OTP or secret is included here. User notification permission is granted. Owner permission was still denied at the first verification; account-holder action is pending. No new secrets were created.

## 4. User notifications

Provider accepted the booking-confirmation dispatch for three registered devices. The physical User receiver logged receipt. Foreground banner visibility and tap navigation await the account holder's observation; provider acceptance alone is not device-display PASS.

## 5. Owner notifications

Physical display/navigation not yet verified. Notification permission must be enabled by the account holder. No device security settings were changed automatically.

## 6–7. Navigation and lifecycle

Correct booking/match screen, foreground, background, process-terminated and reboot tests: pending on the physical phone. Earlier emulator passes do not substitute for these tests. No Force Stop test is treated as ordinary termination.

## 8. Logout, switching and isolation

Physical logout/relogin, account switch, old-account delivery suppression and Owner-to-Owner isolation: pending. Existing local/hosted RLS evidence remains in the Firebase final acceptance report; it does not establish full physical token lifecycle.

## 9. Security and regression

No booking/payment/permission logic or applied migrations changed in this physical acceptance cycle. Both fresh explicit-Staging Android builds passed. Previous verified regression baseline: User analyze and 23 tests, Owner analyze and two tests, Admin build/lint, 226 PostgreSQL tests, seven Edge tests, seven local Thawani tests, four native configuration tests and ten hosted security checks. These are prior results, not fresh physical-cycle runs. Fresh requested regression reruns remain pending.

## 10. Problems and repairs

USB authorization and installation restrictions required user approval. No application-code repair has been made. Owner notification permission remains an unresolved device setup prerequisite.

## 11. Test data

New normal authenticated cash/no-add-on booking `d09b7178-c3f5-45ec-8aa7-e3de04cc4f4a`, Staging Two Courts, 15 October 2036, 10:00–11:00 Oman. Cash/unpaid; no fabricated payment or refund. Booking notification event `47d2ae08-6958-47b7-b37a-a53f966a77fa`. It remains active at this checkpoint. Any cancellation will use the approved RPC after reviewing the fixture; historical bookings were not cleaned up.

## 12. Incomplete checks

Final duration acceptance: the account holder explicitly confirmed the updated Owner foreground alert appeared and remained approximately ten seconds until automatic dismissal. Dedicated cash/no-add-on fixture `416329c9-e209-4eab-aff8-ce805220ab71`, 22 October 2036, 10:00–11:00 Oman, was created through normal checkout and subsequently cancelled by the normal RPC. This is user-observed timing, not an automated stopwatch measurement. Owner foreground display, action and requested duration are now confirmed on the physical device.

Final physical-cycle source changes are limited to `arena_owner/lib/main.dart` (prominent cancelled status), `arena_owner/lib/core/owner_push_service.dart` (ten-second foreground alert), `playon/supabase/functions/push-notifications/handler.ts` (event-specific booking push text and Owner cancellation schedule), and `playon/supabase/tests/phase3_push_fake_test.ts` (regression assertions). This report is new. No applied migration or other business logic was changed. All dedicated physical fixtures through 22 October were cancelled using their designated normal cancellation operations; audit records remain.

Final acceptance limits: both apps passed observed foreground, background and terminated booking scenarios, with User's initial terminated nonreceipt still documented. User C → B switching and logout suppression passed. Complete match push/navigation and Owner A → Owner B account isolation were not performed. Reboot delivery was not performed. These remaining coverage gaps prevent claiming COMPLETE; no real Thawani payment/refund or physical iOS success is claimed. The report footer remains PARTIAL accordingly.

Ten-second Owner foreground duration update: analyze and both existing Flutter tests passed; explicit-Staging debug build passed; approved in-place installation returned Success with no data clearing. Reopen Owner to run this updated build. Ten-second timing has not been measured on the physical device; only build/install and the earlier foreground action scenario are confirmed.

Owner physical foreground acceptance: created then cancelled normal cash/no-add-on booking `fae8a906-0813-41dc-9fc5-4d41b3b362c6`, 21 October 2036, 10:00–11:00 Oman. The account holder confirmed the in-app cancellation alert and Open action reached the correct cancelled booking. Confirmation-event resend was not forced; a distinct cancellation event preserved idempotency. The account holder requested a longer visible duration. Changed only Owner foreground SnackBar duration from the Flutter default to ten seconds (`lib/core/owner_push_service.dart`); no lifecycle or business-rule changes. This duration update requires build/install verification and is not yet claimed visually timed on-device.

Final User terminated retest: on account B, the account holder swiped User from Recents. ADB verified no User process and package stopped=false before cancellation. Cancelled B's designated booking `e270489a-3e7c-4ad8-8122-4be977a12c4b` normally (204). The account holder explicitly answered yes to notification receipt and launching into that booking in Cancelled state. This scenario PASSED; the first C terminated test remains a documented nonreceipt, not an invented resolved root cause.

All newly created physical-cycle fixtures (15, 16, 17, 18, 19 and 20 October 2036) were eventually cancelled through the normal RPC for their designated acceptance events. Their historical booking/order/notification records remain; no direct deletion, inventory mutation or fake refund was used. Earlier emulator fixtures and historical bookings were not cleaned up.

Remaining actions: separately verify Owner foreground/action; use a second authorized Owner account to test Owner-to-Owner switching; verify match notification navigation through a legitimate match flow when provider prerequisites are available; optionally repeat after a user-controlled phone reboot. A longer terminated-device soak/retest is warranted because the initial User terminated confirmation did not appear and the exact cause was not established. These limits keep overall acceptance PARTIAL despite later successful terminated delivery for both apps.

Account-switch physical observation: the account holder confirmed that User B received only its own booking-confirmation notification and that tapping opened the correct booking; C's cancellation notification did not arrive in B. Thus the tested C logout → B login → old-account suppression → B delivery/navigation flow is PASS, with server evidence of device-registration removal and recreation. This does not establish Owner-to-Owner isolation or every token lifecycle failure mode. B's own foreground confirmation/action was also confirmed while the requested test state was User open; direct visual evidence is the account holder's confirmation.

The account holder confirmed that, after User logout, the previous account's new notification arrived only in Owner. User logout suppression therefore passed for this observed event. Subsequently the account holder logged into authorized User account B. RLS-visible metadata confirmed a new active Android registration for B and no physical registration remaining for C. Cancelled C's 19 October fixture normally (204), then created normal cash/no-add-on B booking `e270489a-3e7c-4ad8-8122-4be977a12c4b`, 20 October 2036, 10:00–11:00 Oman. Its event `cde10642-14e2-49b7-a23a-5f0f586632e0` dispatched to one B device. Physical nonreceipt of C and display/navigation for B await confirmation. B fixture remains active pending its designated cancellation test.

Physical logout server verification: after the account holder used User Sign out (Owner remained signed in), the physical User device-registration row disappeared from the previous account's own RLS-visible rows; the two emulator registrations remained. Created normal cash/no-add-on previous-account fixture `43f7e53b-d428-4c99-bbc1-b614465b67b9`, 19 October 2036, 10:00–11:00 Oman. Its notification event `2a88b64c-db5d-4a81-aeb6-69f6d3cbdd3e` dispatched only to the two remaining User devices. Physical absence of a new User notification and subsequent alternate-account login await observation. Owner is expected to receive its independent authorized event. This fixture remains active pending its designated cancellation test; no historical cleanup.

Physical User wording/navigation acceptance: the account holder explicitly answered success to the combined checks for the latest 18 October 2036 cancellation notification: event-specific text and opening the same booking in Cancelled state. User real background cancellation display and correct detail navigation are PASS for this scenario. Owner equivalent cancellation/name/schedule/red-banner scenario was also confirmed. These do not resolve the earlier User terminated-delivery failure or establish account-switch/logout isolation.

After the background comparison, the account holder reported Owner success and that the User notification still said only Update. This supports User visible notification receipt but does not explicitly establish correct User tap navigation. Updated only push presentation: User booking confirmation/cancellation now names the event without customer or financial information. Expanded the existing transport-fake regression test to assert User cancellation wording; it passed. Deployed only push-notifications to the explicit Staging project. Created/cancelled normal cash/no-add-on fixture `20bef6ff-cf2c-4dde-ac8d-413453d856f2`, 18 October 2036, 10:00–11:00 Oman, for physical wording/navigation verification. Both wording and correct User destination await explicit confirmation. No client update or financial state change was required.

Background comparison after the missing User terminated notification: the account holder reopened User and pressed Home without removing it from Recents. A live User process was verified. Cancelled booking `946e7016-e94d-4214-952b-fc6436f39766` through the normal RPC (204). Its new event was recorded by the physical User Firebase receiver while backgrounded. System-tray display and correct cancelled-booking navigation await observation. This is a new event, not an attempt to bypass delivery idempotency. The test fixture is now cancelled; no financial refund was fabricated.

Terminated-lifecycle preparation: after the account holder swiped both apps out of Recents, `pidof` returned no process for either package. Package state for both showed `stopped=false`, establishing genuine process termination without Force Stop. Created normal authenticated cash/no-add-on booking `946e7016-e94d-4214-952b-fc6436f39766`, 17 October 2036, 10:00–11:00 Oman, for this test. User notification event `d320bfaf-0b63-4458-b7d6-1e2cf7bbdba7`; worker accepted three registered User-device deliveries. The account holder answered Owner yes and User notification absent. Thus Owner's requested terminated delivery/navigation/name scenario is confirmed, while User terminated delivery is NOT passed. Follow-up User permission remained granted and stopped=false; its process remained absent. Android exit history included SwipeUpClean and subsequent empty-process system cleanup. These do not establish a definitive root cause. Repeated dispatch safely skipped all three deliveries; no duplicate send was forced. A background/resume comparison is pending. This fixture remains active at this checkpoint; no old booking cleanup was performed.

Owner update was explicitly approved and installed successfully with `install -r`, without clearing application data. The account holder reopened Owner and placed it in the background. Created and cancelled dedicated cash/no-add-on booking `2082aac0-171f-49cf-9b44-a7aeba6016c8` for 16 October 2036, 10:00–11:00 Oman using authenticated checkout and cancellation RPC (204). No electronic payment/refund was simulated. Android recorded both events reaching Owner. The account holder explicitly confirmed success for all requested observations: specific cancellation notification naming Staging Two Courts and 16/10/2036 10:00–11:00; tap opening the correct booking; prominent red CANCELLED / Arabic cancellation banner. This physical Owner background cancellation/navigation/clarity scenario is PASS. The complete lifecycle/account-isolation matrix remains incomplete.

### Physical observations and requested clarity fix

The account holder confirmed User notification display. After Owner login/permission approval, Android confirmed its notification permission and native Firebase receipt of the new cancellation event. The account holder confirmed that an update notification opened the cancelled booking, but reported that cancelled status was insufficiently prominent and that the notification needed cancellation/date/time wording. This establishes physical notification/tap evidence for that observed event; it does not establish the complete lifecycle matrix or both app destinations separately.

The dedicated physical fixture was cancelled successfully by the normal RPC (HTTP 204); no electronic refund was invented. Added a prominent red bilingual cancellation banner in Owner Booking details and specific Owner cancellation push text with authoritative booking dates/times in Asia/Muscat. The existing generic customer/financial privacy behavior remains. Fresh Owner analyze/tests passed; fresh User tests passed; the expanded Edge fake test passed and asserts the exact correct Oman schedule and no sensitive financial/customer fields.

After the account holder completed CLI authentication, the project listing verified `arena-staging` / `gtcrijikfaglqcwqozel` as ACTIVE_HEALTHY. Deployed only push-notifications, uploading index.ts and handler.ts with the explicit Staging project reference. Post-deployment missing/wrong worker secrets were rejected (401); correct authentication reached input validation (400 for missing notification ID). Existing secrets and authentication configuration were retained. New Owner debug build passed, but installing this update awaits explicit replacement approval; the new UI and server wording still need physical visual acceptance.

The fresh isolated Phase 1/2/3/refund/host/Firebase SQL chain completed successfully (226 tests). Its first attempt found the loopback test database stopped; starting PostgreSQL on 127.0.0.1:55439 restored the test environment and the complete rerun passed. This was not a hosted database migration or Production operation.

Device-visible observations, navigation, remaining lifecycle, account isolation, Owner permission/registration and fresh regression completion are pending. Real Thawani and iOS are outside this physical Android acceptance result. Production untouched; Phase 4 not started.

- USER PHYSICAL ANDROID: PARTIAL
- OWNER PHYSICAL ANDROID: PARTIAL
- NOTIFICATION NAVIGATION: PARTIAL
- TOKEN & ACCOUNT ISOLATION: PARTIAL
- REGRESSION SAFETY: PASS
- ANDROID ACCEPTANCE: PARTIAL
