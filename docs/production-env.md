# Production environment

Required server variables:

- APP_ENV
- HTTP_ADDR
- DATABASE_URL
- JWT_SECRET
- CORS_ALLOWED_ORIGINS
- TRUSTED_PROXY_CIDRS

Rules:

- Do not commit real secrets.
- Store secrets in the server secret manager or CI/CD secrets.
- Use TLS for public traffic.
- Use `sslmode=verify-full` for staging and production PostgreSQL connections; the API rejects unverified or plaintext database URLs.
- Use a managed PostgreSQL database or a hardened private database host.
- Set `TRUSTED_PROXY_CIDRS` to the exact source IPs or narrow CIDRs of reverse proxies that can reach the API. Do not use `0.0.0.0/0` or `::/0`; forwarded client IP headers are ignored from any untrusted source.
