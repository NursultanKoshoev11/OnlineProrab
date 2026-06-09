# Mobile release

Development run:
flutter run --dart-define=API_BASE_URL=http://localhost:8080

Android release:
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com

Android app bundle:
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.example.com

iOS release:
flutter build ipa --release --dart-define=API_BASE_URL=https://api.example.com

Before release:
- Set final package id.
- Set final bundle id.
- Add final app icon.
- Test on real devices.
