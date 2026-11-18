import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:online_prorab/firebase_options.dart';
import 'package:online_prorab/services/api_client.dart';

const _disablePushNotificationsForE2E = bool.fromEnvironment(
  'DISABLE_PUSH_NOTIFICATIONS',
  defaultValue: false,
);

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
  String? _installationId;
  bool _initialized = false;
  bool _initializing = false;

  Future<void> initializeForSession() async {
    if (_disablePushNotificationsForE2E || _initializing || kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    _initializing = true;
    try {
      final firstInitialization = !_initialized;
      if (firstInitialization) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      final messaging = FirebaseMessaging.instance;
      if (firstInitialization) {
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );

        // Listen before requesting permission or registering. On iOS Firebase
        // can emit the FID as APNs registration completes.
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
        _messageSubscription = FirebaseMessaging.onMessage.listen((_) {
          // The SSE stream refreshes the open workspace immediately.
        });
        _initialized = true;
      }

      // register() emits the current FID every time. Rebind it after every
      // authenticated session so server-side delivery recovers after an API
      // outage and follows account changes on a shared device.
      await _registerWithRetry(messaging, waitForAPNs: firstInitialization);
    } catch (error, stackTrace) {
      // Push is additive: a Firebase/permission failure must not block login.
      debugPrint('STROY push initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!_initialized) {
        await _registrationSubscription?.cancel();
        _registrationSubscription = null;
        await _messageSubscription?.cancel();
        _messageSubscription = null;
      }
    } finally {
      _initializing = false;
    }
  }

  Future<void> unregisterForSession() async {
    final installationId = _installationId?.trim();
    if (!_initialized || installationId == null || installationId.isEmpty) {
      return;
    }
    try {
      await _apiClient.unregisterPushInstallationId(installationId);
    } catch (_) {
      // Logout and account deletion must continue when push cleanup is down.
    }
  }

  Future<void> _registerWithRetry(
    FirebaseMessaging messaging, {
    required bool waitForAPNs,
  }) async {
    if (waitForAPNs && defaultTargetPlatform == TargetPlatform.iOS) {
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
    _installationId = value;
    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? 'ios'
        : 'android';
    try {
      await _apiClient.registerPushInstallationId(value, platform);
    } catch (_) {
      // The next authenticated session re-registers this FID.
    }
  }

  Future<void> dispose() async {
    await _registrationSubscription?.cancel();
    await _messageSubscription?.cancel();
  }
}
