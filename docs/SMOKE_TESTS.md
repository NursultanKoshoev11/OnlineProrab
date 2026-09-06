# OnlineProrab Smoke Tests

Run this checklist after deploying backend to staging and before any production release.

## 1. Health and readiness

- `GET /health` returns 200.
- `GET /ready` returns 200 when database is reachable.
- `GET /ready` returns non-200 when database is unavailable.

## 2. Authentication

- `POST /api/v1/auth/sms/request` with a valid phone returns 202.
- Invalid phone number returns 400.
- `POST /api/v1/auth/sms/verify` with a valid code returns a bearer access token.
- Invalid code returns 401.
- Too many invalid attempts returns 429.
- Protected endpoints reject requests without bearer token.
- Protected endpoints reject invalid or expired bearer token.

## 3. Projects

- Create project returns a project id.
- List projects returns the created project.
- Update project changes name, address or status.
- Archive project removes it from the active list.
- `include_archived=true` returns archived projects.
- Restore project returns it to the active list.
- A viewer can read the project but cannot mutate it.

## 4. Cost items

- Create cost item with project id, title, amount and currency.
- List cost items returns only items for the project.
- Update cost item changes amount/category/vendor.
- Delete cost item removes it from the list.

## 5. Daily reports

- Create daily report with summary and worker count.
- List reports returns only reports for the project.
- Update report changes summary, worker count or issues.
- Delete report removes it from the list.

## 6. Tasks

- Create task with title and description.
- List tasks returns only tasks for the project.
- Move a task to in-progress, done or cancelled.
- Cancelled tasks remain visible in their own section.
- Delete task removes it from the list.

## 7. Files and audit logs

- Upload a real receipt, photo or document through the multipart upload endpoint.
- Protected download returns the file only for a project member.
- A receipt can be attached to a cost item and remains linked after refresh.
- Deleting an attached receipt clears the link from the cost item.
- List files returns only files for the project.
- Audit log records project and related changes.

Direct file metadata creation is disabled in production.

## 8. Negative checks

- Requests with malformed JSON return 400.
- Requests for another user's project return 404 or 403.
- Unknown endpoints return 404.
- CORS allows only approved frontend origins in production.
