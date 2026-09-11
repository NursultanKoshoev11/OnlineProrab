# Mobile release

Development run:
flutter run --dart-define=API_BASE_URL=http://localhost:8080

Android release:
flutter build apk --release --dart-define=API_BASE_URL=https://stroy.com.kg

Android app bundle:
flutter build appbundle --release --dart-define=API_BASE_URL=https://stroy.com.kg

iOS release:
flutter build ipa --release --dart-define=API_BASE_URL=https://stroy.com.kg

Before release:
- Set final package id.
- Set final bundle id.
- Add final app icon.
- Test on real devices.
