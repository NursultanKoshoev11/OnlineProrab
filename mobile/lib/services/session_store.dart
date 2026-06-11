import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionData {
  const SessionData({
    required this.phone,
    required this.accessToken,
    this.refreshToken = '',
  });

  final String phone;
  final String accessToken;
  final String refreshToken;

  bool get isValid => phone.isNotEmpty && accessToken.isNotEmpty;
  bool get canRefresh => refreshToken.isNotEmpty;

  SessionData copyWith({String? accessToken, String? refreshToken}) {
    return SessionData(
      phone: phone,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
    );
  }
}

abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(migrateWithBackup: true),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class SessionStore {
  SessionStore({SecureKeyValueStore? storage})
      : _storage = storage ?? FlutterSecureKeyValueStore();

  static const _phoneKey = 'online_prorab_session_phone';
  static const _accessTokenKey = 'online_prorab_access_token';
  static const _refreshTokenKey = 'online_prorab_refresh_token';

  final SecureKeyValueStore _storage;

  Future<SessionData?> load() async {
    final phone = await _storage.read(_phoneKey) ?? '';
    final accessToken = await _storage.read(_accessTokenKey) ?? '';
    final refreshToken = await _storage.read(_refreshTokenKey) ?? '';
    if (phone.isEmpty || accessToken.isEmpty) {
      return null;
    }
    return SessionData(
      phone: phone,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Future<void> save(SessionData session) async {
    if (!session.isValid) {
      throw ArgumentError('session phone and access token are required');
    }
    await _storage.write(_phoneKey, session.phone);
    await _storage.write(_accessTokenKey, session.accessToken);
    if (session.refreshToken.isEmpty) {
      await _storage.delete(_refreshTokenKey);
    } else {
      await _storage.write(_refreshTokenKey, session.refreshToken);
    }
  }

  Future<void> clear() async {
    await _storage.delete(_phoneKey);
    await _storage.delete(_accessTokenKey);
    await _storage.delete(_refreshTokenKey);
  }
}
