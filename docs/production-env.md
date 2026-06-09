# Production environment

Required server variables:

- APP_ENV
- HTTP_ADDR
- DATABASE_URL
- JWT_SECRET
- CORS_ALLOWED_ORIGINS

Rules:

- Do not commit real secrets.
- Store secrets in the server secret manager or CI/CD secrets.
- Use TLS for public traffic.
- Use a managed PostgreSQL database or a hardened private database host.
