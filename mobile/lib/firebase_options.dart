// Firebase configuration for the STROY mobile clients.
//
// These values identify the public Firebase applications. The server-side
// service-account credential is intentionally not stored in the mobile app.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'STROY Firebase messaging is configured for Android and iOS only.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'STROY Firebase messaging is not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB6gTzwNfestKEUaYvlW7q5twoEf_FytNY',
    appId: '1:1092895503626:android:9b8a37beee1dc17715b6f3',
    messagingSenderId: '1092895503626',
    projectId: 'stroy-notifications',
    storageBucket: 'stroy-notifications.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCxlZO0TZKeG6f75QwM7_Hq18lr41Tiu8Q',
    appId: '1:1092895503626:ios:5218c2f2e8958ebe15b6f3',
    messagingSenderId: '1092895503626',
    projectId: 'stroy-notifications',
    storageBucket: 'stroy-notifications.firebasestorage.app',
    iosBundleId: 'com.koshoev.stroy',
  );
}
