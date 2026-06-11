import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/session_store.dart';

class AuthRepository {
  AuthRepository({required ApiClient apiClient, required SessionStore sessionStore})
      : _apiClient = apiClient,
        _sessionStore = sessionStore {
    _apiClient.setSessionHandlers(
      onTokensUpdated: _saveRotatedTokens,
      onSessionExpired: _clearLocalSession,
    );
  }

  final ApiClient _apiClient;
  final SessionStore _sessionStore;
  SessionData? _currentSession;

  Future<SessionData?> loadSession() async {
    final session = await _sessionStore.load();
    _currentSession = session;
    if (session != null) {
      _apiClient.setTokens(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
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

    _apiClient.setAccessToken(accessToken);
    final refreshToken = await _apiClient.createRefreshSession();
    final session = SessionData(
      phone: phone,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    _currentSession = session;
    await _sessionStore.save(session);
    return session;
  }

  Future<void> signOut() async {
    await _apiClient.logoutSession();
    await _clearLocalSession();
  }

  Future<void> _saveRotatedTokens(
    String accessToken,
    String refreshToken,
  ) async {
    final current = _currentSession;
    if (current == null) {
      await _clearLocalSession();
      return;
    }
    final updated = current.copyWith(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    _currentSession = updated;
    await _sessionStore.save(updated);
  }

  Future<void> _clearLocalSession() async {
    _currentSession = null;
    _apiClient.setTokens(accessToken: null, refreshToken: null);
    await _sessionStore.clear();
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
