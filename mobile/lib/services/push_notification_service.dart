import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:online_prorab/firebase_options.dart';
import 'package:online_prorab/services/api_client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // The OS displays notification payloads while the app is backgrounded. We
  // only initialize Firebase here so data-only messages can be handled safely
  // by a future background action without touching UI state.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class PushNotificationService {
  PushNotificationService({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  bool _initialized = false;

  Future<void> initializeForSession() async {
    if (_initialized || kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
    _tokenSubscription = messaging.onRegistered.listen(_registerToken);
    await messaging.register();
    _messageSubscription = FirebaseMessaging.onMessage.listen((_) {
      // The existing SSE stream refreshes the open workspace immediately.
      // Foreground notification presentation is enabled above for a visible
      // system notification on both platforms.
    });
    _initialized = true;
  }

  Future<void> _registerToken(String? token) async {
    final value = token?.trim() ?? '';
    if (value.isEmpty) return;
    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? 'ios'
        : 'android';
    try {
      await _apiClient.registerPushToken(value, platform);
    } catch (_) {
      // Token refresh will retry registration; push delivery must not block
      // authentication or workspace rendering.
    }
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
  }
}
