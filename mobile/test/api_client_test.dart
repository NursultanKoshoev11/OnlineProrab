import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:online_prorab/services/api_client.dart';

void main() {
  test('verifySMSCode stores access token from backend response', () async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/auth/sms/verify');
        return http.Response(jsonEncode({'access_token': 'token-123'}), 200);
      }),
    );

    final data = await client.verifySMSCode('+996700000000', '123456');

    expect(data['access_token'], 'token-123');
    expect(client.accessToken, 'token-123');
  });

  test('createProject sends bearer token and JSON body', () async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/projects');
        expect(request.headers['Authorization'], 'Bearer token-123');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], 'Demo');
        expect(body['address'], 'Bishkek');
        return http.Response(jsonEncode({'id': 'project-1', 'name': 'Demo'}), 201);
      }),
    )..setAccessToken('token-123');

    final data = await client.createProject('Demo', 'Bishkek');

    expect(data['id'], 'project-1');
  });

  test('ApiClient throws ApiException on backend error', () async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode({'error': 'Unauthorized'}), 401);
      }),
    );

    expect(
      () => client.listProjects(),
      throwsA(isA<ApiException>().having((error) => error.statusCode, 'statusCode', 401)),
    );
  });
}
