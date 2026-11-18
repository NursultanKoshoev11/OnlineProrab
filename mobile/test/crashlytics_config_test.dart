import 'package:flutter_test/flutter_test.dart';
import 'package:online_prorab/services/crashlytics_config.dart';

void main() {
  group('shouldEnableCrashlytics', () {
    test('enables only for a real release build', () {
      expect(
        shouldEnableCrashlytics(
          isReleaseMode: true,
          offlineDemo: false,
          disablePushNotifications: false,
        ),
        isTrue,
      );
    });

    test('disables debug, offline demo, and E2E builds', () {
      const cases = [
        (
          isReleaseMode: false,
          offlineDemo: false,
          disablePushNotifications: false,
        ),
        (
          isReleaseMode: true,
          offlineDemo: true,
          disablePushNotifications: false,
        ),
        (
          isReleaseMode: true,
          offlineDemo: false,
          disablePushNotifications: true,
        ),
      ];

      for (final values in cases) {
        expect(
          shouldEnableCrashlytics(
            isReleaseMode: values.isReleaseMode,
            offlineDemo: values.offlineDemo,
            disablePushNotifications: values.disablePushNotifications,
          ),
          isFalse,
        );
      }
    });
  });
}
