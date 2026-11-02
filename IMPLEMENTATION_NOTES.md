# Arena implementation notes

## Database deployment

Apply `supabase/arena_v2_booking_system.sql` after the existing production
schema migrations. The migration is non-destructive and does not delete demo
arenas, bookings, profiles, users, or conversations.

Before any demo-data cleanup, run `supabase/reset_demo_data_preview.sql`. It is
read-only and lists the exact arena, court, booking, and match rows that would
be candidates for a separately approved cleanup. No deletion SQL is included
on purpose.

After applying the migration, classify every legacy arena as `men` or `women`,
set `court_count` to the real number of physical units, and then validate the
deferred arena gender constraint. Setting `court_count = 4` automatically
creates Courts 1–4; users never choose the number themselves.

```sql
alter table public.arenas validate constraint arenas_audience_gender_check;
```

Do not validate it until all legacy `mixed` or null rows have been reviewed.

The local machine did not have a linked Supabase CLI/configuration, so the
new completion changes were not claimed as deployed. To apply the checked-in
SQL now, open the production project SQL Editor, paste the complete contents of
`supabase/arena_v2_booking_system.sql`, review the target project name, and run
it once. For a CLI workflow, first install/login/link Supabase CLI to project
`mbgqnlbuslrgamkzdqpd`, convert this SQL into the repository's approved
migration, and run `supabase db push --dry-run` followed by `supabase db push`.
Never run `db reset` against production.

After the migration succeeds, run the complete
`supabase/arena_v2_verification.sql` in the SQL Editor. It wraps its fixtures in
a transaction and always ends with `ROLLBACK`; it does not retain test users,
arenas, courts, bookings, matches, coupons, or notifications. The script checks
four-unit generation/allocation, the fifth-booking rejection, protected court
reduction, open end boundaries, cancellation recovery, gender enforcement,
server-priced water, single-use coupons, private-match access, owner scope, and
notification event de-duplication. True simultaneous-session contention still
requires two authenticated clients against the deployed migration and is not
claimed as locally tested.

## External services still required

### Phone authentication

The user-facing authentication flow now uses an Oman mobile number, SMS OTP,
and then a separate username/first-name/last-name/gender step. To deliver real
codes, enable the Phone provider in Supabase Authentication and configure a
supported SMS provider. The dashboard currently reports Phone as disabled and
asks for a Twilio Account SID, Auth Token, and Message Service SID. Until those
credentials are supplied, real OTP delivery cannot be tested and the app shows
a localized configuration message.

### Push notifications

The database notification feed, unread state, unique event key, delivery ledger,
device-token registration/refresh/logout cleanup, badge count, localization,
related-page navigation, and FCM HTTP v1 Edge Function are implemented.
External push delivery is not claimed as active because this repository does
not contain Firebase/APNs credentials or platform configuration.

Activation requires:

- Register the current Android application id in Firebase, download
  `google-services.json`, and place it at `android/app/google-services.json`.
- Register the current iOS bundle id in Firebase, download
  `GoogleService-Info.plist`, and place it at
  `ios/Runner/GoogleService-Info.plist` through Xcode so Runner includes it.
- Enable Push Notifications and Background Modes → Remote notifications for
  Runner, then upload the APNs `.p8` key, Key ID, and Team ID to Firebase. The
  checked-in entitlement, background mode, and localized permission strings are
  already prepared; Xcode/iOS signing cannot be validated from Windows.
- Store the Firebase service-account JSON only as Supabase secret
  `FIREBASE_SERVICE_ACCOUNT_JSON`; never add the file to Flutter or Git.
- Store a random webhook secret as `PUSH_DISPATCH_SECRET`, deploy
  `push-notifications`, and create a Database Webhook for INSERT events on
  `public.notifications`. Its URL is the deployed function URL and its
  `x-arena-push-secret` header must equal that secret.
- Schedule `public.enqueue_due_event_reminders()` every five minutes with
  Supabase Cron. Unique `event_key` and delivery constraints suppress repeats.

Required server commands after Supabase CLI authentication:

```bash
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='<json>' PUSH_DISPATCH_SECRET='<random-secret>'
supabase functions deploy push-notifications --project-ref mbgqnlbuslrgamkzdqpd
```

`firebase_core` initializes Firebase and `firebase_messaging` provides native
FCM/APNs permission, token refresh, foreground/background/open handling. They
are the only new Flutter packages and are required for native push delivery.
The iOS entitlements/background-mode code is present, but both Android and iOS
still use the placeholder identifier `com.example.playon`. Choose the final
production identifier before registering the Firebase apps; changing it later
creates different Firebase/Apple app identities.

### Arena Assistant

The Flutter conversation UI and the safe Edge Function are implemented at
`supabase/functions/arena-assistant/index.ts`. Deploy it and configure:

```text
OPENAI_API_KEY=<server-side secret>
OPENAI_MODEL=gpt-5-mini
```

The function uses the signed-in user's Supabase session, fixed queries, gender
checks, row-level security, and the same whole-range court-availability RPC. It
does not accept or execute model-generated SQL. No OpenAI key is stored in the
Flutter application or repository.

Deploy after adding the secret:

```bash
supabase secrets set OPENAI_API_KEY='<server-side-key>' OPENAI_MODEL='gpt-5-mini'
supabase functions deploy arena-assistant --project-ref mbgqnlbuslrgamkzdqpd
```

## Logo

The repository already contains the approved back-to-back boy/girl Arena mark
in `assets/images/arena_splash_logo.png` and
`assets/images/arena_logo_transparent.png`. The existing splash and login flow
already use these files, so no replacement or generated logo was introduced.

## Empty-state assets

The repository contains `assets/images/ui/messages-empty.png` and the existing
Arena field placeholder. No unrelated internet artwork was introduced. To give
every empty state its own approved illustration, the design handoff still needs
the following lightweight local assets in one consistent Arena navy style:

- `assets/images/ui/bookings-empty.png` — My bookings.
- `assets/images/ui/notifications-empty.png` — Notifications.
- `assets/images/ui/matches-empty.png` — Public matches.
- `assets/images/ui/arenas-empty.png` — Explore/filter results.
- `assets/images/ui/search-empty.png` — User and global search.
- `assets/images/ui/players-empty.png` — Joined-player list.
- `assets/images/ui/image-failed.png` — Failed stadium/gallery image.

Until approved artwork is supplied, those states use restrained local icons or
the existing placeholder and never load arbitrary network illustrations.

## Local verification

Flutter 3.29.3 / Dart 3.7.2 were available. Static analysis, Flutter tests, the
Android debug build, Web build, the admin TypeScript/Vite checks, and Deno type
checking for both Edge Functions passed locally on 17 August 2026. Real SMS,
FCM/APNs delivery, Edge Function deployment, iOS signing/building, the database
migration/rollback verification, and cross-session database concurrency still
require the external credentials and linked environments described above.

```bash
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
flutter build web
npx --yes deno check supabase/functions/arena-assistant/index.ts supabase/functions/push-notifications/index.ts
```

The admin portal passed `pnpm lint` and `pnpm build` in its separate directory.

The React admin/stadium-owner portal is stored separately at
`C:\monther\MN\my_apps\playon_admin`. It is not currently a Git repository, so
its changes cannot be included in the Flutter repository pull request until the
owner places it under version control or provides its remote.
