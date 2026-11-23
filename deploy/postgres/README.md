# Production PostgreSQL

Production runs `postgres:16-alpine` as the `stroy-postgres` container on the
`stroy_default` network (aliases `stroy-postgres` and `postgres`), with data in
the `stroy_postgres_data` volume and no published ports. It was created by
Compose project `stroy` from an old copy of `deploy/docker-compose.staging.yml`
with `/opt/projects/OnlineProrab/.env.staging`; recreating it from that
directory is not reproducible, so treat the container as hand-managed until it
is moved to a dedicated Compose file.

Configuration lives inside the data directory:

- `postgresql.auto.conf`: `ssl = on`, `ssl_cert_file = onlineprorab-server.crt`,
  `ssl_key_file = onlineprorab-server.key` (certificate SANs `stroy-postgres`
  and `postgres`; clients use `sslmode=verify-full`).
- `pg_hba.conf`: trust for local socket and loopback, `host all all all
  scram-sha-256` for the network.
- Defaults otherwise: `max_connections=100`, `shared_buffers=128MB`,
  `wal_level=replica`, `archive_mode=off`.

Backups: encrypted `pg_dump` plus S3 snapshot every six hours
(`deploy/systemd`). There is no WAL archiving yet, so point-in-time recovery
is not available.

## Known follow-ups

- Change the network rule to `hostssl` so a client cannot fall back to an
  unencrypted connection.
- Enable WAL archiving to S3 (for example WAL-G) for point-in-time recovery.
