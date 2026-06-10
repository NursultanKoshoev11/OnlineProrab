import 'dart:async';
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

  test('createProject sends bearer token, accept header and JSON body', () async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/projects');
        expect(request.headers['Authorization'], 'Bearer token-123');
        expect(request.headers['Accept'], 'application/json');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], 'Demo');
        expect(body['address'], 'Bishkek');
        return http.Response(jsonEncode({'id': 'project-1', 'name': 'Demo'}), 201);
      }),
    )..setAccessToken('token-123');

    final data = await client.createProject('Demo', 'Bishkek');

    expect(data['id'], 'project-1');
  });

  test('listProjects supports wrapped items response', () async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/projects');
        return http.Response(jsonEncode({'items': [{'id': 'project-1'}]}), 200);
      }),
    );

    final items = await client.listProjects();

    expect(items.length, 1);
    expect((items.first as Map<String, dynamic>)['id'], 'project-1');
  });

  test('listTasks supports tasks wrapper response', () async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/tasks');
        return http.Response(jsonEncode({'tasks': [{'id': 'task-1'}]}), 200);
      }),
    );

    final items = await client.listTasks('project-1');

    expect(items.length, 1);
    expect((items.first as Map<String, dynamic>)['id'], 'task-1');
  });

  test('ApiClient throws ApiException on backend error', () async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode({'error': 'Unauthorized'}), 401);
      }),
    );

    expect(
      () => client.listProjects(),
      throwsA(isA<ApiException>().having((error) => error.statusCode, 'statusCode', 401).having((error) => error.isUnauthorized, 'isUnauthorized', isTrue)),
    );
  });

  test('ApiClient throws ApiException on invalid JSON', () async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        return http.Response('<html>bad gateway</html>', 502);
      }),
    );

    expect(
      () => client.listProjects(),
      throwsA(isA<ApiException>().having((error) => error.message, 'message', 'Backend returned invalid JSON')),
    );
  });

  test('ApiClient throws timeout ApiException', () async {
    final client = ApiClient(
      timeout: const Duration(milliseconds: 1),
      httpClient: MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response(jsonEncode([]), 200);
      }),
    );

    expect(
      () => client.listProjects(),
      throwsA(isA<ApiException>().having((error) => error.statusCode, 'statusCode', 408).having((error) => error.isNetworkError, 'isNetworkError', isTrue)),
    );
  });

  test('ApiClient converts http client errors to network ApiException', () async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        throw http.ClientException('Connection refused');
      }),
    );

    expect(
      () => client.listProjects(),
      throwsA(isA<ApiException>().having((error) => error.statusCode, 'statusCode', 0).having((error) => error.isNetworkError, 'isNetworkError', isTrue)),
    );
  });
}
