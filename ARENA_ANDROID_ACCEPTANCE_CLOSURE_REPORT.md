# ARENA ANDROID ACCEPTANCE CLOSURE REPORT

11 October 2026, Muscat. FINAL CLOSURE CHECKPOINT: PARTIAL due to the external match-flow prerequisite. Staging only: Supabase `gtcrijikfaglqcwqozel`, Firebase `arena-staging-ae20f`. Physical device model 23129RAA4G / Android 14. This report distinguishes previous acceptance from new closure checks; the final matrix below supersedes intermediate pending statements in the chronological evidence.

| Closure check | Result |
|---|---|
| User terminated confirmation and correct booking navigation | PASS |
| Owner terminated confirmation and correct booking navigation | PASS |
| Independent terminated cancellation in both applications | PASS |
| Owner A logout → B own-event / A suppression → A return | PASS |
| Real B-session RLS denial for A bookings and matches | PASS |
| Manual reboot, retained permissions/tokens, new delivery/navigation in both apps | PASS |
| Existing clear booking/cancellation text, red Owner status and ten-second alert | PASS from preceding physical acceptance |
| Initial User nonreceipt root cause | UNDETERMINED; no repair claimed |
| Physical legitimate match notification navigation | PENDING — Thawani/live eligible match prerequisite |

Account-holder physical display/tap confirmations are explicitly separate from queue/FCM acceptance. This sample is not a guarantee of indefinite delivery or latency.

## 1. User

Previous physical acceptance: foreground confirmation/action, background cancellation/action, logout suppression, C → B switching and own-event navigation passed. Terminated B cancellation passed on retest; initial C terminated confirmation was not observed. Do not erase that failed observation.

## 2. Owner

Previous physical foreground/background/terminated booking delivery/navigation, clear cancellation/name/schedule, red cancelled status and approximately ten-second foreground alert were explicitly confirmed. New account isolation sequence is in progress.

## 3. Terminated reliability

Final observation: the account holder explicitly confirmed both User and Owner received the independent 24 October cancellation and opened the correct cancelled booking. Both application processes were absent and stopped=false before this event. Together with the separately confirmed new booking event, this closes the requested independent-event sample. The initial unexplained User nonreceipt remains documented; no code or battery-setting repair is claimed.

| Notification ID | Audience / event | Queue / worker | Device state / physical observation |
|---|---|---|---|
| 9372335b-0aa6-4c92-b531-2dce39d3e809 | User confirmation, 24 October | sent; device sent; attempt 1 | No process / not force-stopped; display and correct booking PASS |
| 3e8f239c-cf55-4b7c-854e-a9550ce9a32a | Owner confirmation, 24 October | sent; device sent; attempt 1 | No process / not force-stopped; display and correct booking PASS |
| c0686dc6-08d3-4e92-8008-4ebaffbffa01 | User cancellation, 24 October | sent; device sent; attempt 1 | No process / not force-stopped; display and correct cancelled booking PASS |
| 3552fc65-090e-48e4-88c2-60f1767835e2 | Owner cancellation, 24 October | sent; device sent; attempt 1 | No process / not force-stopped; display and correct cancelled booking PASS |
| 357f3857-3759-4bdb-b9a8-d9aa5ae9e257 | User confirmation, 25 October | sent; device sent; attempt 1 | After verified manual reboot, no process; display and correct booking PASS |
| 1596c846-af39-4775-832b-7f766c297bc4 | Owner confirmation, 25 October | sent; device sent; attempt 1 | After verified manual reboot, no process; display and correct booking PASS |

Representative genuine Firebase provider references for these six events, respectively: `projects/arena-staging-ae20f/messages/0:1791726208386493%17a9e92417a9e924`, `projects/arena-staging-ae20f/messages/0:1791726208666150%df333baddf333bad`, `projects/arena-staging-ae20f/messages/0:1791726390922122%17a9e92417a9e924`, `projects/arena-staging-ae20f/messages/0:1791726389099441%df333baddf333bad`, `projects/arena-staging-ae20f/messages/0:1791726767200272%17a9e92417a9e924`, `projects/arena-staging-ae20f/messages/0:1791726778878552%df333baddf333bad`. Owner also has emulator deliveries; the complete per-device mapping is retained in the ignored evidence ledger, with no raw tokens. No duplicate same-event resend was forced.

Physical closure confirmation event: the account holder separately answered User success and Owner success for the 24 October confirmation (receipt and correct tap destination). This verifies both terminated-delivery/navigation scenarios. After another Recents removal, both processes were again absent and stopped=false; cancelled the designated booking normally (204), creating an independent cancellation event rather than duplicating the confirmation. Cancellation observation is pending; its successful normal cancellation releases the dedicated slot while retaining audit records.

First closure soak event: initial preflight found a live User process and aborted without sending; after a second account-holder swipe, both package processes were absent and both stopped=false with notification permission granted. Created genuine cash/unpaid/no-add-on booking `8bd6735c-6886-443f-be6e-3f5fd4796818`, 24 October 2036, 10:00–11:00 Oman. User notification `9372335b-0aa6-4c92-b531-2dce39d3e809`; authenticated worker returned sent=1/failed=0/skipped=0. Queue/per-device/provider evidence saved in `build/android-closure-evidence/reliability-one-delivery.json`. Physical User and Owner receipt/navigation await separate confirmation. The live-process aborted preflight is not falsely classified as a terminated test.

Initial missing event `d320bfaf-0b63-4458-b7d6-1e2cf7bbdba7`: notification queue marked sent / attempt 1. Current retained device-delivery records are sent with no errors and genuine Firebase provider references. The original worker reported three device sends; current records retain two, after subsequent device deregistration, so they must not be presented as a complete original physical-device ledger. Provider acceptance does not prove phone display. Exact first-failure cause remains UNDETERMINED.

Read-only phone diagnostics: User standby bucket 40; RUN_ANY_IN_BACKGROUND default allow; device powered and not in device idle at inspection. Earlier notification permission granted, package stopped=false, and exit history included SwipeUpClean and empty-process cleanup. Channel importance previously checked as 4. No phone power/security settings changed. New independent terminated observations and per-event queue/provider evidence are pending.

## 4. Owner A → B

Return-to-A receipt/navigation is additionally established by the new 24 October A-arena event, explicitly confirmed in Owner. A → logout → B registration/own delivery/A suppression → B logout → A registration/own delivery round trip has been tested. B could not read A bookings or matches in actual public-key RLS tests. Owner account isolation for this authorized two-account sequence: PASS.

Return-to-A server verification: B's phone registration was removed; a newly updated A registration appeared alongside its two emulator registrations. Both 23 October switch fixtures were cancelled through their normal authenticated RPCs (204 each), preserving their orders/inbox/audit records. Physical A cancellation receipt/navigation and B cancellation suppression await confirmation.

Physical B confirmation: the account holder explicitly confirmed only B's arena notification arrived, tapping opened the correct B booking, and A arenas did not appear. Combined with real B RLS checks and device-registration transition, A logout → B registration → A-event suppression → B-event/navigation is PASS. Return-to-A verification is still pending, so the complete round trip is not yet marked PASS.

User explicitly authorized creation of a new Staging test Owner. Created genuine Supabase Auth identity `263daac0-52f9-4973-a490-aaeaacafe3f3`, username owner_stage_b; registered it in the existing staff-login table and assigned only new arena `a1000000-0000-4000-8000-000000000003`, Staging Owner B Court. Original arena ownership unchanged. Fixture transaction checked the existing Staging installation receipt and conflicting ownership. No new migration or permission model.

Credentials remain in ignored local evidence; none are reproduced here. Temporary server API-key file used for authenticated Auth Admin creation was deleted. Real B-session public-key tests passed: B sees its assigned arena, cannot read A bookings, cannot read A matches. A phone registration disappeared after account-holder logout; two emulator registrations remained. Physical B login, token registration, event isolation, and A return remain pending.

## 5. Matches

Fresh hosted future-match read returned only two cancelled legacy test matches, with no checkout/provider reference. No eligible live provider-backed match was found in this result. The first read used a nonexistent is_public column and failed without mutation; the corrected read succeeded. No fixture was promoted, payment state changed, or paid success invented. Physical match flow remains an external prerequisite, not a failed fake test.

Physical match event/navigation remains PENDING unless a legitimate existing flow can be tested. No bypass of Card payment, no fake paid match, no invented provider success. Prior isolated match/RLS tests are not physical acceptance.

## 6. Reboot

Final physical confirmation: the account holder explicitly confirmed the new post-reboot notification appeared and opened the correct 25 October booking in User and Owner. POST-REBOOT DELIVERY: PASS for both observed scenarios. Later normal cancellation safely released this dedicated fixture; post-reboot cancellation itself was not requested as an additional acceptance scenario.

Actual manual reboot verified: ADB reconnected with a new transport, /proc/uptime approximately 251 seconds. Both apps had no process, stopped=false, notification permission granted, and active device registrations retained. Created genuine authenticated cash/unpaid/no-add-on post-reboot booking `8ff63c15-19c1-4e98-b391-aa10ed951f59`, 25 October 2036, 10:00–11:00 Oman. User event `357f3857-3759-4bdb-b9a8-d9aa5ae9e257`; worker accepted one User-device delivery. Per-event queue/device/provider references for both closure reliability and reboot events are recorded in ignored `build/android-closure-evidence/closure-delivery-ledger.json`. Physical post-reboot display/navigation awaits separate confirmation; no automatic restart was used.

User approved a later manual phone reboot. It has not yet occurred. No automatic reboot command issued.

## 7. Navigation

Previous booking routes passed on-device for both apps. New closure events and Owner B versus A access remain in progress; private-match physical routing has not been verified.

## 8. Proven problems / cause

Initial User terminated nonreceipt remains unexplained. Observed later success does not establish a repair. No new application defect proven in this closure cycle.

## 9. Repairs

No application or worker source changed in this closure cycle. Existing specific booking text, clear Owner cancelled state and ten-second alert retained. Only the explicitly authorized Staging test identity and independent arena were added.

## 10. Regression

Prior physical-cycle baseline, not new runs: both Flutter analyze clean; User 23 / Owner 2 tests; explicit-Staging debug builds; 226 local PostgreSQL checks; expanded Edge test; post-deploy worker auth rejection. All were recorded in the physical report. No new code modification currently warrants repeating all costly suites. Fresh B-session hosted authorization checks passed.

## 11. New data

Final hosted relation review verified all four closure bookings cancelled, payment_method=cash, payment_status=unpaid, addon_count=0 and refund_count=0. Review evidence: `build/android-closure-evidence/fixture-final-state.json`. Their booking/order/inbox/audit records remain. Owner B and its independent arena remain authorized test fixtures. No old data cleanup occurred.

Owner-switch events: normal cash/unpaid/no-add-on authenticated bookings `c993e53b-53fa-448a-b40b-775a9695ba93` (A arena) and `7c728531-915b-40a3-bcaa-fc99ee74d429` (B arena), both 23 October 2036, 10:00–11:00 Oman. User-event IDs `7ca474e6-10ea-47b5-9b05-41706209a620` and `ff99a7cc-a387-435d-9109-49891a45e707`. Physical B registration appeared under B while A retained emulator registrations only. Full owner/user queue and provider references saved in ignored `build/android-closure-evidence/owner-switch-delivery.json`. Physical Owner B own-event display/navigation and A-event suppression await confirmation. Both designated fixtures remain active pending their cancellation tests.

New Owner B identity and independent arena above, preserved as authorized fixtures. No old bookings, notifications or audit records deleted. New event fixtures will be listed as created, reviewed and cancelled using normal RPCs.

## 12. Pending

Final remaining external requirement: physical match-notification navigation through a legitimate, eligible match. Current future-match read found only cancelled fixtures without real provider-backed checkout. Do not bypass Card requirements or revive those fixtures to manufacture a PASS. When Thawani Sandbox credentials and a real valid match flow become available, perform the match notification/privacy/navigation test. Prior isolated Phase 3/RLS match tests remain prior local evidence. This single remaining required category prevents Android COMPLETE.

No source, migration, server-secret, application ID, Firebase project, booking/payment/refund/inventory rule or phone setting was changed in this closure cycle. The only authorized hosted mutations were the independent Owner B fixture and normal creation/cancellation of the four dedicated test bookings. Earlier physical-cycle UI/push text changes were retained and not rebuilt or redeployed unnecessarily. No Production action or Phase 4 work.

Physical owner switch, independent terminated event soak, approved reboot and legitimate match acceptance remain pending. Source/business rules, payment/refund state, IDs, secrets, Firebase project and Production unchanged. Phase 4 not started.

- USER ANDROID PUSH: PASS
- OWNER ANDROID PUSH: PASS
- TERMINATED DELIVERY RELIABILITY: PASS
- OWNER ACCOUNT ISOLATION: PASS
- MATCH NOTIFICATION NAVIGATION: PENDING
- POST-REBOOT DELIVERY: PASS
- REGRESSION SAFETY: PASS
- ANDROID FINAL ACCEPTANCE: PARTIAL
