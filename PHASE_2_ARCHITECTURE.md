# Phase 2 financial boundaries

Staging target: `gtcrijikfaglqcwqozel`. Production is outside this work.

OMR amounts are integer baisa (1000 = OMR 1). PostgreSQL numeric is used only
when converting the existing hourly rate. An immutable checkout snapshot stores
the base, each add-on unit price and quantity, discount and total.

Cash fulfillment creates a booking with payment method cash and payment status
unpaid. Confirmation of a booking never implies receipt of money.

Card orders do not reserve a court before verified collection. The interface must
explain this. After server verification, fulfillment allocates inventory in one
transaction using the existing arena lock and exclusion constraint. If inventory,
coupon eligibility or participant capacity has changed, captured funds are kept
in the ledger with refund_required; no conflicting reservation is created.

Only the server integration can reconcile a provider session. Redirects are
navigation only. Webhooks require the documented HMAC signature and a fresh
server-to-server session lookup. No test success path is deployed.

Provider creation is claimed once in the database. An uncertain creation result
is recovered by client_reference_id; it is never blindly recreated. Checkout
request keys are bound to the authenticated user and exact request payload.

For matches, seat index i has total / capacity (integer division) plus one baisa
when i < total % capacity. The host is seat zero. Paid seats retain their financial
record after leaving; an already paid seat is not sold again automatically.
Host coverage becomes valid only after a verified full payment.

Rental capacity is the maximum concurrent allocation over the selected interval,
with half-open intervals. Consumable stock represents remaining units and is
decremented on fulfillment. Admin changes and fulfillment use the same arena
lock. Owners can read their catalog but cannot change prices or stock.

Thawani official contracts reviewed 2026-10-04:
- [Create session](https://thawani-technologies.stoplight.io/docs/thawani-ecommerce-api/a2a9e57e10521-create-session)
- [Retrieve session](https://thawani-technologies.stoplight.io/docs/thawani-ecommerce-api/50259f1e290c9-retrieve-session)
- [Recover by reference](https://thawani-technologies.stoplight.io/docs/thawani-ecommerce-api/dde52edbe8db7-retrieve-session-by-client-reference)
- [Webhook signature](https://thawani-technologies.stoplight.io/docs/thawani-ecommerce-api/5534c91789a48-thawani-e-commerce-api)

Create POST /checkout/session; retrieve GET /checkout/session/{session_id};
recover GET /checkout/reference/{client_reference_id}. API header thawani-api-key.
Sandbox base https://uatcheckout.thawani.om/api/v1. Session amounts are baisa;
minimum total is 100, session expiry minimum is 30 minutes. Signature is HMAC
SHA256 of raw body + '-' + thawani-timestamp, keyed by merchant webhook secret.
No undocumented idempotency header is assumed.
