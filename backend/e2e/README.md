# Local API E2E harness

The harness starts an isolated PostgreSQL 16 container and the API built from
`backend/Dockerfile`. It uses `APP_ENV=development`, local file storage, and
the existing development SMS fallback (`111111`). `E2E_TEST_MODE` is a
development-only container binding guard; it cannot pass configuration
validation in staging or production. The harness never needs an SMS, Firebase,
bank, AWS, or production connection.

From the repository root:

```sh
docker compose -f backend/e2e/docker-compose.e2e.yml up -d --build postgres api
docker compose -f backend/e2e/docker-compose.e2e.yml run --rm seed
(cd backend && go test -tags=e2e ./e2e)
docker compose -f backend/e2e/docker-compose.e2e.yml down -v
```

The API is exposed at `http://127.0.0.1:8080`. The seed creates two users and
one project for each: `+996700000001` and `+996700000002`. Both use code
`111111`; the first user is on the standard plan and the second remains on the
trial plan so subscription limits can be exercised.

To keep the database and uploaded files for inspection, omit `-v` when running
`down`. To collect API logs before teardown:

```sh
docker compose -f backend/e2e/docker-compose.e2e.yml logs --no-color api
```
