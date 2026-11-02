# Supabase phone authentication setup

## Required Phone provider

The Arena entry flow uses Oman phone numbers and SMS OTP for both sign-in and
account creation. In **Supabase Dashboard → Authentication → Providers →
Phone**, enable Phone and configure the SMS provider credentials. The current
project reports Phone as disabled and requires these Twilio values:

- Account SID
- Auth Token
- Message Service SID

Store those values only in the Supabase provider form. Do not add them to
Flutter, `.env` committed to Git, or GitHub. Disable test OTPs before production.

After a valid code, a new or incomplete account is sent to the separate
username, first-name, last-name, and gender page. Guest browsing remains
available without authentication.

## OTP validation checklist

- New Oman number creates an account, then opens profile completion.
- Existing number signs in without opening profile completion again.
- Incorrect and expired codes remain rejected by Supabase.
- Resend remains disabled for 30 seconds after a code is sent.
- No fixed or test verification code is present in the app.

Email/password screens remain only as legacy source code and are not linked
from the current Arena login landing page. Do not enable them as the primary
entry flow.
