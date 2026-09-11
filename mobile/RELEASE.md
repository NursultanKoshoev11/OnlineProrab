# Mobile release

Development run:
flutter run --dart-define=API_BASE_URL=http://localhost:8080

Android release:
STROY_APPLICATION_ID=com.example.from-play-console \\
STROY_KEYSTORE_PATH=/secure/path/stroy-upload.jks \\
STROY_KEYSTORE_PASSWORD='...' \\
STROY_KEY_ALIAS='...' \\
STROY_KEY_PASSWORD='...' \\
flutter build apk --release --dart-define=API_BASE_URL=https://api.stroy.com.kg --dart-define=OFFLINE_DEMO=false

Android app bundle:
STROY_APPLICATION_ID=com.example.from-play-console \\
STROY_KEYSTORE_PATH=/secure/path/stroy-upload.jks \\
STROY_KEYSTORE_PASSWORD='...' \\
STROY_KEY_ALIAS='...' \\
STROY_KEY_PASSWORD='...' \\
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.stroy.com.kg --dart-define=OFFLINE_DEMO=false

iOS release:
flutter build ipa --release --dart-define=API_BASE_URL=https://api.stroy.com.kg

Before release:
- Verify the Play Console package id matches `applicationId` in `android/app/build.gradle.kts`.
- Set `STROY_APPLICATION_ID` to the exact Play Console package id. Release builds fail when it is missing.
- Add final app icon.
- Provide a production keystore through `STROY_KEYSTORE_PATH`, `STROY_KEYSTORE_PASSWORD`, `STROY_KEY_ALIAS`, and `STROY_KEY_PASSWORD`.
- Confirm `targetSdk = 36` and `compileSdk = 36`.
- Test on real devices.
