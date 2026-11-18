import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app/online_prorab_redesign.dart';
import 'firebase_options.dart';
import 'services/crashlytics_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeCrashlytics();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const OnlineProrabRedesignApp());
}

Future<void> _initializeCrashlytics() async {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS)) {
    return;
  }

  final enabled = shouldEnableCrashlytics(
    isReleaseMode: kReleaseMode,
    offlineDemo: offlineDemoEnabled,
    disablePushNotifications: pushNotificationsDisabled,
  );

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(enabled);
    if (!enabled) return;

    FlutterError.onError = crashlytics.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      unawaited(crashlytics.recordError(error, stackTrace, fatal: true));
      return true;
    };
  } catch (error, stackTrace) {
    // Firebase is additive to the app. A configuration or native SDK issue
    // must not prevent the app from starting or authenticating.
    debugPrint('STROY Crashlytics initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
