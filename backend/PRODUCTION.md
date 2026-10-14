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
- `S3_BACKUP_BUCKET=<separate-private-backup-archive-bucket>` for encrypted S3 backup archives
- `BACKUP_AGE_RECIPIENTS_FILE=<public-age-recipient-list>` for encrypted S3 backups
- `BACKUP_AGE_IDENTITY_FILE=<restore-only-private-age-identity>` for encrypted restore
- AWS credentials from an IAM workload role, or `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (plus `AWS_SESSION_TOKEN` for temporary credentials)
- `UPLOAD_DIR=/data/uploads` (legacy volume used by the migration tool)
- `MAX_UPLOAD_MB=10`
- `SMS_PROVIDER=twilio` or `nikita`; supply that provider's credentials below.
- For Twilio: `TWILIO_ACCOUNT_SID`, `TWILIO_API_KEY_SID`, `TWILIO_API_KEY_SECRET`, and exactly one of `TWILIO_FROM` or `TWILIO_MESSAGING_SERVICE_SID`.
- For Nikita: `NIKITA_LOGIN`, `NIKITA_PASSWORD`, and `NIKITA_SENDER`; `NIKITA_API_URL` must be `https://smspro.nikita.kg/api/message` in staging/production.

The API refuses unsafe configuration in staging and production when the JWT secret is missing or still uses the default placeholder.
Malformed boolean/integer settings and values that overflow duration or upload-size conversions stop startup with a sanitized configuration error; the process does not panic or echo the rejected value into logs.

## Staging environment

- Set `APP_ENV=staging` explicitly. Staging does not load values from a local `.env` file.
- Use a `DATABASE_URL` with `sslmode=verify-full` in staging and production; the API rejects connections that do not verify every database host's certificate and hostname.
- Set `STORAGE_DRIVER=s3`, `S3_REGION`, `S3_BUCKET`, and `S3_DELETION_LEDGER_BUCKET` for Amazon S3. The uploads and deletion ledger buckets must be separate. The application uses AWS SDK region-based endpoints and the standard AWS credential chain; custom S3 endpoints are not supported. Prefer an IAM role for the workload. For a host without AWS workload identity, use a dedicated, least-privilege IAM access key injected through `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`; never put credentials in the image or source control. Readiness checks the database and both buckets.
- Provision separate private uploads, deletion-ledger, and backup-archive buckets per environment with [`onlineprorab-storage.yaml`](../deploy/aws/onlineprorab-storage.yaml), following [`deploy/aws/README.md`](../deploy/aws/README.md). The template enables all S3 Block Public Access settings, Bucket owner enforced object ownership, SSE-S3 encryption, and HTTPS-only bucket access, and cleanup of incomplete multipart uploads after seven days. Attach `ApplicationStoragePolicyArn` to the API role; it permits app object access, multipart aborts, and tombstone writes only. Attach `BackupWriterPolicyArn` to the scheduled backup runner, and `BackupArchiveReadPolicyArn`, `StorageRecoveryPolicyArn`, and `DeletionJournalReadPolicyArn` to a separate recovery identity. The recovery policy can append object tombstones during restore before deleting queued upload objects.
- The API serves objects only after its existing project authorization check and never publishes object URLs or public ACLs. If using SSE-KMS instead of the template's SSE-S3 default, the KMS key policy must also allow the workload principal to use the key.
- Leave S3 versioning disabled until account deletion permanently removes every noncurrent version within the applicable deletion window. S3 delete markers alone do not erase old versions. If versioning is enabled later, configure and verify a lifecycle rule that permanently expires noncurrent versions.
- Configure `SMS_PROVIDER=twilio` or `SMS_PROVIDER=nikita` with valid provider credentials. Staging startup fails closed if SMS is unavailable. In staging and production, `NIKITA_API_URL` is restricted to `https://smspro.nikita.kg/api/message`; SMS clients refuse redirects so provider secrets or login codes cannot be replayed to another host.
- Keep `DEV_SMS_CODE_ENABLED`, `REVIEW_ONLY_MODE`, and `NIKITA_TEST_MODE` disabled. The staging Compose file pins them off even if the host environment tries to enable them.
- Set `CORS_ALLOWED_ORIGINS` to the exact HTTPS origins used by the staging client.
- Set `TRUSTED_PROXY_CIDRS` to the exact IP addresses or narrow CIDRs of proxies that connect to the API container. The API trusts `X-Forwarded-For` only when `RemoteAddr` belongs to one of these networks; direct requests cannot spoof the limiter's client IP.
- SMS request quotas are 6 attempts per phone per hour, plus 30 per client IP per hour. Code verification is limited to 10 attempts per phone and 30 per client IP per 15 minutes. These counters include failed delivery/verification attempts and reserve each request before it reaches the SMS provider or code handler.
- Login abuse records retain the normalized phone number and client IP for 7 days. SMS-code records are retained until 24 hours after expiry. The API prunes these records every 6 hours in batches; a failed or timed-out cleanup is retried within 15 minutes, and a large backlog is drained over successive batches.

For local development, the fixed `dev_code` response is disabled by default. To opt in, set `DEV_SMS_CODE_ENABLED=true` and bind `HTTP_ADDR` to `127.0.0.1` or `localhost`.

## Current production blockers

1. Deploy the three-bucket private AWS S3 stack per environment with [`deploy/aws/README.md`](../deploy/aws/README.md), attach its least-privilege policies, and configure the API credentials. Back up and migrate existing uploads with the command below; retain the source volume until all active-file counts and checksums are verified.
2. Ship JSON logs to a secure external collector, configure alerts, and monitor `/health` and `/ready` externally.
3. Install and enable the daily encrypted S3 backup timer on the production runner, configure alerts for failures and missed runs, and complete a real PostgreSQL + S3 restore drill in staging with a dedicated recovery uploads bucket and database. Keep the age identity in the separate recovery secret store.
4. Configure the real SMS provider and complete an auth-to-project smoke test.
5. Run mobile release builds and test the full flow on real Android and iOS devices.
6. Keep deletion-ledger read access restricted to recovery operators, then run the S3 restore drill below to verify tombstones remove accounts, file metadata, and queued upload objects before traffic resumes.

## Application logs

- Staging and production write one JSON record per event to standard output. HTTP request records include request ID, method, path, status, response bytes, and duration; request bodies, query strings, and client IP addresses are omitted.
- Startup, SMS, storage, database, and HTTP 5xx failures use the JSON `ERROR` level with stable event names and separate fields; expected retries and partial-provider results use `WARN`. Alert rules can filter on `level` and the event name instead of parsing formatted log text.
- Development keeps readable text logs.
- Production and staging Compose rotate container logs at 10 MB per file and retain five files. Configure a secure external log collector and alert rules for sustained server errors, readiness failures, and SMS/storage errors before public launch.

## PostgreSQL and uploaded-file backups

`scripts/backup.sh` backs up PostgreSQL and the upload files. Set `APP_ENV=production`, `STORAGE_DRIVER=s3`, `S3_REGION`, `S3_BUCKET`, `S3_DELETION_LEDGER_BUCKET`, `S3_BACKUP_BUCKET`, and `BACKUP_AGE_RECIPIENTS_FILE`; the script rejects local-storage backups for staging/production. The host must have the AWS CLI, age, and AWS credentials from its standard credential chain. Attach `BackupWriterPolicyArn`, which grants read-only access to uploaded objects and write-only access under `snapshots/` in the separate archive bucket. The script writes `snapshot.tar.age`, which encrypts the database dump, file archive, and checksums to the public age recipients, then uploads only that encrypted snapshot and its manifest to a unique `s3://$S3_BACKUP_BUCKET/snapshots/<timestamp-host-pid>/` path. Keep the matching private identity only in a separate restore secret store. Plaintext staging files exist temporarily while the snapshot is assembled, so put `BACKUP_DIR` on encrypted storage with operator-only access. Local-storage backup remains an unencrypted development path. S3 lifecycle rules retain current archive snapshots for `BackupArchiveRetentionDays` (180 days by default) and expire old object versions after 30 additional days. Deletion tombstones have no expiration rule, so deleted accounts and files remain protected from resurrection by every retained backup.

The repository includes a daily systemd scheduler in [`deploy/systemd`](../deploy/systemd). It runs at 02:00 UTC with up to 30 minutes of jitter and catches up once after host downtime. The API deployment workflow installs the matching backup and path-validation scripts into each managed release so the timer follows the current release symlink. The service runs as the unprivileged `onlineprorab-backup` account, uses a private environment file, and allows writes only to its private state directory and the encrypted backup directory. Install the AWS CLI, `age`, `postgresql-client` with a `pg_dump` version compatible with the production server, `tar`, `coreutils`, and `acl` on the runner. Give that host network access to PostgreSQL and an AWS identity limited to `BackupWriterPolicyArn`; when colocating the runner with the API, use a dedicated least-privilege IAM user for the backup service instead of adding backup permissions to the API role.

Create `/etc/onlineprorab/backup.env` from [`deploy/systemd/backup.env.example`](../deploy/systemd/backup.env.example), replace all placeholders, and keep it root-owned with mode 0600. It sets `APP_ENV=production` and `STORAGE_DRIVER=s3`; set `DEPLOY_PATH` to the exact canonical API deployment root configured as `API_DEPLOY_PATH`, and set the production database URL and actual S3 bucket names from the CloudFormation outputs. Do not set `BACKUP_DIR` or `UPLOAD_DIR`; the systemd service pins these paths to its encrypted backup mount and private state directory. Include `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` only when using the dedicated IAM user; do not copy the API's broader credentials. Install the public age recipients file as root-owned and readable by the backup group. Keep the matching private age identity in a separate recovery secret store.

Create the `onlineprorab-backup` system account. Grant it search-only access to the deployment root and releases directory, then set a default read/traverse ACL on new releases so it can read the deployed scripts without joining the Docker-capable deploy group. For example, after setting `DEPLOY_PATH` to the configured root, run `setfacl -m u:onlineprorab-backup:--x "$DEPLOY_PATH" "$DEPLOY_PATH/releases"` and `setfacl -m d:u:onlineprorab-backup:r-x "$DEPLOY_PATH/releases"` before the next API deployment. Mount an encrypted filesystem at `/var/backups` before creating `/var/backups/onlineprorab`; make that directory owned by the backup account and mode 0700. Confirm `/var/backups` is a mount point and `findmnt -T /var/backups/onlineprorab` reports the intended encrypted filesystem before enabling the timer. The unit requires the mount and is skipped if `/var/backups` is not mounted. It uses `/var/lib/onlineprorab-backup/empty-uploads` only to satisfy the script's path checks because S3 mode reads uploaded files from S3. Install the two unit files from `deploy/systemd` into `/etc/systemd/system`, run `systemctl daemon-reload`, start `onlineprorab-backup.service` once, and confirm the encrypted snapshot and manifest reached the archive bucket before enabling `onlineprorab-backup.timer` with `systemctl enable --now onlineprorab-backup.timer`. Review failures with `journalctl -u onlineprorab-backup.service`; send failed-unit events to the configured external monitoring system and alert on missed daily backups. The repository does not configure a monitoring provider or credentials.

The daily timer runs online: `pg_dump` captures a consistent database snapshot, then the script syncs the S3 uploads bucket. Random upload keys and the permanent deletion journal/outbox protect deleted accounts and files from being restored during that gap. An upload committed after the database snapshot may leave an extra unreferenced object in the archive; the API cannot serve objects without matching database metadata. If an exact cross-store point-in-time archive is required, quiesce API writes and the storage-deletion worker for a manually run backup. During restore, account tombstones delete file metadata first; database deletion-outbox paths are copied into the permanent object journal and removed from S3 before the restore command succeeds. Copy completed encrypted snapshots to an independent protected location. The restore identity should not be available to the backup host; keep a recovery copy outside the deployment account and test it periodically.

Generate the private identity on the recovery system, protect it as a secret, and copy only the public recipient file to the backup host:

```bash
age-keygen -o /secure/recovery/onlineprorab-backup.agekey
age-keygen -y /secure/recovery/onlineprorab-backup.agekey \
  > /etc/onlineprorab/backup-age-recipients.txt
chmod 600 /secure/recovery/onlineprorab-backup.agekey
```

Keep old private identities until every backup encrypted to their recipients has expired. A recipient file can contain several public keys during key rotation so new snapshots remain decryptable by both recovery identities.

```bash
STORAGE_DRIVER=s3 \
APP_ENV=production \
S3_REGION=us-east-1 \
S3_BUCKET=onlineprorab-staging-uploads \
S3_DELETION_LEDGER_BUCKET=onlineprorab-staging-deletions \
S3_BACKUP_BUCKET=onlineprorab-staging-backups \
BACKUP_AGE_RECIPIENTS_FILE=/etc/onlineprorab/backup-age-recipients.txt \
BACKUP_DIR=/var/backups/onlineprorab \
UPLOAD_DIR=/tmp/onlineprorab-unused-uploads \
sh backend/scripts/backup.sh
```

Replace the example bucket names with the CloudFormation stack outputs. Restore with `CONFIRM_RESTORE=YES`, `CONFIRM_S3_TARGET_BUCKET` set to the exact `S3_BUCKET` target name, `S3_BACKUP_BUCKET`, both target bucket settings, `BACKUP_AGE_IDENTITY_FILE`, and the archive URI printed by the backup command. The typed bucket confirmation helps catch a restore pointed at the wrong uploads bucket. The restore host needs AWS CLI, age, Python 3, `psql`, and PostgreSQL client tools. It downloads and decrypts the snapshot into private staging directories, validates every tombstone from the separate ledger, restores the database and objects, deletes tombstoned S3 keys in batches, then replays account and file deletions before the API can serve traffic. Use encrypted scratch storage for temporary decrypted files. Stop every API instance and storage worker first, and use a dedicated recovery uploads bucket/database when validating a restore. Attach `BackupArchiveReadPolicyArn`, `StorageRecoveryPolicyArn`, and `DeletionJournalReadPolicyArn` to the recovery identity. Keep the API stopped while validating, then point its `S3_BUCKET` setting at the restored bucket before starting it. Existing unencrypted S3 backups require an explicit `ALLOW_UNENCRYPTED_RESTORE=YES` override and should be used only for an approved legacy recovery.

```bash
CONFIRM_RESTORE=YES \
CONFIRM_S3_TARGET_BUCKET=onlineprorab-staging-recovery \
APP_ENV=production \
STORAGE_DRIVER=s3 \
S3_REGION=us-east-1 \
S3_BUCKET=onlineprorab-staging-recovery \
S3_DELETION_LEDGER_BUCKET=onlineprorab-staging-deletions \
S3_BACKUP_BUCKET=onlineprorab-staging-backups \
BACKUP_AGE_IDENTITY_FILE=/run/secrets/onlineprorab-backup-age-identity \
UPLOAD_DIR=/tmp/onlineprorab-restore-target \
sh backend/scripts/restore.sh s3://onlineprorab-staging-backups/snapshots/20261014T120000Z-backup-host-1234/
```

## File-storage migration and rollback

The API stores only the object key in PostgreSQL; public file responses continue
to pass through the authenticated API. Before cutover, set the S3 environment
values, back up PostgreSQL and the existing upload volume, and stop the API so
uploads cannot race the copy. Build the new image without starting the API, then
copy and SHA-256-verify every active file row against the private bucket:

```bash
docker build --pull --file backend/Dockerfile --tag stroy-api:storage-migration backend
API_IMAGE=stroy-api:storage-migration docker compose --env-file /opt/stroy-api/.env -f backend/docker-compose.prod.yml run --rm --no-deps \
  --entrypoint /app/storage-migrate api -direction=local-to-s3
```

Set `UPLOADS_VOLUME_NAME` to the exact name of the existing Docker volume if
the current deployment used a different Compose project name. The default is
`onlineprorab_uploads`; Docker must mount the same volume that currently holds
the uploads before the migration command starts.

The migration command refuses missing active source files, streams each object
between stores, verifies the destination size and digest, and keeps the local
volume unchanged. It does not buffer whole objects in memory or write migration
copies to host temporary storage. It migrates historical files even when they
exceed the current API upload limit. Large objects use sequential S3 multipart
upload; one-pass requests use SigV4 `UNSIGNED-PAYLOAD`, so HTTPS-only bucket
policies are required and the completed copy is SHA-256 verified on readback.
The migration command requires AWS access to `S3_BUCKET` and the configured
`S3_DELETION_LEDGER_BUCKET` name needed to initialize the S3 client. Its
migration role needs object read/write access to the uploads bucket; it does
not write deletion tombstones. After it reports success, start the API and test
a real authenticated upload, download, and deletion in staging before
production cutover. Use the same command with `-direction=s3-to-local` to
rehydrate active objects into the mounted local volume before rolling back to a
pre-S3 API image.
Keep the volume and database backups until the S3 backup/restore test and rollback
window have passed.

## Account deletion

- Authenticated app deletion: `DELETE /api/v1/account` with a Bearer token.
- Public deletion flow: `/account-deletion` requests an SMS challenge and verifies it through `POST /api/v1/account/deletion/verify`. That endpoint does not create or update a user and does not accept project invitations; it issues a ten-minute `account:delete` token that is accepted only by the account deletion endpoint. The public flow then calls `DELETE /api/v1/account`.
- The endpoint deletes the user, owned projects, sessions, support requests, and user-uploaded files. Protected API requests verify that the account still exists, so deletion also revokes outstanding access JWTs immediately instead of waiting for token expiry. It writes an account tombstone to the separate S3 deletion ledger before committing, and S3 object deletion records a tombstone before removing the object. A background worker processes queued object deletions and retries failures with bounded exponential backoff. Restore replays ledger tombstones after snapshot data is restored and before traffic resumes, so older snapshots do not reintroduce deleted users or file metadata. Per the retention decision, tombstones do not expire so separately retained and offline backups remain covered. A tombstone keeps only an account UUID or object storage path and deletion timestamp; it contains no name, phone number, or other profile fields. Treat those identifiers as retained personal data: the API can write but cannot read the ledger, and read access stays restricted to recovery operators.

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
- `REVIEW_SMS_CODE=<six-digit-secret>`
- leave `SMS_PROVIDER` empty only for this temporary mode

The placeholder above is not a usable code. Keep the actual review phone and code in the deployment secret store; never commit either value. The fixed code is accepted only for the exact configured phone. Other phone numbers receive an SMS-unavailable response and cannot sign in. Do not use a universal code for all numbers. Disable `REVIEW_ONLY_MODE` and configure the real SMS provider before a public release.

## GitHub Actions API deployment

Backend Production Deploy is a manual workflow. It only runs from the current main revision after an explicit confirmation, backend vet/race checks, production Compose validation, and a revision-tagged image build. SSH uses a pinned known_hosts file. The deployment waits for the API container readiness check, probes the public account-deletion endpoint, and restores the prior managed release if either check fails.

Create the production-api GitHub Environment, restrict it to main, and add these variables:

- API_DEPLOY_HOST
- API_DEPLOY_USER
- API_DEPLOY_PATH
- API_DEPLOY_COMPOSE_PROJECT
- API_STORAGE_CUTOVER_COMPLETE=true, only after provisioning S3, migrating uploads, and verifying object checksums

Add Environment secrets API_DEPLOY_SSH_KEY and API_DEPLOY_KNOWN_HOSTS. Never add application runtime secrets to GitHub; the workflow reads the API .env file already on the host. The .env file must be a regular file owned by the deployment account with mode 0600 or stricter. The deploy root must already exist as a canonical directory.

The deployment account needs Docker Engine, Docker Compose v2 with support for --wait and --pull never, and Python 3 for private configuration comparison. Set API_DEPLOY_COMPOSE_PROJECT to the current API service project so Compose replaces only that service. Keep the API port bound to 127.0.0.1 behind the HTTPS reverse proxy.

Set API_STORAGE_CUTOVER_COMPLETE only after the storage deployment instructions above are complete, including database/upload backups, S3 migration, checksum verification, and a rollback procedure rehearsed in staging. The workflow does not deploy automatically on merge. In GitHub Actions, select Backend Production Deploy on main and check confirm_production_deploy.

For an existing S3-ready API container that predates the workflow, the first deployment adopts its running image as the rollback baseline. The running container must be the sole api service in the configured Compose project, and its STORAGE_DRIVER, S3_REGION, S3_BUCKET, and S3_DELETION_LEDGER_BUCKET must match the host .env settings. The deploy directory is managed by the workflow under releases/<revision> with a current symlink. Do not set the cutover variable while the active API still uses local storage.
