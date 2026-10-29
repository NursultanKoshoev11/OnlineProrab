# Security audit — 2026-10-29

## Scope

The audit covered the Go API, authentication and session handling, subscription and O!Bank payment flows, project/object authorization, file storage, realtime connections, AI-provider calls, Docker production configuration, CI/CD workflows, the public website, and production probes against `api.stroy.com.kg` and `stroy.com.kg`.

## Confirmed issue fixed

The live API had `SUBSCRIPTION_PRICE_OVERRIDE_KGS=10`, which exposed paid plans at 10 KGS. The production catalog was verified to return 3,000 KGS/month for Standard and 5,000 KGS/month for Max after the live setting was reset.

The fix is fail-closed in code:

- the override is accepted only in `APP_ENV=staging`;
- production billing ignores the override even if an old environment variable is present;
- the production Compose file no longer passes the override variable to the API;
- configuration tests cover production rejection and staging acceptance.

## Additional hardening applied

- Realtime/SSE connections are bounded to 256 total and 8 per user. Excess connections receive HTTP 429 with `Retry-After`.
- O!Bank callback and status reconciliation continue to require the configured merchant/test flag, signed callback, matching order, invoice, currency, and exact amount before activating a subscription.
- Project, file, task, expense, report, audit, and subscription routes were reviewed for authentication, subscription enforcement, and project-membership authorization.

## Verification

- `go test ./...` — passed.
- `go vet ./...` — passed.
- `govulncheck ./...` — no known vulnerabilities.
- `npm audit --omit=dev --audit-level=high` — 0 vulnerabilities.
- Live `/ready` — healthy.
- Live unauthenticated `/api/v1/projects` — HTTP 401.
- Live security headers — HSTS, `Cache-Control: no-store`, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, restrictive `Permissions-Policy`, and `Referrer-Policy: no-referrer`.

## Residual production risks requiring operational action

1. `REVIEW_ONLY_MODE=true` and a fixed review-code allowlist are still enabled on the live server. This is an intentional store-review/testing exception, but it is not safe for a public launch: anyone who obtains an allowlisted number and code can authenticate. Disable it and configure the real SMS sender before public release.
2. Firebase client API keys in `mobile/lib/firebase_options.dart` are client identifiers, not server secrets, but they must be restricted to the STROY Android/iOS apps in Firebase/Google Cloud and App Check should be enabled.
3. Production S3 bucket policy, Block Public Access, versioning, and the API IAM policy must remain restricted to the deployment role. No private AWS credentials were found in the repository.
4. Production deployment is gated by `API_STORAGE_CUTOVER_COMPLETE`; the audited code changes must be merged to `main` and deployed through the protected production workflow before they are considered permanently deployed.

No unauthenticated project-data access, cross-project object access, payment amount bypass, or callback-signature bypass was found in the audited paths.
