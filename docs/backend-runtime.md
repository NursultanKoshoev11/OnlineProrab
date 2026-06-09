# Backend Runtime

Required runtime values are provided by the server environment.

Minimum values:
- APP_ENV
- HTTP_ADDR
- DATABASE_URL

Recommended checks after deploy:
- GET /health
- GET /ready
- GET /api/v1/projects

Do not commit real production secrets to GitHub.
