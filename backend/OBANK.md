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

The production Android and iOS builds can open the live `app_link` directly from
the subscription screen when `OBANK_NATIVE_CHECKOUT_ENABLED=true` is passed at
compile time and the API host is `api.stroy.com.kg`. Staging keeps the native flow
restricted to debug builds and the sandbox API. The app checks payment status with
the backend when the user returns from O!Bank. Before distributing a store build,
confirm that the applicable Apple and Google billing rules or an approved
alternative-billing program permit this external subscription payment flow.

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

For live production payments, use the live SID/password and have the bank confirm
the live API URL. Set `OBANK_TEST=false`. The callback and return URLs must use
HTTPS. `OBANK_ENABLED` defaults to false, so the payment API stays closed until
the merchant secrets are installed.

For a temporary sandbox verification on the existing production API, production
accepts `OBANK_TEST=true` only when `OBANK_API_URL` is exactly the sandbox JSON
endpoint, `OBANK_TEST_ONLY_PHONE` identifies one E.164 test account, and
`OBANK_TEST_PRICE_KGS` is from 1 to 100. Checkout and status access are blocked
for other accounts; the test account can purchase only the Standard monthly plan
at that test price. A successful sandbox callback grants that account a real
production subscription entitlement, so use a dedicated test account and turn
`OBANK_ENABLED` off and clear the sandbox credentials/test settings immediately
after verification. Do not accept customer purchases in this mode. It cannot be
used for real payments; switch to live merchant credentials and `OBANK_TEST=false`
for launch.

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
