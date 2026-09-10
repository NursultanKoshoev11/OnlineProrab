# Bank payment integration

## Current implementation

The app uses a server-owned payment order flow for the explicitly supported
providers `optima` and `obank`:

1. Android sends only `plan_code` and `provider` to
   `POST /api/v1/subscriptions/checkout`.
2. The backend selects the authoritative KGS amount and creates a
   `payment_orders` row.
3. The backend returns a hosted checkout URL only when the selected provider's
   bank-supplied URL template is configured, or returns a controlled test order
   in development test mode.
4. Android opens the returned URL externally. Card data never enters the app.
5. Android can read the order state from
   `GET /api/v1/subscriptions/payments/{order_id}`.

The test completion endpoint is available only when `PAYMENT_TEST_MODE=true`
and `APP_ENV` is not `production`:

NaNPOST /api/v1/subscriptions/payments/{order_id}/test-complete`

## O!Bank

O!Bank's public business page advertises internet acquiring from a partner's
website or application and integration with software. Its exact signed API
request and webhook contract are not present in the public page used for this
implementation.

The O!Bank provider is therefore registered in the backend, but its live
webhook remains fail-closed with `501` until O!Bank supplies the technical
manual and merchant credentials. Do not activate a subscription from an
unsigned callback.

Configuration:

```env
OBANK_PAYMENT_WEBHOOK_URL=https://your-domain.example/api/v1/payments/obank/webhook
OBANK_PAYMENT_URL_TEMPLATE=
```

## Optima Bank

Optima's public page confirms internet acquiring for websites and mobile
applications, but the exact signed API request and webhook contract must come
from the bank.

Configuration:

```env
PAYMENT_WEBHOOK_URL=https://your-domain.example/api/v1/payments/optima/webhook
OPTIMA_PAYMENT_URL_TEMPLATE=
```

## Hosted URL bridge

Both providers support these placeholders when the bank gives an exact hosted
checkout URL format:

NaN{order_id}`, `{amount}`, `{currency}`, `{return_url}`, and
NaN{webhook_url}`.

This bridge is not a substitute for a bank API adapter or webhook signature
verification. Merchant secrets must never be put in the Android APK.