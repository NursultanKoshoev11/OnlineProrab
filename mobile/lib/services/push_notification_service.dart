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

      // Listen before requesting permission or registering. On iOS Firebase
      // can emit the FID as soon as APNs registration completes; attaching the
      // listener later can lose that first event and leave the device absent
      // from the server registry.
      _registrationSubscription = messaging.onRegistered.listen(
        _registerRegistration,
      );

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
      // On iOS, register() can race APNs registration on a fresh install, so
      // wait briefly for the APNs device token and retry the FID registration.
      await _registerWithRetry(messaging);
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

  Future<void> _registerWithRetry(FirebaseMessaging messaging) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Firebase Messaging exposes no APNs-token stream. Polling for a short
      // bounded window avoids the first-launch race without delaying login
      // indefinitely when APNs is unavailable or permission is denied.
      for (var attempt = 0; attempt < 20; attempt++) {
        try {
          final apnsToken = await messaging.getAPNSToken();
          if (apnsToken != null && apnsToken.isNotEmpty) break;
        } catch (_) {
          // register() below will surface the actionable provider error.
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }

    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await messaging.register();
        return;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    }

    Error.throwWithStackTrace(lastError!, lastStackTrace!);
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
