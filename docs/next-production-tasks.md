# Next Production Tasks

## Implemented in the current PR stack

- Staging SMS fails closed without a real provider; provider URLs, database TLS, proxy trust, and SMS abuse limits are validated.
- Production file storage uses private AWS S3, with a checksum-verified migration tool, deletion tombstones, encrypted backups, and CI restore coverage.
- Backend production startup validates configuration, writes structured logs, checks database and S3 readiness, and shuts down gracefully.
- Android debug builds and iOS simulator builds run in CI; website account deletion and SSH deploy automation are prepared.
- Database CI covers clean installs plus upgrades from unversioned and legacy-versioned schema fixtures.

## Remaining release gates

### Infrastructure and backend

- Provision separate staging and production S3 buckets and least-privilege IAM roles; migrate existing uploads only after a database and volume backup.
- Rehearse schema and storage upgrades against a recent staging snapshot, then complete a real PostgreSQL/S3 backup and restore drill.
- Configure external log collection, alerting, and uptime monitoring for `/health` and `/ready`.
- Configure a real SMS provider and complete the auth-to-project staging smoke test.
- Confirm production HTTPS, CORS origins, database credentials, retention periods, and the rollback procedure.

### Mobile and website

- Build the signed Android App Bundle and signed iOS IPA with release credentials; test the full auth-to-project flow on real Android and iOS devices.
- Configure the GitHub Actions SSH deployment secrets and verify website deployment, including the public account-deletion page.

Do not treat passing CI or these prepared workflows as a production deployment. Use [`docs/RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md) and [`backend/PRODUCTION.md`](../backend/PRODUCTION.md) for release verification.
