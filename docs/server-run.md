# Server Run

## Production API deployment

The Backend Production Deploy workflow is a manual release from the current main revision. It runs backend checks, builds a revision-tagged Docker image, transfers it over SSH with strict host-key verification, waits for the API readiness check, and probes the public account-deletion route. A failed container health check or public route probe restores the previous managed release.

Prepare the API host after provisioning the private AWS S3 buckets and IAM policy, backing up PostgreSQL and uploaded files, migrating existing files to S3, and verifying their checksums. The API Compose project must publish port 8080 only on loopback and Caddy must proxy api.stroy.com.kg to 127.0.0.1:8080.

Create an API deployment root, for example /opt/stroy-api, with a host-managed .env file owned by the deployment user and mode 0600. Keep database, JWT, SMS, and AWS credentials in that file or use the host IAM role. Do not put production values in GitHub. See backend/PRODUCTION.md for required application settings and the storage cutover procedure.

Create the GitHub Environment production-api, allow deployments from main, and configure:

Variables:

- API_DEPLOY_HOST — SSH hostname for the API host.
- API_DEPLOY_USER — dedicated deployment account with Docker access.
- API_DEPLOY_PATH — existing canonical path containing .env.
- API_DEPLOY_COMPOSE_PROJECT — exact Compose project name of the API service.
- API_STORAGE_CUTOVER_COMPLETE=true — set only after S3 provisioning, upload migration, and checksum verification are complete.

Secrets:

- API_DEPLOY_SSH_KEY — dedicated SSH private key.
- API_DEPLOY_KNOWN_HOSTS — independently verified host-key entries.

Install Docker Engine, Docker Compose v2 with support for --wait and --pull never, and Python 3 on the host. The deployment account must own the deployment root and .env; .env must have no group or other permissions. The current Compose project must have exactly one API container and use the same S3 region, uploads bucket, and deletion-ledger bucket as .env.

In GitHub Actions, select Backend Production Deploy, select main, and check the confirmation input. The workflow refuses stale revisions, unconfigured environments, and releases before S3 cutover confirmation. It does not deploy on pull requests or automatically on merge.

## Backend checks

For a local development API, run:

    cd backend
    go run ./cmd/api

The production container image is built from backend/Dockerfile. For a manual recovery release from a trusted checkout after completing the storage cutover:

    cd backend
    docker build --pull --file Dockerfile --tag stroy-api:production .
    API_IMAGE=stroy-api:production docker compose --env-file /opt/stroy-api/.env -f docker-compose.prod.yml up --detach --no-build --pull never --wait api

Check local API health:

    curl http://127.0.0.1:8080/health
    curl http://127.0.0.1:8080/ready

The public release probe expects GET https://api.stroy.com.kg/api/v1/account/deletion/verify to return 405 Method Not Allowed. This checks that the route is deployed without submitting a deletion request.

Keep production values out of GitHub and source control. Use the host environment file or AWS workload identity for runtime credentials.