# OnlineProrab Release Checklist

Use the [detailed release checklist](docs/RELEASE_CHECKLIST.md) for backend, Android, and iOS checks. Use the [backend production runbook](backend/PRODUCTION.md) for environment configuration, AWS S3 migration, encrypted backup/restore, account deletion, and rollback.

Do not release based on green CI alone. The staging auth-to-project flow, real-device Android and iOS checks, AWS storage migration, and a real PostgreSQL/S3 restore drill must pass before public launch. Configure live SMS credentials, external log collection, alerts, uptime monitoring, HTTPS, and the SSH website deployment secrets as described in the runbooks.
