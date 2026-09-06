# OnlineProrab Backend Production Checklist

This checklist tracks the minimum work required before a real public release.

## Required environment variables

- `APP_ENV=production`
- `HTTP_ADDR=:8080`
- `DATABASE_URL=postgres://...`
- `JWT_SECRET=<strong random secret>`
- `ACCESS_TOKEN_TTL_MINUTES=60`
- `CORS_ALLOWED_ORIGINS=https://your-domain.example`
- `UPLOAD_DIR=/app/uploads`
- `MAX_UPLOAD_MB=10`

The API refuses unsafe production configuration when `APP_ENV=production` and the JWT secret is missing or still uses the default placeholder.

## Current production blockers

1. Configure durable object storage for uploaded photos, receipts and documents.
2. Add structured logs, alerting and external uptime monitoring.
3. Test PostgreSQL and upload-storage backup/restore in staging.
4. Configure the real SMS provider and complete an auth-to-project smoke test.
5. Run mobile release builds and test the full flow on real Android and iOS devices.

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
