# Server Run

## Backend

```bash
cd backend
docker compose -f docker-compose.prod.yml up -d --build
```

## Checks

```bash
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl http://localhost:8080/api/v1/projects
```

## Notes

Keep real production values outside GitHub.
Use server environment variables for database and external services.
