# Local production MVP patch

The GitHub connector can block router and auth updates. Apply these files locally.

## 1. Router

Update `backend/internal/httpapi/router.go` and add routes for files, SMS auth, and subscriptions.

Required routes:

- `/api/v1/files`
- `/api/v1/auth/sms/request`
- `/api/v1/auth/sms/verify`
- `/api/v1/subscriptions/plans`
- `/api/v1/subscriptions/status`

## 2. Database startup

Update `backend/cmd/api/main.go` so it opens PostgreSQL when `DATABASE_URL` is set.

## 3. Project CRUD

Replace demo project responses with PostgreSQL repository calls.

## 4. Owner dashboard

Add `/api/v1/projects/{id}/dashboard` after project storage works.

## 5. Verify

Run:

```bash
cd backend
go test ./...