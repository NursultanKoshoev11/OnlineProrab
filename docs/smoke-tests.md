# Smoke Tests

Run after backend deploy:

```bash
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl http://localhost:8080/api/v1/projects
curl http://localhost:8080/api/v1/cost-items
curl http://localhost:8080/api/v1/daily-reports
```

Expected result: API returns JSON and does not crash.
