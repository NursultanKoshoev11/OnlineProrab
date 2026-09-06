# OnlineProrab Release Checklist

Use this checklist before every beta or production release.

## Backend

Run from `backend/`:

```bash
go mod tidy
go test ./...
go vet ./...
go build ./cmd/api
```

Backend release gates:

- Database setup works on a clean database.
- Health endpoint works.
- Readiness endpoint checks database connectivity.
- Auth flow works in staging.
- CORS is restricted for production.
- Logs do not contain private user data.
- Smoke test flow passes: auth, project, cost item, report, task, file upload and audit log.

## Mobile

Run from `mobile/`:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --dart-define=API_BASE_URL=https://your-production-api-domain
```

Mobile release gates:

- Login screen works against staging backend.
- Session restores after app restart.
- Network errors show clear user messages.
- Projects load from backend.
- Cost items, reports and tasks sync with backend.
- Project cover can be replaced from the edit screen.
- File upload and protected download work on a real device.
- APK is tested on a real Android device.

## Release decision

Ship only when:

- Backend checks are green.
- Mobile checks are green.
- Staging smoke test passes.
- Database backup and restore are tested.
- HTTPS domain is active.
- Rollback plan is ready.

## Known gaps

- Local disk uploads are suitable for a single-server beta only; production needs durable object storage.
- Staging and production runtime settings must be configured before public launch.
