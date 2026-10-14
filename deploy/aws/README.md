# OnlineProrab S3 storage

`onlineprorab-storage.yaml` provisions private uploads, deletion-ledger, and
encrypted backup-archive buckets, plus scoped IAM policies for a single
environment. Create separate stacks and three buckets for staging and
production. Bucket names must be globally unique, lowercase, and must not
contain dots.

The template enables all S3 Block Public Access controls, Bucket owner enforced
object ownership, SSE-S3 encryption, and HTTPS-only bucket policies. Upload
object versioning stays disabled because account deletion must permanently
remove user files. The backup archive bucket has versioning enabled and expires
current snapshots after `BackupArchiveRetentionDays` (180 days by default);
noncurrent versions expire after a further 30 days. Deletion tombstones have no
expiration rule by product decision. Keeping them indefinitely ensures that
restoring even an old or separately retained backup cannot resurrect an account
or file deleted after that snapshot. Each entry contains only an account UUID or
object storage path and its deletion timestamp; it does not retain names, phone
numbers, or other profile fields. Treat the UUID and storage path as retained
personal data: the bucket is private and SSE-S3 encrypted, the API can write
tombstones but cannot read them, and only recovery operators should have read
access. The recovery policy can write only object tombstones under
`tombstones/objects/`; restore records queued file deletions there before it
removes those S3 objects. The uploads bucket aborts incomplete multipart uploads after seven
days. All three
buckets are retained if the CloudFormation stack is deleted or a bucket is
replaced.

Deploy to the intended AWS region; use that same region as the API's
`S3_REGION`. Replace the example bucket suffix with a globally unique value:

```sh
aws cloudformation deploy \
  --template-file deploy/aws/onlineprorab-storage.yaml \
  --stack-name onlineprorab-staging-storage \
  --region us-east-1 \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    Environment=staging \
    BucketName=onlineprorab-staging-uploads-unique-suffix \
    DeletionLedgerBucketName=onlineprorab-staging-deletions-unique-suffix \
    BackupArchiveBucketName=onlineprorab-staging-backups-unique-suffix \
    BackupArchiveRetentionDays=180
```

Repeat with a production stack name, `Environment=production`, and three
different globally unique bucket names. Before running the command, choose the
AWS region and replace `us-east-1` if needed.

Retrieve the stack outputs and attach `ApplicationStoragePolicyArn` to the API
workload's IAM role. Attach `BackupWriterPolicyArn` to a scheduled backup
runner and `BackupArchiveReadPolicyArn`, `StorageRecoveryPolicyArn`, and
`DeletionJournalReadPolicyArn` to a separate recovery identity. The recovery
identity can read the journal, restore uploads, and append object tombstones;
it cannot write account tombstones. If the API or
backup runner uses a host without AWS workload identity, attach only the
corresponding scoped policy to a dedicated IAM user and store its access key in
the host's secret configuration. The template does not create credentials or
attach permissions to an existing principal automatically.

Configure `S3_BUCKET`, `S3_DELETION_LEDGER_BUCKET`, `S3_BACKUP_BUCKET`, and
`S3_REGION` from the stack and verify the API's `/ready` endpoint before
migration. The repository's [`../systemd`](../systemd) units schedule encrypted
database and S3 object backups daily at 02:00 UTC. Install the runner with an
identity limited to `BackupWriterPolicyArn`, follow the host setup in
[`../../backend/PRODUCTION.md`](../../backend/PRODUCTION.md), run the service
once, and verify the encrypted archive in S3 before enabling the timer. Forward
failed-unit events to external monitoring and alert on missed daily backups.
Back up PostgreSQL and the existing upload volume, stop API writes, run the
checksum-verified migration described in
[`../../backend/PRODUCTION.md`](../../backend/PRODUCTION.md), and keep the
source volume until upload, download, deletion, backup, and rollback checks pass.
