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

## External services still required

### Phone authentication

The user-facing authentication flow now uses an Oman mobile number, SMS OTP,
and then a separate username/first-name/last-name/gender step. To deliver real
codes, enable the Phone provider in Supabase Authentication and configure a
supported SMS provider. Until that provider is configured, Supabase will reject
the send-code request and the app shows a localized configuration message.

### Push notifications

The database notification feed, unread state, unique event key, device-token
table, badge, localization fields, and related-page navigation are implemented.
External push delivery is not claimed as active because this repository does
not contain Firebase/APNs credentials or platform configuration.

Activation requires:

- Android Firebase project and `android/app/google-services.json`.
- iOS Firebase/APNs project and `ios/Runner/GoogleService-Info.plist`.
- APNs capability and signing configuration in the Apple developer account.
- A server-side Supabase Edge Function or trusted worker using the FCM service
  account; the service-account key must never be shipped in Flutter.
- Flutter token registration/refresh wiring after selecting the project's push
  provider package. No package was added while those platform files are absent.

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

## Local verification limitation

This execution environment does not provide the Flutter or Dart SDK, so
`dart format`, `flutter analyze`, and `flutter test` cannot be run here. Run the
following in the configured Flutter development environment before release:

```bash
dart format lib test
flutter analyze
flutter test
```

The repository was still checked with `git diff --check`; SQL migrations and
all modified code were reviewed statically. Database concurrency behavior must
also be integration-tested against a disposable Supabase branch before applying
the migration to production.
