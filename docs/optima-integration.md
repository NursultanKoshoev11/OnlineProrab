# Optima Bank integration

## Current implementation

The app now uses a server-owned payment order flow:

1. Android sends only `plan_code` and `provider` to
   `POST /api/v1/subscriptions/checkout`.
2. The backend selects the authoritative KGS amount and creates a
   `payment_orders` row.
3. The backend returns a hosted checkout URL when Optima has supplied a URL
   template, or returns a controlled test order in development test mode.
4. Android opens the returned URL externally. Card data never enters the app.
5. Android can read the order state from
   `GET /api/v1/subscriptions/payments/{order_id}` after returning from the
   bank.

The test completion endpoint is available only when `PAYMENT_TEST_MODE=true`
and `APP_ENV` is not `production`:

`POST /api/v1/subscriptions/payments/{order_id}/test-complete`

## What is intentionally not guessed

Optima's public page confirms internet acquiring for websites and mobile
applications, but it does not publish the signed API request and webhook
contract needed to activate a real subscription. The webhook endpoint therefore
fails closed with `501` until the bank's technical manual is provided. It must
not be changed to trust an unsigned callback.

After receiving the manual, implement the bank-specific adapter and signature
verification using the exact fields from the document. Do not put merchant
secrets in the Android APK.

## Configuration

```env
PAYMENT_TEST_MODE=false
PAYMENT_RETURN_URL=https://your-domain.example/payment-return
PAYMENT_WEBHOOK_URL=https://your-domain.example/api/v1/payments/optima/webhook
OPTIMA_PAYMENT_URL_TEMPLATE=
```

`OPTIMA_PAYMENT_URL_TEMPLATE` is only a bridge for a bank-provided hosted URL
format. Supported placeholders are `{order_id}`, `{amount}`, `{currency}`,
`{return_url}`, and `{webhook_url}`. Leave it empty until Optima gives the
exact format.
