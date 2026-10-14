# STROY Backend Production Checklist

This checklist tracks the minimum work required before a real public release.

## Required environment variables

- `APP_ENV=production`
- `HTTP_ADDR=:8080`
- `DATABASE_URL=postgres://...`
- `JWT_SECRET=<strong random secret>`
- `ACCESS_TOKEN_TTL_MINUTES=60`
- `CORS_ALLOWED_ORIGINS=https://stroy.com.kg`
- `STORAGE_DRIVER=s3`
- `S3_REGION=<bucket-region>`
- `S3_BUCKET=<private-bucket>`
- `S3_ENDPOINT=<optional-https-endpoint-for-S3-compatible-storage>`
- `S3_ACCESS_KEY_ID` and `S3_SECRET_ACCESS_KEY` (or an AWS workload identity)
- `UPLOAD_DIR=/data/uploads` (legacy volume used by the migration tool)
- `MAX_UPLOAD_MB=10`

The API refuses unsafe production configuration when `APP_ENV=production` and the JWT secret is missing or still uses the default placeholder.

## Staging environment

- Set `APP_ENV=staging` explicitly. Staging does not load values from a local `.env` file.
- Use a `DATABASE_URL` with `sslmode=verify-full`; staging rejects PostgreSQL URLs that do not verify the server certificate and hostname.
- Set `STORAGE_DRIVER=s3`, `S3_REGION`, and `S3_BUCKET`. The bucket must stay private; the API serves objects only after its existing project authorization check.
- Leave `S3_ENDPOINT` empty for AWS S3. For another S3-compatible provider, set its HTTPS endpoint, access key pair, and `S3_FORCE_PATH_STYLE` as required by that provider. The storage policy needs bucket health-check permission plus object get, put, and delete permissions. Readiness checks database and bucket availability.
- Configure bucket-side encryption and backups in the storage provider. Keep versioning disabled unless a lifecycle policy permanently removes noncurrent object versions within the account-deletion retention window; S3 delete markers alone do not erase old versions. The application never publishes object URLs or public ACLs.
- Configure `SMS_PROVIDER=twilio` or `SMS_PROVIDER=nikita` with valid provider credentials. Staging startup fails closed if SMS is unavailable.
- Keep `DEV_SMS_CODE_ENABLED`, `REVIEW_ONLY_MODE`, and `NIKITA_TEST_MODE` disabled. The staging Compose file pins them off even if the host environment tries to enable them.
- Set `CORS_ALLOWED_ORIGINS` to the exact HTTPS origins used by the staging client.

For local development, the fixed `dev_code` response is disabled by default. To opt in, set `DEV_SMS_CODE_ENABLED=true` and bind `HTTP_ADDR` to `127.0.0.1` or `localhost`.

## Current production blockers

1. Configure the private S3-compatible bucket, copy existing active files with the migration command below, and verify bucket backup/restore.
2. Add structured logs, alerting and external uptime monitoring.
3. Test PostgreSQL and upload-storage backup/restore in staging.
4. Configure the real SMS provider and complete an auth-to-project smoke test.
5. Run mobile release builds and test the full flow on real Android and iOS devices.

## File-storage migration and rollback

The API stores only the object key in PostgreSQL; public file responses continue
to pass through the authenticated API. Before cutover, set the S3 environment
values, back up PostgreSQL and the existing upload volume, and stop the API so
uploads cannot race the copy. Build the new image without starting the API, then
copy and SHA-256-verify every active file row against the private bucket:

```bash
docker compose -f backend/docker-compose.prod.yml build api
docker compose -f backend/docker-compose.prod.yml run --rm --no-deps \
  --entrypoint /app/storage-migrate api -direction=local-to-s3
```

Set `UPLOADS_VOLUME_NAME` to the exact name of the existing Docker volume if
the current deployment used a different Compose project name. The default is
`onlineprorab_uploads`; Docker must mount the same volume that currently holds
the uploads before the migration command starts.

The migration command refuses missing active source files, checks the database
size, verifies each destination object's size and digest, and keeps the local
volume unchanged. After it reports success, start the API and test a real
authenticated upload, download, and deletion in staging before production
cutover. Use the same command with `-direction=s3-to-local` to rehydrate active
objects into the mounted local volume before rolling back to a pre-S3 API image.
Keep the volume and database backups until the S3 backup/restore test and rollback
window have passed.

## Account deletion

- Authenticated app deletion: `DELETE /api/v1/account` with a Bearer token.
- Public deletion flow: `/account-deletion` sends an SMS challenge, verifies the phone, then calls the same authenticated endpoint.
- The endpoint deletes the user, owned projects, sessions, support requests, and user-uploaded files. It records storage removals in the same database transaction; a background worker deletes queued objects and retries failures with bounded exponential backoff.

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
- `REVIEW_SMS_CODE=111111`
- leave `SMS_PROVIDER` empty only for this temporary mode

The fixed code is accepted only for the exact configured phone. Other phone numbers receive an SMS-unavailable response and cannot sign in. Do not use a universal code for all numbers. Disable `REVIEW_ONLY_MODE` and configure the real SMS provider before a public release.
