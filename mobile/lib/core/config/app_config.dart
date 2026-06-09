class AppConfig {
  static const appName = 'Online Prorab';
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
  static const buildMode = String.fromEnvironment(
    'BUILD_MODE',
    defaultValue: 'development',
  );
}
