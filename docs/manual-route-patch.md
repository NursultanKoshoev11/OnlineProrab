# Manual route patch

Add these routes locally after cloning the repo:

```go
mux.HandleFunc("/api/v1/files", Files)
mux.HandleFunc("/api/v1/auth/sms/request", RequestSMSCode)
mux.HandleFunc("/api/v1/auth/sms/verify", VerifySMSCode)
mux.HandleFunc("/api/v1/subscriptions/plans", ListPlans)
mux.HandleFunc("/api/v1/subscriptions/status", SubscriptionStatus)
```

Then run:

```bash
cd backend
go test ./...
go run ./cmd/api
```
