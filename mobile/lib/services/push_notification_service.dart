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
  StreamSubscription<String>? _registrationSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  bool _initialized = false;
  bool _initializing = false;

  Future<void> initializeForSession() async {
    if (_initialized || _initializing || kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    _initializing = true;
    try {
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

      // firebase_messaging 17 switched Android and iOS to Firebase
      // Installation IDs (FIDs). With the installation-ID manifest flag
      // enabled, getToken() is intentionally disabled; onRegistered is the
      // supported callback and the FCM HTTP v1 API accepts the FID directly.
      _registrationSubscription = messaging.onRegistered.listen(
        _registerRegistration,
      );
      await messaging.register();
      _messageSubscription = FirebaseMessaging.onMessage.listen((_) {
        // The existing SSE stream refreshes the open workspace immediately.
        // Foreground notification presentation is enabled above for a visible
        // system notification on both platforms.
      });
      _initialized = true;
    } catch (error, stackTrace) {
      // Push is additive: a Firebase/permission failure must not block login.
      // Keep _initialized false so a later session initialization can retry.
      debugPrint('STROY push initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      await _registrationSubscription?.cancel();
      _registrationSubscription = null;
    } finally {
      _initializing = false;
    }
  }

  Future<void> _registerRegistration(String registrationId) async {
    final value = registrationId.trim();
    if (value.isEmpty) return;
    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? 'ios'
        : 'android';
    try {
      await _apiClient.registerPushToken(value, platform);
    } catch (_) {
      // A later FID refresh will retry registration; push delivery must not
      // block authentication or workspace rendering.
    }
  }

  Future<void> dispose() async {
    await _registrationSubscription?.cancel();
    await _messageSubscription?.cancel();
  }
}
