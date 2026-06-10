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

1. Apply database migrations automatically or through a release script.
2. Replace placeholder SMS auth with real code generation, expiry, verification, and rate limiting.
3. Replace demo API responses with database-backed project, expense, report, file, and task handlers.
4. Add authenticated project access checks for every project-owned resource.
5. Add object storage for uploaded photos and receipts, or keep local uploads only for single-server beta testing.
6. Add structured logs and external monitoring before public launch.
7. Add backup and restore process for PostgreSQL and uploaded files.

## Local smoke test

```bash
docker compose up --build
curl http://localhost:8080/health
curl http://localhost:8080/ready
```

Expected responses:

- `/health` returns `200 OK` when the HTTP server is alive.
- `/ready` returns `200 OK` only when the database connection is healthy.
