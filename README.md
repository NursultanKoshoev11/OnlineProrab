# OnlineProrab

Production-ready MVP foundation for a mobile construction control platform.

OnlineProrab helps homeowners, foremen, and small construction teams control construction projects from a phone: expenses, receipts, daily reports, tasks, photos, documents, and analytics.

## Structure

```text
backend/   Go REST API for server deployment
mobile/    Flutter app for Android and iOS testing
```

## MVP scope

Core product loop:

1. SMS authentication with refresh sessions.
2. Object list, search, creation and editing.
3. Budget and multi-currency expense tracking.
4. Tasks, daily reports and project files.
5. Team roles, access checks and an action log.

## Local development

Start the backend and PostgreSQL from the repository root:

```bash
docker compose up --build
```

The API applies the authoritative embedded migrations on startup. Run the
Flutter app with the backend URL configured:

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:8080
```

Before a release, run the checks in `RELEASE_CHECKLIST.md` and complete the
production configuration in `backend/PRODUCTION.md`.
