# STROY Backend Production Checklist

This checklist tracks the minimum work required before a real public release.

## Required environment variables

- `APP_ENV=production`
- `HTTP_ADDR=:8080`
- `DATABASE_URL=postgres://...?sslmode=verify-full`
- `JWT_SECRET=<strong random secret>`
- `ACCESS_TOKEN_TTL_MINUTES=60`
- `CORS_ALLOWED_ORIGINS=https://stroy.com.kg`
- `TRUSTED_PROXY_CIDRS=<reverse proxy source IP or narrow CIDR>`
- `UPLOAD_DIR=/app/uploads`
- `MAX_UPLOAD_MB=10`

Generate `JWT_SECRET` with `openssl rand -hex 32` and store it directly in the host's secret configuration. The API refuses missing secrets, known placeholders, short values, low observed byte entropy, repeated patterns, and long sequential character runs in staging and production.

## Staging environment

- Set `APP_ENV=staging` explicitly. Staging does not load values from a local `.env` file.
- Use a `DATABASE_URL` with `sslmode=verify-full` in staging and production; the API rejects connections that do not verify every database host's certificate and hostname.
- Configure `SMS_PROVIDER=twilio` or `SMS_PROVIDER=nikita` with valid provider credentials. Staging startup fails closed if SMS is unavailable.
- In staging and production, `NIKITA_API_URL` is restricted to `https://smspro.nikita.kg/api/message`; the SMS client does not follow redirects, so provider credentials cannot be replayed to a redirect target.
- Keep `DEV_SMS_CODE_ENABLED`, `REVIEW_ONLY_MODE`, and `NIKITA_TEST_MODE` disabled. The staging Compose file pins them off even if the host environment tries to enable them.
- Set `CORS_ALLOWED_ORIGINS` to the exact HTTPS origins used by the staging client.
- Set `TRUSTED_PROXY_CIDRS` to the exact IP addresses or narrow CIDRs of proxies that connect to the API container. The API trusts `X-Forwarded-For` only when `RemoteAddr` belongs to one of these networks; direct requests cannot spoof the limiter's client IP.
- SMS request quotas are 6 attempts per phone per hour, plus 30 per client IP per hour. Code verification is limited to 10 attempts per phone and 30 per client IP per 15 minutes. These counters include failed delivery/verification attempts and reserve each request before it reaches the SMS provider or code handler.
- Login abuse records retain the normalized phone number and client IP for 7 days. SMS-code records are retained until 24 hours after expiry. The API prunes these records every 6 hours in batches; a failed or timed-out cleanup is retried within 15 minutes, and a large backlog is drained over successive batches.

For local development, the fixed `dev_code` response is disabled by default. To opt in, set `DEV_SMS_CODE_ENABLED=true` and bind `HTTP_ADDR` to `127.0.0.1` or `localhost`.

## Current production blockers

1. Configure durable object storage for uploaded photos, receipts and documents.
2. Add structured logs, alerting and external uptime monitoring.
3. Test PostgreSQL and upload-storage backup/restore in staging.
4. Configure the real SMS provider and complete an auth-to-project smoke test.
5. Run mobile release builds and test the full flow on real Android and iOS devices.

## Account deletion

- Authenticated app deletion: `DELETE /api/v1/account` with a Bearer token.
- Public deletion flow: `/account-deletion` requests an SMS challenge and verifies it through `POST /api/v1/account/deletion/verify`. That endpoint does not create or update a user and does not accept project invitations; it issues a ten-minute `account:delete` token that is accepted only by the account deletion endpoint. The public flow then calls `DELETE /api/v1/account`.
- The endpoint deletes the user, owned projects, sessions, support requests, and user-uploaded files. Protected API requests verify that the account still exists, so deletion also revokes outstanding access JWTs immediately instead of waiting for token expiry. Files are removed from storage after the transaction commits.

## Local smoke test

Run this from the repository root; the root compose file starts the API and PostgreSQL services.

```bash
docker compose up --build
curl http://localhost:8080/health
curl http://localhost:8080/ready
```

Expected responses:

- `/health` returns `200 OK` when the HTTP server is alive.
- `/ready` returns `200 OK` only when the database connection is healthy.

## Support integrations

Support tickets are always stored in PostgreSQL. Delivery to Telegram and WhatsApp is optional until the provider credentials are configured.

- `SUPPORT_TELEGRAM_BOT_TOKEN`
- `SUPPORT_TELEGRAM_CHAT_ID`
- `SUPPORT_TELEGRAM_URL` (optional deep link shown in the app)
- `SUPPORT_WHATSAPP_ACCESS_TOKEN`
- `SUPPORT_WHATSAPP_PHONE_NUMBER_ID`
- `SUPPORT_WHATSAPP_TO`
- `SUPPORT_WHATSAPP_URL` (optional deep link shown in the app)

Inject these values through the deployment secret store or environment, never commit them to Git. Until a channel is configured, `POST /api/v1/support/tickets` returns `delivery_status=not_configured` while preserving the ticket for later processing.


## Temporary Google Play review-only mode

Until the SMS provider is connected, closed testing can use a single dedicated review phone:

- `APP_ENV=production`
- `REVIEW_ONLY_MODE=true`
- `REVIEW_SMS_PHONE=+996...`
- `REVIEW_SMS_CODE=<six-digit-secret>`
- leave `SMS_PROVIDER` empty only for this temporary mode

The placeholder above is not a usable code. Keep the actual review phone and code in the deployment secret store; never commit either value. The fixed code is accepted only for the exact configured phone. Other phone numbers receive an SMS-unavailable response and cannot sign in. Do not use a universal code for all numbers. Disable `REVIEW_ONLY_MODE` and configure the real SMS provider before a public release.
