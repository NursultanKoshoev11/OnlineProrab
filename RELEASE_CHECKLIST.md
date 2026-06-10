# OnlineProrab Release Checklist

## Backend readiness

- [ ] `cd backend && go mod tidy`
- [ ] `cd backend && go test ./...`
- [ ] `cd backend && go vet ./...`
- [ ] `cd backend && go build ./cmd/api`
- [ ] Start PostgreSQL and API with `docker compose up --build`
- [ ] Check `GET /health` returns 200
- [ ] Check `GET /ready` returns 200
- [ ] Check `POST /api/v1/auth/sms/request`
- [ ] Check `POST /api/v1/auth/sms/verify` returns Bearer token
- [ ] Check authenticated `POST /api/v1/projects`
- [ ] Check authenticated `GET /api/v1/projects`
- [ ] Check authenticated `POST /api/v1/cost-items`
- [ ] Check authenticated `POST /api/v1/daily-reports`
- [ ] Check authenticated file metadata endpoint

## Mobile readiness

- [ ] `cd mobile && flutter pub get`
- [ ] `cd mobile && flutter analyze`
- [ ] `cd mobile && flutter build apk --debug`
- [ ] Login screen opens
- [ ] Projects screen opens
- [ ] Project dashboard opens
- [ ] Add expense screen opens
- [ ] Add daily report screen opens
- [ ] Connect forms to backend API before external beta

## Production environment

- [ ] Set `APP_ENV=production`
- [ ] Set strong `JWT_SECRET`
- [ ] Set production `DATABASE_URL`
- [ ] Set production `CORS_ALLOWED_ORIGINS`
- [ ] Configure HTTPS and domain
- [ ] Configure PostgreSQL backups
- [ ] Configure uploaded file storage
- [ ] Configure logs and uptime monitoring
- [ ] Configure SMS provider

## Release decision

Do not mark the project as production-ready until CI is green, the smoke test passes, mobile builds, and a full auth-to-project-to-expense flow works on a real device.
