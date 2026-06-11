import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/auth_repository.dart';
import 'package:online_prorab/services/session_store.dart';

class MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test('AuthRepository verifies code and creates refresh session', () async {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/sms/verify') {
          return http.Response(jsonEncode({'access_token': 'token-123'}), 200);
        }
        if (request.url.path == '/api/v1/auth/session') {
          expect(request.headers['Authorization'], 'Bearer token-123');
          return http.Response(jsonEncode({'refresh_token': 'refresh-123'}), 201);
        }
        return http.Response(jsonEncode({'error': 'not found'}), 404);
      }),
    );
    final storage = MemorySecureStore();
    final sessionStore = SessionStore(storage: storage);
    final repository = AuthRepository(apiClient: apiClient, sessionStore: sessionStore);

    final session = await repository.verifyCode('+996700000000', '123456');

    expect(session.phone, '+996700000000');
    expect(session.accessToken, 'token-123');
    expect(session.refreshToken, 'refresh-123');
    expect(apiClient.accessToken, 'token-123');
    expect(apiClient.refreshToken, 'refresh-123');

    final restored = await SessionStore(storage: storage).load();
    expect(restored, isNotNull);
    expect(restored!.accessToken, 'token-123');
    expect(restored.refreshToken, 'refresh-123');
  });

  test('AuthRepository restores saved access and refresh tokens', () async {
    final store = SessionStore(storage: MemorySecureStore());
    await store.save(const SessionData(
      phone: '+996700000000',
      accessToken: 'token-abc',
      refreshToken: 'refresh-abc',
    ));

    final apiClient = ApiClient(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
    );
    final repository = AuthRepository(apiClient: apiClient, sessionStore: store);

    final session = await repository.loadSession();

    expect(session, isNotNull);
    expect(apiClient.accessToken, 'token-abc');
    expect(apiClient.refreshToken, 'refresh-abc');
  });

  test('AuthRepository signOut revokes session and clears secure storage', () async {
    final store = SessionStore(storage: MemorySecureStore());
    await store.save(const SessionData(
      phone: '+996700000000',
      accessToken: 'token-abc',
      refreshToken: 'refresh-abc',
    ));
    final apiClient = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/session/logout');
        return http.Response(jsonEncode({'status': 'logged_out'}), 200);
      }),
    )..setTokens(accessToken: 'token-abc', refreshToken: 'refresh-abc');
    final repository = AuthRepository(apiClient: apiClient, sessionStore: store);
    await repository.loadSession();

    await repository.signOut();

    expect(apiClient.accessToken, isNull);
    expect(apiClient.refreshToken, isNull);
    expect(await store.load(), isNull);
  });

  test('401 refreshes tokens and retries request once', () async {
    var projectRequests = 0;
    final storage = MemorySecureStore();
    final store = SessionStore(storage: storage);
    await store.save(const SessionData(
      phone: '+996700000000',
      accessToken: 'expired-access',
      refreshToken: 'refresh-old',
    ));
    final apiClient = ApiClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/v1/projects') {
          projectRequests++;
          if (projectRequests == 1) {
            expect(request.headers['Authorization'], 'Bearer expired-access');
            return http.Response(jsonEncode({'error': 'invalid token'}), 401);
          }
          expect(request.headers['Authorization'], 'Bearer access-new');
          return http.Response(jsonEncode([]), 200);
        }
        if (request.url.path == '/api/v1/auth/session/refresh') {
          return http.Response(jsonEncode({
            'access_token': 'access-new',
            'refresh_token': 'refresh-new',
          }), 200);
        }
        return http.Response(jsonEncode({'error': 'not found'}), 404);
      }),
    );
    final repository = AuthRepository(apiClient: apiClient, sessionStore: store);
    await repository.loadSession();

    final projects = await apiClient.listProjects();

    expect(projects, isEmpty);
    expect(projectRequests, 2);
    expect(apiClient.accessToken, 'access-new');
    expect(apiClient.refreshToken, 'refresh-new');
    final saved = await store.load();
    expect(saved!.accessToken, 'access-new');
    expect(saved.refreshToken, 'refresh-new');
  });

  test('AuthRepository throws AuthException when access token is missing', () async {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    );
    final repository = AuthRepository(
      apiClient: apiClient,
      sessionStore: SessionStore(storage: MemorySecureStore()),
    );

    expect(
      () => repository.verifyCode('+996700000000', '123456'),
      throwsA(isA<AuthException>()),
    );
  });
}
