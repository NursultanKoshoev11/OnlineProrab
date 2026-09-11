# STROY Backend Production Checklist

This checklist tracks the minimum work required before a real public release.

## Required environment variables

- `APP_ENV=production`
- `HTTP_ADDR=:8080`
- `DATABASE_URL=postgres://...`
- `JWT_SECRET=<strong random secret>`
- `ACCESS_TOKEN_TTL_MINUTES=60`
- `CORS_ALLOWED_ORIGINS=https://stroy.com.kg`
- `UPLOAD_DIR=/app/uploads`
- `MAX_UPLOAD_MB=10`

The API refuses unsafe production configuration when `APP_ENV=production` and the JWT secret is missing or still uses the default placeholder.

## Current production blockers

1. Configure durable object storage for uploaded photos, receipts and documents.
2. Add structured logs, alerting and external uptime monitoring.
3. Test PostgreSQL and upload-storage backup/restore in staging.
4. Configure the real SMS provider and complete an auth-to-project smoke test.
5. Run mobile release builds and test the full flow on real Android and iOS devices.

## Account deletion

- Authenticated app deletion: `DELETE /api/v1/account` with a Bearer token.
- Public deletion flow: `/account-deletion` sends an SMS challenge, verifies the phone, then calls the same authenticated endpoint.
- The endpoint deletes the user, owned projects, sessions, support requests, and user-uploaded files. Files are removed from storage after the transaction commits.

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
