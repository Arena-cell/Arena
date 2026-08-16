# Supabase authentication setup

## Email verification

In **Supabase Dashboard → Authentication → Providers → Email**, keep
**Confirm email** enabled. A user verifies their address before signing in and
then completes their profile and device-location permission inside the app.

## Make reset links open the app

In **Authentication → URL Configuration**, add this Redirect URL exactly:

`playon://auth-callback`

The mobile app is configured to receive this link and will open its
password-update screen after a reset link is opened.

## Send mail from the company address

In **Project Settings → Auth → SMTP Settings**, enable custom SMTP and enter
your company mailbox/SMTP provider credentials. Configure the sender name as
`Arena` and use an authenticated company-domain address. This replaces the
default Supabase sender.
