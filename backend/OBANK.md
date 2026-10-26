# O!Dengi (O!Bank) subscription payments

STROY charges for its own software subscription only. Checkout creates a single-use,
fixed-amount KGS invoice for the selected `standard` or `max` plan. There is no
automatic renewal. O!Dengi receives the customer at its hosted payment page or,
on supported mobile devices, in its app; STROY does not collect card details.

The browser checkout is at `https://stroy.com.kg/billing/`. It authenticates the
account owner by the existing SMS login flow, creates a server-side invoice, then
returns to the billing page. A signed `result_url` callback activates the account
subscription only after the merchant SID, test flag, amount, currency, order, and
HMAC-MD5 signature have been checked. The billing page also asks `statusPayment`
when it returns from the bank so a delayed callback does not leave a successful
payment looking pending.

The invoice response's `link_app` is stored with the payment order and returned as
`app_link`. On mobile browsers, the billing page offers the bank app link and a
separate hosted-paylink fallback. The API only accepts the bank's HTTPS
`o.kg/l/a` link after validating that its invoice ID matches the created invoice.
Sandbox links must
be opened in O!Bank's test app; the production app rejects test invoices.

The App Store and Google Play release builds do not link to O!Dengi checkout. A
sideloaded internal staging build can open `app_link` from the subscription screen
when both `OBANK_NATIVE_CHECKOUT_ENABLED=true` and `OBANK_STAGING_BUILD=true` are
passed at compile time. The code blocks this flow in release mode and when the
configured API host is `api.stroy.com.kg`. The app checks payment status with the
backend when the user returns from O!Bank. For store distribution, digital
subscriptions must use the store's payment system unless STROY is enrolled in an
applicable alternative-billing program for the storefront.

Build an internal Android test APK with the staging API host and the two flags
above, plus `OFFLINE_DEMO=false`:

```sh
cd mobile
flutter build apk --debug \
  --dart-define=API_BASE_URL=https://<staging-api-host> \
  --dart-define=OFFLINE_DEMO=false \
  --dart-define=OBANK_NATIVE_CHECKOUT_ENABLED=true \
  --dart-define=OBANK_STAGING_BUILD=true
```

Store release workflows explicitly disable both flags. Never point the internal
payment build at the production API while sandbox credentials are configured.

## Merchant setup

Get the test SID and API password from the O!Dengi merchant administration panel.
Test and live credentials are different. Configure credentials only as backend
environment secrets. Do not use the sample credentials shown in the PDF or put a
real password in Flutter, JavaScript, GitHub source, or support logs.

For staging, configure:

```text
OBANK_ENABLED=true
OBANK_SID=<test merchant SID>
OBANK_PASSWORD=<test API password>
OBANK_API_URL=https://mw-api-test.dengi.kg/api/json/json.php
OBANK_API_VERSION=1005
OBANK_TEST=true
OBANK_RESULT_URL=https://stroy.com.kg/staging-api/api/v1/payments/obank/result
OBANK_RETURN_URL=https://stroy.com.kg/billing/
```

The live staging server has a prompt-based helper that keeps merchant secrets out
of shell history and chat:

```sh
cd /opt/projects/OnlineProrab-staging/deploy
bash ./configure-obank-staging.sh
```

Enter the sandbox SID and password at the hidden prompts. The helper writes them
to the server-only `.env` with mode `0600`, enables sandbox mode, and recreates
only the staging API container. It does not modify production. Staging payment
returns carry a `stage=1` marker so the billing page checks the staging API; normal
production billing continues to use the production API.

For a low-value sandbox checkout test, `STAGING_TEST_PAYMENT_PRICE_KGS` can be set
to a value from 1 to 100. It updates the displayed and charged price for paid plans
only when the server is in staging with sandbox payments enabled. Its default is
`0`; remove the temporary staging value after the test.

The provider's test host requires the temporary IP allowlist described in the
bank's instructions. Reopen the supplied allowlist link when the 24-hour window
expires. Do not store that private link in this repository.

For production, use the live SID/password and have the bank confirm the live API
URL. Set `OBANK_TEST=false`; the application rejects test transactions in
production. The callback and return URLs must use HTTPS. `OBANK_ENABLED` defaults
to false, so the payment API stays closed until the merchant secrets are installed.

The database migration for payment orders runs with the existing startup migration
runner. The API exposes authenticated `POST /api/v1/subscriptions/checkout` and
`GET /api/v1/subscriptions/checkout?order_id=...`, plus the public bank callback at
`POST /api/v1/payments/obank/result`. The callback stores only the provider
transaction ID and payment state; it does not persist the bank callback's payer
name, phone, or raw body.

## Refund limitation

The supplied bank guide says some payments routed through third-party banks cannot
be refunded through the O!Dengi API. This integration intentionally has no refund
button or refund API. Confirm the merchant's actual refund route and publish the
approved refund terms before enabling live payments.
