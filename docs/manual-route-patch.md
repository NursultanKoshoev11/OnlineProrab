# Manual route patch

The route patch is already included in the current repository. Do not add a
second router; run the authoritative API entrypoint instead:

```bash
cd backend
go test ./...
go run ./cmd/api
```

Routes are registered in `internal/httpapi/api_routes.go`.
