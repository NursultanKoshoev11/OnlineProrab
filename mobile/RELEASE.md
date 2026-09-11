# Mobile release

Development run:
flutter run --dart-define=API_BASE_URL=http://localhost:8080

Android release:
flutter build apk --release --dart-define=API_BASE_URL=https://api.stroy.com.kg

Android app bundle:
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.stroy.com.kg

iOS release:
flutter build ipa --release --dart-define=API_BASE_URL=https://api.stroy.com.kg

Before release:
- Verify the Play Console package id matches `applicationId` in `android/app/build.gradle.kts`.
- Set final bundle id.
- Add final app icon.
- Provide a production keystore through `STROY_KEYSTORE_PATH`, `STROY_KEYSTORE_PASSWORD`, `STROY_KEY_ALIAS`, and `STROY_KEY_PASSWORD`.
- Test on real devices.
