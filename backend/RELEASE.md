# Backend release

The API Production workflow runs automatically for backend changes merged to main after the production storage cutover is complete. It performs backend vet and race tests, validates the production Compose file, builds the exact revision-tagged Docker image, and deploys it over SSH through the configured production-api Environment gate. A push before cutover reports that deployment is waiting for storage; it does not replace the running API. `workflow_dispatch` remains available for a confirmed recovery deployment.

Before the first release, provision the private AWS buckets, API CloudWatch log group, and least-privilege IAM identities; configure the host production environment file, back up PostgreSQL and existing uploads, complete the local-to-S3 migration, and verify every migrated object checksum. Set `API_LOG_GROUP` from the CloudFormation output and allow the Docker daemon to use the `ApiLogWriterPolicyArn` identity. Keep the repository Actions variable `API_STORAGE_CUTOVER_COMPLETE=false` until the storage cutover is complete, then set it to `true`.

The workflow leaves .env on the server, checks the deployed image revision, waits for /ready, and requires the public account-deletion API route to return HTTP 405 for GET. It rolls back the previous managed release if those checks fail. Set up SSH variables and secrets as listed in docs/server-run.md; never copy runtime credentials into the workflow.

Local development:

    go run ./cmd/api

Build a manual recovery image after S3 cutover:

    docker build --pull --file backend/Dockerfile --tag stroy-api:production backend

The manual recovery Compose command is documented in docs/server-run.md.
