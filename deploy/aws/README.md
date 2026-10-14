# OnlineProrab S3 storage

`onlineprorab-storage.yaml` provisions a private uploads bucket, a separate
private deletion-ledger bucket, and scoped IAM policies for a single
environment. Create separate stacks and bucket pairs for staging and
production. Bucket names must be globally unique, lowercase, and must not
contain dots.

The template enables all S3 Block Public Access controls, Bucket owner enforced
object ownership, SSE-S3 encryption, and HTTPS-only bucket policies. Upload
object versioning stays disabled because account deletion must permanently
remove user files. Deletion tombstones expire after `DeletionLedgerRetentionDays`
(365 days by default); set this longer than the retention of every backup copy
that may be restored. Both buckets are retained if the CloudFormation stack is
deleted or either bucket is replaced.

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
    DeletionLedgerRetentionDays=365
```

Repeat with a production stack name, `Environment=production`, and two
different globally unique bucket names. Before running the command, choose the
AWS region and replace `us-east-1` if needed.

Retrieve the stack outputs and attach `ApplicationStoragePolicyArn` to the API
workload's IAM role. For restores, attach `StorageRecoveryPolicyArn` and
`DeletionJournalReadPolicyArn` to the recovery identity. If the API runs on a
host without AWS workload identity, attach the application policy to a
dedicated IAM user instead, then store that user's access key in the host's
secret configuration. The template does not create credentials or attach
permissions to an existing principal automatically.

Configure `S3_BUCKET`, `S3_DELETION_LEDGER_BUCKET`, and `S3_REGION` from the
stack and verify the API's `/ready` endpoint before migration. Back up PostgreSQL and the existing upload
volume, stop API writes, run the checksum-verified migration described in
[`../../backend/PRODUCTION.md`](../../backend/PRODUCTION.md), and keep the
source volume until upload, download, deletion, backup, and rollback checks pass.
