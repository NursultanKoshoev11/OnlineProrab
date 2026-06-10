# Backend Smoke Test

Run the stack:

```bash
docker compose up --build
```

Health checks:

```bash
curl -i http://localhost:8080/health
curl -i http://localhost:8080/ready
```

Auth flow:

```bash
curl -s -X POST http://localhost:8080/api/v1/auth/sms/request \
  -H 'Content-Type: application/json' \
  -d '{"phone":"+996700000000"}'
```

Use the returned development code only in local development. Then verify:

```bash
curl -s -X POST http://localhost:8080/api/v1/auth/sms/verify \
  -H 'Content-Type: application/json' \
  -d '{"phone":"+996700000000","code":"123456"}'
```

Set token:

```bash
export TOKEN='PASTE_ACCESS_TOKEN_HERE'
```

Create a project:

```bash
curl -s -X POST http://localhost:8080/api/v1/projects \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"name":"Demo house","address":"Bishkek"}'
```

List projects:

```bash
curl -s http://localhost:8080/api/v1/projects \
  -H "Authorization: Bearer $TOKEN"
```

Create expense:

```bash
curl -s -X POST http://localhost:8080/api/v1/cost-items \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"project_id":"PASTE_PROJECT_ID","title":"Cement","amount":1200,"category":"materials","currency":"KGS","vendor":"Local supplier"}'
```

Create daily report:

```bash
curl -s -X POST http://localhost:8080/api/v1/daily-reports \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"project_id":"PASTE_PROJECT_ID","summary":"Foundation works completed","workers_count":4,"issues":""}'
```
