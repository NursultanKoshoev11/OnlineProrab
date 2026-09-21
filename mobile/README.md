# STROY mobile

Flutter construction-project workspace, redesigned from the supplied OnlineProrab archive.

## Run

```powershell
flutter pub get
flutter run -d emulator-5556 --dart-define=OFFLINE_DEMO=true
```

The demo uses seeded, in-memory projects and expenses. Changes reset when the process restarts. The default build uses the live API configured through `API_BASE_URL` (default: `https://api.stroy.com.kg`). No backend source was included.

## Checks

```powershell
flutter analyze --no-pub
flutter test --no-pub
flutter drive --no-pub -d emulator-5556 --driver=test_driver/design_driver.dart --target=integration_test/offline_design_test.dart --dart-define=OFFLINE_DEMO=true
```

The emulator test writes screenshots to `evidence/`. See `QA_REPORT.md` for the completed run and its limitations, `DESIGN_NOTES.md` for visual decisions, and `ARCHIVE_REPAIR.md` for extraction recovery and compatibility changes. The original ZIP was not modified.
