# Local production MVP notes

This document is retained as a historical checklist. The changes below are
already part of the current repository; do not apply a second implementation.

## 1. Router

Routes for files, SMS auth and subscriptions are registered in
`backend/internal/httpapi/api_routes.go`.

Available routes include:

- `/api/v1/files`
- `/api/v1/auth/sms/request`
- `/api/v1/auth/sms/verify`
- `/api/v1/subscriptions/plans`
- `/api/v1/subscriptions/status`

## 2. Database startup

`backend/cmd/api` opens PostgreSQL and applies the embedded authoritative
migrations on startup.

## 3. Project CRUD

Project CRUD is backed by PostgreSQL and protected by authenticated project
membership checks.

## 4. Owner dashboard

The mobile workspace loads expenses, reports, tasks, files, team members and
the audit log from their current API endpoints.

## 5. Verify

Verify with:

```bash
cd backend
go test ./...
```

For a complete request sequence use `backend/SMOKE_TEST.md`.
