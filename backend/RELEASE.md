# Backend release

Local run:
go run ./cmd/api

Docker run:
docker compose -f docker-compose.prod.yml up --build -d

Check:
curl http://localhost:8080/health
curl http://localhost:8080/ready

Before release:
- Configure server variables outside Git.
- Apply database migrations.
- Check logs.
- Check health endpoint.
- Check ready endpoint.
