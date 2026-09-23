# STROY design and Android verification

Verified on 21 September 2026 using Flutter 3.44.9 / Dart 3.12.2.

## Results

| Check | Result |
|---|---|
| Flutter static analysis, including legacy screens | No issues |
| Unit and widget suite | 52 tests passed |
| Android 14 AVD, 1080 × 2400 at 420 dpi | Full offline flow passed |
| Same AVD, 1080 × 1920 at 480 dpi (360 × 640 dp) | Full offline flow passed |
| Compact Android login and invalid-phone feedback | Passed |
| ARM64 and x86-64 demo debug APK builds | Passed |

The full device flow covers project search and clearing, empty search, archived projects, project creation, archiving and restoration, project overview, expense search and clearing, expense creation with keyboard interaction, PDF preview, team navigation and returning between screens. Screenshots were captured on the AVD and inspected for layout and legibility. No Flutter layout overflow or app crash was observed in the completed flows.

## Fixes found during verification

- Added the missing demo project-detail route, removing the spurious load-error banner.
- Made demo archiving preserve projects and expenses so restoration works.
- Made all expense fields scroll above the keyboard while keeping Save accessible.
- Added clear-search controls that dismiss keyboard focus and reset the filter.
- Replaced a PDF table label containing a missing font glyph and aligned its green with the app palette.
- Updated the workspace app-bar title to follow the selected section.

The original ZIP is intact. Some working files were zero-filled during the initial extraction; direct ZIP reads recovered them. See ARCHIVE_REPAIR.md for the corrected recovery record and compatibility changes.

## Evidence

`evidence/01-projects.png` through `10-projects-final.png` show the standard device flow. The `compact-` screenshots show the smaller viewport, including `compact-11-login.png` and `compact-12-login-validation.png`. Test logs are saved in the same folder.

## Scope

Project and expense device checks use the existing in-memory demo API. Live SMS, production backend/realtime behavior, real file uploads, microphone recognition, payments and physical-device performance were not verified. Demo edits reset on process restart. The delivered APK is an offline debug preview, not a signed production release.

The original Pixel AVD ran out of installation storage. A separate `STROY_Review_API34` AVD was used for the completed checks; its normal display settings were restored and the demo was left open. A temporary unresponsive preview-system AVD created during setup was removed.

## Reproduce

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter drive --no-pub -d emulator-5556 --driver=test_driver/design_driver.dart --target=integration_test/offline_design_test.dart --dart-define=OFFLINE_DEMO=true
```

For compact screenshots, set the AVD to 1080 × 1920 at 480 dpi and set `SCREENSHOT_PREFIX=compact-` in the driver environment. Restore the size and density afterwards. Run `integration_test/login_design_test.dart` without `OFFLINE_DEMO` for the local phone-validation check; it does not send an SMS request.
