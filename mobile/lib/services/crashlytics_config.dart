/// Build-time switches used by Crashlytics and the offline/E2E app modes.
const offlineDemoEnabled = bool.fromEnvironment(
  'OFFLINE_DEMO',
  defaultValue: false,
);

const pushNotificationsDisabled = bool.fromEnvironment(
  'DISABLE_PUSH_NOTIFICATIONS',
  defaultValue: false,
);

/// Returns whether production Crashlytics collection is allowed for this build.
///
/// This is deliberately pure so the privacy-sensitive decision can be tested
/// without initializing Firebase or contacting a service.
bool shouldEnableCrashlytics({
  required bool isReleaseMode,
  required bool offlineDemo,
  required bool disablePushNotifications,
}) {
  return isReleaseMode && !offlineDemo && !disablePushNotifications;
}
