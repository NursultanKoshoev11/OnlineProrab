# Local API E2E harness

The harness starts an isolated PostgreSQL 16 container and the API built from
`backend/Dockerfile`. It uses `APP_ENV=development`, local file storage, and
the existing development SMS fallback (`111111`). `E2E_TEST_MODE` is a
development-only container binding guard; it cannot pass configuration
validation in staging or production. The harness never needs an SMS, Firebase,
real bank, AWS, or production connection; local fakes stand in for Firebase
and O!Dengi.

From the repository root:

```sh
export E2E_FCM_SERVICE_ACCOUNT_JSON="$(bash backend/e2e/fake-fcm/credentials.sh)"
docker compose -f backend/e2e/docker-compose.e2e.yml up -d --build postgres api
docker compose -f backend/e2e/docker-compose.e2e.yml run --rm seed
(cd backend && go test -tags=e2e ./e2e)
docker compose -f backend/e2e/docker-compose.e2e.yml down -v
```

The API is exposed at `http://127.0.0.1:8080`. The seed creates two users and
one project for each: `+996700000001` and `+996700000002`. Both use code
`111111`; the first user is on the standard plan and the second remains on the
trial plan so subscription limits can be exercised. Payment E2E adds three
trial users on `+996700000021` through `+996700000023`.

To keep the database and uploaded files for inspection, omit `-v` when running
`down`. To collect API logs before teardown:

```sh
docker compose -f backend/e2e/docker-compose.e2e.yml logs --no-color api
```

## Push notifications

Push goes to `fake-fcm` (`backend/e2e/fake-fcm/server.py`), a recording stand-in
for Google OAuth and the FCM v1 API, through the real `FirebaseSender`. The API
reaches it via `FCM_API_BASE_URL`, which configuration validation allows only
in development. `credentials.sh` generates a throwaway service account per run;
without it push stays disabled and `TestProjectNotificationsReachAllMembers`
fails. The test shares a project between an owner, a worker and a viewer, adds
expenses as different members, and checks that every other member (and nobody
else) receives the push and the realtime event, including after a member is
removed. Recorded messages: `curl http://127.0.0.1:8090/messages`.

## O!Dengi payment tests

The API is configured with clearly marked E2E-only merchant values and sends
all O!Dengi JSON traffic to `fake-obank` (`backend/e2e/fake-obank/server.py`).
The fake verifies the HMAC-MD5 request signature, implements the exact
`createInvoice` and `statusPayment` commands used by the client, records calls,
and never contacts O!Dengi. Its payment links use the development-only
`OBANK_PAYMENT_URL_BASE_URL` override; production validation still accepts
only official O!Dengi hosts.

The payment suite covers standard monthly checkout, idempotency, five-way
concurrency, signed callbacks, wrong signature, amount/currency mismatch,
stale callback, replay idempotency, user isolation, status polling, and the
maximum yearly plan. Callback expectations are 201 for a new checkout, 200
for successful/replayed callbacks and paid status reads, 401 for bad or stale
signatures, 422 for signed order mismatches, and 404 for another user's order.

The fake bank is available at `http://127.0.0.1:8091`:

```sh
curl http://127.0.0.1:8091/calls
curl -X DELETE http://127.0.0.1:8091/calls
curl -X PUT http://127.0.0.1:8091/control/status \
  -H 'Content-Type: application/json' -d '{"status":"approved"}'
```
