import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/auth_repository.dart';
import 'package:online_prorab/services/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('AuthRepository verifies code, saves session and sets API token', () async {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/auth/sms/verify');
        return http.Response(jsonEncode({'access_token': 'token-123'}), 200);
      }),
    );
    final repository = AuthRepository(apiClient: apiClient, sessionStore: SessionStore());

    final session = await repository.verifyCode('+996700000000', '123456');

    expect(session.phone, '+996700000000');
    expect(session.accessToken, 'token-123');
    expect(apiClient.accessToken, 'token-123');

    final restored = await SessionStore().load();
    expect(restored, isNotNull);
    expect(restored!.accessToken, 'token-123');
  });

  test('AuthRepository restores saved session into API client', () async {
    final store = SessionStore();
    await store.save(const SessionData(phone: '+996700000000', accessToken: 'token-abc'));

    final apiClient = ApiClient(httpClient: MockClient((request) async => http.Response('{}', 200)));
    final repository = AuthRepository(apiClient: apiClient, sessionStore: store);

    final session = await repository.loadSession();

    expect(session, isNotNull);
    expect(session!.phone, '+996700000000');
    expect(apiClient.accessToken, 'token-abc');
  });

  test('AuthRepository signOut clears session and API token', () async {
    final store = SessionStore();
    await store.save(const SessionData(phone: '+996700000000', accessToken: 'token-abc'));
    final apiClient = ApiClient(httpClient: MockClient((request) async => http.Response('{}', 200)))..setAccessToken('token-abc');
    final repository = AuthRepository(apiClient: apiClient, sessionStore: store);

    await repository.signOut();

    expect(apiClient.accessToken, isNull);
    expect(await store.load(), isNull);
  });

  test('AuthRepository throws AuthException when access token is missing', () async {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    );
    final repository = AuthRepository(apiClient: apiClient, sessionStore: SessionStore());

    expect(
      () => repository.verifyCode('+996700000000', '123456'),
      throwsA(isA<AuthException>()),
    );
  });
}
