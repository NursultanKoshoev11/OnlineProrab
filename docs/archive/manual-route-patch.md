# Manual route patch

> **Historical document.** Archived for reference only; it does not describe the current system or release process. See [`RELEASE_CHECKLIST.md`](../../RELEASE_CHECKLIST.md) and [`backend/PRODUCTION.md`](../../backend/PRODUCTION.md) for current guidance.

The route patch is already included in the current repository. Do not add a
second router; run the authoritative API entrypoint instead:

```bash
cd backend
go test ./...
go run ./cmd/api
```

Routes are registered in `internal/httpapi/api_routes.go`.
