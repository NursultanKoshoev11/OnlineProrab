# STROY Backend Production Checklist

This checklist tracks the minimum work required before a real public release.

## Required environment variables

- `APP_ENV=production`
- `HTTP_ADDR=:8080`
- `DATABASE_URL=postgres://...?sslmode=verify-full`
- `JWT_SECRET=<strong random secret>`
- `ACCESS_TOKEN_TTL_MINUTES=60`
- `CORS_ALLOWED_ORIGINS=https://stroy.com.kg`
- `TRUSTED_PROXY_CIDRS=<reverse proxy source IP or narrow CIDR>`
- `STORAGE_DRIVER=s3`
- `S3_REGION=<bucket-region>`
- `S3_BUCKET=<private-bucket>`
- `S3_DELETION_LEDGER_BUCKET=<separate-private-bucket>`
- AWS credentials from an IAM workload role, or `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (plus `AWS_SESSION_TOKEN` for temporary credentials)
- `UPLOAD_DIR=/data/uploads` (legacy volume used by the migration tool)
- `MAX_UPLOAD_MB=10`

The API refuses unsafe configuration in staging and production when the JWT secret is missing or still uses the default placeholder.

## Staging environment

- Set `APP_ENV=staging` explicitly. Staging does not load values from a local `.env` file.
- Use a `DATABASE_URL` with `sslmode=verify-full` in staging and production; the API rejects connections that do not verify every database host's certificate and hostname.
- Set `STORAGE_DRIVER=s3`, `S3_REGION`, `S3_BUCKET`, and `S3_DELETION_LEDGER_BUCKET` for Amazon S3. The uploads and deletion ledger buckets must be separate. The application uses AWS SDK region-based endpoints and the standard AWS credential chain; custom S3 endpoints are not supported. Prefer an IAM role for the workload. For a host without AWS workload identity, use a dedicated, least-privilege IAM access key injected through `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`; never put credentials in the image or source control. Readiness checks the database and both buckets.
- Provision one private uploads bucket and one private deletion-ledger bucket per environment with [`onlineprorab-storage.yaml`](../deploy/aws/onlineprorab-storage.yaml), following [`deploy/aws/README.md`](../deploy/aws/README.md). The template enables all S3 Block Public Access settings, Bucket owner enforced object ownership, SSE-S3 encryption, and HTTPS-only bucket access. Attach `ApplicationStoragePolicyArn` to the API role; it permits app object access and tombstone writes only.
- The API serves objects only after its existing project authorization check and never publishes object URLs or public ACLs. If using SSE-KMS instead of the template's SSE-S3 default, the KMS key policy must also allow the workload principal to use the key.
- Leave S3 versioning disabled until account deletion permanently removes every noncurrent version within the applicable deletion window. S3 delete markers alone do not erase old versions. If versioning is enabled later, configure and verify a lifecycle rule that permanently expires noncurrent versions.
- Configure `SMS_PROVIDER=twilio` or `SMS_PROVIDER=nikita` with valid provider credentials. Staging startup fails closed if SMS is unavailable.
- Keep `DEV_SMS_CODE_ENABLED`, `REVIEW_ONLY_MODE`, and `NIKITA_TEST_MODE` disabled. The staging Compose file pins them off even if the host environment tries to enable them.
- Set `CORS_ALLOWED_ORIGINS` to the exact HTTPS origins used by the staging client.
- Set `TRUSTED_PROXY_CIDRS` to the exact IP addresses or narrow CIDRs of proxies that connect to the API container. The API trusts `X-Forwarded-For` only when `RemoteAddr` belongs to one of these networks; direct requests cannot spoof the limiter's client IP.
- SMS request quotas are 6 attempts per phone per hour, plus 30 per client IP per hour. Code verification is limited to 10 attempts per phone and 30 per client IP per 15 minutes. These counters include failed delivery/verification attempts and reserve each request before it reaches the SMS provider or code handler.

For local development, the fixed `dev_code` response is disabled by default. To opt in, set `DEV_SMS_CODE_ENABLED=true` and bind `HTTP_ADDR` to `127.0.0.1` or `localhost`.

## Current production blockers

1. Deploy one private AWS S3 stack per environment with [`deploy/aws/README.md`](../deploy/aws/README.md), attach its least-privilege policy, and configure the API credentials. Back up and migrate existing uploads with the command below; retain the source volume until all active-file counts and checksums are verified.
2. Ship JSON logs to a secure external collector, configure alerts, and monitor `/health` and `/ready` externally.
3. Run a real PostgreSQL + S3 backup/restore drill in staging with a dedicated recovery bucket and database; store backup archives on encrypted, independently protected storage.
4. Configure the real SMS provider and complete an auth-to-project smoke test.
5. Run mobile release builds and test the full flow on real Android and iOS devices.
6. Set deletion-ledger retention longer than every restorable database or object backup, then run the S3 restore drill below to verify tombstones remove accounts and file metadata before traffic resumes.

## Application logs

- Staging and production write one JSON record per event to standard output. HTTP request records include request ID, method, path, status, response bytes, and duration; request bodies, query strings, and client IP addresses are omitted.
- Development keeps readable text logs.
- Production and staging Compose rotate container logs at 10 MB per file and retain five files. Configure a secure external log collector and alert rules for sustained server errors, readiness failures, and SMS/storage errors before public launch.

## PostgreSQL and uploaded-file backups

`scripts/backup.sh` backs up PostgreSQL and the upload files. Set `STORAGE_DRIVER=s3`, `S3_REGION`, and `S3_BUCKET` to include S3 objects; the host must have the AWS CLI and AWS credentials from its standard credential chain. S3 backup needs `s3:ListBucket` and `s3:GetObject` on the uploads bucket. Local-storage backup continues to archive `UPLOAD_DIR`.

Quiesce API writes and the storage-deletion worker for the duration of a backup so the database dump and object archive describe one point in time. Put `BACKUP_DIR` on encrypted storage with access restricted to operators, and copy completed archives to an independent protected location. Archives contain user files and database data; the script protects local file permissions and verifies SHA-256 checksums, but does not encrypt the archive itself.

```bash
STORAGE_DRIVER=s3 \
S3_REGION=us-east-1 \
S3_BUCKET=onlineprorab-staging-uploads \
S3_DELETION_LEDGER_BUCKET=onlineprorab-staging-deletions \
BACKUP_DIR=/var/backups/onlineprorab \
UPLOAD_DIR=/tmp/onlineprorab-unused-uploads \
sh backend/scripts/backup.sh
```

Replace both example bucket names with the CloudFormation stack outputs. Set deletion-ledger retention longer than the retention of every backup copy that may be restored. Restore with `CONFIRM_RESTORE=YES`, both bucket settings, and the snapshot directory. The restore host needs AWS CLI, Python 3, `psql`, and PostgreSQL client tools. It downloads and validates every tombstone from the separate ledger, restores the database and objects, deletes tombstoned S3 keys in batches, then replays account and file deletions before the API can serve traffic. Stop every API instance and storage worker first, and use a dedicated recovery uploads bucket/database when validating a restore. Attach `StorageRecoveryPolicyArn` to the restore identity for the target uploads bucket and `DeletionJournalReadPolicyArn` for reading the ledger. Keep the API stopped while validating, then point its `S3_BUCKET` setting at the restored bucket before starting it.

```bash
CONFIRM_RESTORE=YES \
STORAGE_DRIVER=s3 \
S3_REGION=us-east-1 \
S3_BUCKET=onlineprorab-staging-recovery \
S3_DELETION_LEDGER_BUCKET=onlineprorab-staging-deletions \
UPLOAD_DIR=/tmp/onlineprorab-restore-target \
sh backend/scripts/restore.sh /var/backups/onlineprorab/20261014T120000Z
```

## File-storage migration and rollback

The API stores only the object key in PostgreSQL; public file responses continue
to pass through the authenticated API. Before cutover, set the S3 environment
values, back up PostgreSQL and the existing upload volume, and stop the API so
uploads cannot race the copy. Build the new image without starting the API, then
copy and SHA-256-verify every active file row against the private bucket:

```bash
docker compose -f backend/docker-compose.prod.yml build api
docker compose -f backend/docker-compose.prod.yml run --rm --no-deps \
  --entrypoint /app/storage-migrate api -direction=local-to-s3
```

Set `UPLOADS_VOLUME_NAME` to the exact name of the existing Docker volume if
the current deployment used a different Compose project name. The default is
`onlineprorab_uploads`; Docker must mount the same volume that currently holds
the uploads before the migration command starts.

The migration command refuses missing active source files, checks the database
size, verifies each destination object's size and digest, and keeps the local
volume unchanged. After it reports success, start the API and test a real
authenticated upload, download, and deletion in staging before production
cutover. Use the same command with `-direction=s3-to-local` to rehydrate active
objects into the mounted local volume before rolling back to a pre-S3 API image.
Keep the volume and database backups until the S3 backup/restore test and rollback
window have passed.

## Account deletion

- Authenticated app deletion: `DELETE /api/v1/account` with a Bearer token.
- Public deletion flow: `/account-deletion` requests an SMS challenge and verifies it through `POST /api/v1/account/deletion/verify`. That endpoint does not create or update a user and does not accept project invitations; it issues a ten-minute `account:delete` token that is accepted only by the account deletion endpoint. The public flow then calls `DELETE /api/v1/account`.
- The endpoint deletes the user, owned projects, sessions, support requests, and user-uploaded files. It writes an account tombstone to the separate S3 deletion ledger before committing, and S3 object deletion records a tombstone before removing the object. A background worker processes queued object deletions and retries failures with bounded exponential backoff. Restore replays ledger tombstones after snapshot data is restored and before traffic resumes, so older snapshots do not reintroduce deleted users or file metadata. Keep ledger retention longer than all database/object backup copies that may be restored.

## Local smoke test

Run this from the repository root; the root compose file starts the API and PostgreSQL services.

```bash
docker compose up --build
curl http://localhost:8080/health
curl http://localhost:8080/ready
```

Expected responses:

- `/health` returns `200 OK` when the HTTP server is alive.
- `/ready` returns `200 OK` only when the database connection is healthy.

## Support integrations

Support tickets are always stored in PostgreSQL. Delivery to Telegram and WhatsApp is optional until the provider credentials are configured.

- `SUPPORT_TELEGRAM_BOT_TOKEN`
- `SUPPORT_TELEGRAM_CHAT_ID`
- `SUPPORT_TELEGRAM_URL` (optional deep link shown in the app)
- `SUPPORT_WHATSAPP_ACCESS_TOKEN`
- `SUPPORT_WHATSAPP_PHONE_NUMBER_ID`
- `SUPPORT_WHATSAPP_TO`
- `SUPPORT_WHATSAPP_URL` (optional deep link shown in the app)

Inject these values through the deployment secret store or environment, never commit them to Git. Until a channel is configured, `POST /api/v1/support/tickets` returns `delivery_status=not_configured` while preserving the ticket for later processing.


## Temporary Google Play review-only mode

Until the SMS provider is connected, closed testing can use a single dedicated review phone:

- `APP_ENV=production`
- `REVIEW_ONLY_MODE=true`
- `REVIEW_SMS_PHONE=+996...`
- `REVIEW_SMS_CODE=111111`
- leave `SMS_PROVIDER` empty only for this temporary mode

The fixed code is accepted only for the exact configured phone. Other phone numbers receive an SMS-unavailable response and cannot sign in. Do not use a universal code for all numbers. Disable `REVIEW_ONLY_MODE` and configure the real SMS provider before a public release.
