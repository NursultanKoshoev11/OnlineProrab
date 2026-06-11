import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/session_store.dart';

class AuthRepository {
  AuthRepository({required ApiClient apiClient, required SessionStore sessionStore})
      : _apiClient = apiClient,
        _sessionStore = sessionStore {
    _apiClient.setUnauthorizedHandler(_clearExpiredSession);
  }

  final ApiClient _apiClient;
  final SessionStore _sessionStore;

  Future<SessionData?> loadSession() async {
    final session = await _sessionStore.load();
    if (session != null) {
      _apiClient.setAccessToken(session.accessToken);
    }
    return session;
  }

  Future<void> requestCode(String phone) async {
    await _apiClient.requestSMSCode(phone);
  }

  Future<SessionData> verifyCode(String phone, String code) async {
    final data = await _apiClient.verifySMSCode(phone, code);
    final accessToken = data['access_token']?.toString() ?? '';
    if (accessToken.isEmpty) {
      throw const AuthException('Backend did not return an access token');
    }
    final session = SessionData(phone: phone, accessToken: accessToken);
    await _sessionStore.save(session);
    _apiClient.setAccessToken(accessToken);
    return session;
  }

  Future<void> signOut() async {
    await _clearExpiredSession();
  }

  Future<void> _clearExpiredSession() async {
    _apiClient.setAccessToken(null);
    await _sessionStore.clear();
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
