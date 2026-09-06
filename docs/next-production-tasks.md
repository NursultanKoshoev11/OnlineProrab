# Next Production Tasks

The MVP loop is now wired end-to-end: PostgreSQL migrations, SMS auth with
refresh sessions, project CRUD, roles, expenses, receipts, reports, tasks,
files, audit logs and the redesigned mobile screens are in the repository.

## Backend

- Move file storage from local disk to durable object storage.
- Add structured logs, metrics, alerting and external uptime monitoring.
- Add automated PostgreSQL and object-storage backup/restore checks.
- Add report export after the core staging flow is stable.

## Mobile

- Run release builds and the full auth-to-project flow on real Android and iOS
  devices.
- Add offline/read-only cache and an explicit sync state if field connectivity
  requires it.

## Deployment

- Configure the real SMS provider, HTTPS domain and production CORS origins.
- Run clean-database and upgrade-from-existing-database migration checks in
  staging.
- Complete the smoke test and document the rollback procedure.
