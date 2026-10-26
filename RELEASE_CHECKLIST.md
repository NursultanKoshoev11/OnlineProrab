# OnlineProrab Release Checklist

Use the [detailed release checklist](docs/RELEASE_CHECKLIST.md) for backend, Android, and iOS checks. Use the [backend production runbook](backend/PRODUCTION.md) for environment configuration, AWS S3 migration, encrypted backup/restore, account deletion, and rollback.

Do not release based on green CI alone. The staging auth-to-project flow, real-device Android and iOS checks, AWS storage migration, and a real PostgreSQL/S3 restore drill must pass before public launch. Configure live SMS credentials, external log collection, alerts, uptime monitoring, HTTPS, and the SSH website deployment secrets as described in the runbooks.

## Backend smoke test

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
- [ ] Upload a real file through the authenticated multipart endpoint
- [ ] Check protected file download and attached receipt flow

## Mobile readiness

- [ ] `cd mobile && flutter pub get`
- [ ] `cd mobile && flutter analyze`
- [ ] `cd mobile && flutter build apk --debug`
- [ ] `cd mobile && flutter build ios --simulator --no-codesign`
- [ ] Login screen opens
- [ ] Projects screen opens
- [ ] Project dashboard opens
- [ ] Add expense screen opens
- [ ] Add daily report screen opens
- [ ] Replace project cover from the edit screen
- [ ] Complete the auth-to-project-to-expense flow against staging
- [ ] Run Android and iOS release workflows with the correct store IDs and signing materials
- [ ] Test signed AAB/IPA on store testing tracks before public rollout
- [ ] Complete the App Store privacy details, privacy-policy URL, and support URL

## Production environment

- [ ] Set `APP_ENV=production`
- [ ] Set strong `JWT_SECRET`
- [ ] Set production `DATABASE_URL`
- [ ] Set production `CORS_ALLOWED_ORIGINS`
- [ ] Configure HTTPS and domain
- [ ] Configure PostgreSQL backups
- [ ] Configure a private AWS S3 bucket, Block Public Access, encryption, and least-privilege IAM role or credentials
- [ ] Back up the active local upload volume and database
- [ ] Stop API writes and run `storage-migrate -direction=local-to-s3`
- [ ] Verify existing object sizes/digests and test upload/download/delete against staging
- [ ] Test S3 backup/restore and `storage-migrate -direction=s3-to-local` rollback
- [ ] Configure logs and uptime monitoring
- [ ] Configure SMS provider

## Release decision

Do not mark the project as production-ready until CI is green, the smoke test passes, mobile builds, and a full auth-to-project-to-expense flow works on a real device.
