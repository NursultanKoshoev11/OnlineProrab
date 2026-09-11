class AppConfig {
  static const appName = 'STROY';
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.stroy.com.kg',
  );
  static const buildMode = String.fromEnvironment(
    'BUILD_MODE',
    defaultValue: 'development',
  );
}
