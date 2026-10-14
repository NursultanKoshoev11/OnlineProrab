# Backend Runtime

Required runtime values are provided by the server environment.

Minimum values:
- APP_ENV
- HTTP_ADDR
- DATABASE_URL
- TRUSTED_PROXY_CIDRS in staging and production

Recommended checks after deploy:
- GET /health
- GET /ready
- GET /api/v1/projects

Do not commit real production secrets to GitHub.
Trust forwarded client IP headers only from the explicit reverse proxy addresses configured in `TRUSTED_PROXY_CIDRS`.
