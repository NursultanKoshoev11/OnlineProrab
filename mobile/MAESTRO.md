# Maestro staging smoke test

The repository keeps the Maestro flow in `.maestro/staging-login.yaml`. It is
intentionally staging-only: the workflow rejects every API URL except
`https://stroy.com.kg/staging-api` and never uses the production API.

## One-time GitHub setup

Create a GitHub environment named `staging-mobile` and add these environment
secrets:

- `STAGING_TEST_PHONE`: the allowlisted staging phone in international format,
  for example `+996…`.
- `STAGING_TEST_CODE`: the six-digit staging-only code, normally `111111`.

Do not add these values to the repository, a workflow file, or an APK artifact.
The backend must have the same phone/code pair configured with
`APP_ENV=staging`; production rejects this fixed-code path.

## Run it

Open **Actions → Mobile Maestro staging smoke → Run workflow** and keep the
default API URL. The job first checks `/ready`, builds a debug APK with
`OFFLINE_DEMO=false`, starts a clean Android API 34 `pixel_2` emulator, and
runs the login-to-workspace flow with a pinned, checksum-verified Maestro CLI.
The CI job allows up to 60 minutes for the hosted emulator; the Maestro command
itself is bounded to 15 minutes so a runner hang produces a diagnostic failure.
A JUnit result artifact is retained for 14 days.

The flow deliberately stops after the authenticated workspace is visible. It
does not create projects or expenses, so repeated runs do not consume project
limits or leave test data behind. The existing Flutter integration test remains
the broader server-flow test; a separate fixture-backed Maestro flow can be
added once a disposable staging project is provisioned.
