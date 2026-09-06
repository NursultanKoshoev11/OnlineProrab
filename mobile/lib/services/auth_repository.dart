import 'dart:async';

import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/session_store.dart';

class AuthRepository {
  AuthRepository({
    required ApiClient apiClient,
    required SessionStore sessionStore,
  }) : _apiClient = apiClient,
       _sessionStore = sessionStore {
    _apiClient.setSessionHandlers(
      onTokensUpdated: _saveRotatedTokens,
      onSessionExpired: _handleExpiredSession,
    );
  }

  final ApiClient _apiClient;
  final SessionStore _sessionStore;
  final StreamController<void> _sessionExpiredController =
      StreamController<void>.broadcast();
  SessionData? _currentSession;

  Stream<void> get sessionExpired => _sessionExpiredController.stream;

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

  Future<String?> requestCode(String phone) async {
    final data = await _apiClient.requestSMSCode(phone);
    final devCode = data['dev_code']?.toString().trim();
    return devCode == null || devCode.isEmpty ? null : devCode;
  }

  Future<SessionData> verifyCode(String phone, String code) async {
    final data = await _apiClient.verifySMSCode(phone, code);
    final accessToken = data['access_token']?.toString() ?? '';
    if (accessToken.isEmpty) {
      throw const AuthException('Backend did not return an access token');
    }

    _apiClient.setTokens(accessToken: accessToken, refreshToken: null);
    try {
      final refreshToken = await _apiClient.createRefreshSession();
      final session = SessionData(
        phone: phone,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      _currentSession = session;
      await _sessionStore.save(session);
      return session;
    } catch (_) {
      await _clearLocalSession(notify: false);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _apiClient.logoutSession();
    await _clearLocalSession(notify: false);
  }

  Future<void> _handleExpiredSession() async {
    await _clearLocalSession(notify: true);
  }

  Future<void> _saveRotatedTokens(
    String accessToken,
    String refreshToken,
  ) async {
    final current = _currentSession;
    if (current == null) {
      await _clearLocalSession(notify: true);
      return;
    }
    final updated = current.copyWith(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    _currentSession = updated;
    await _sessionStore.save(updated);
  }

  Future<void> _clearLocalSession({required bool notify}) async {
    _currentSession = null;
    _apiClient.setTokens(accessToken: null, refreshToken: null);
    await _sessionStore.clear();
    if (notify && !_sessionExpiredController.isClosed) {
      _sessionExpiredController.add(null);
    }
  }

  Future<void> dispose() => _sessionExpiredController.close();
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
