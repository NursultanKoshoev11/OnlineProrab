import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:online_prorab/services/api_client.dart';

void main() {
  test(
    'push registration uses Firebase Installation ID target format',
    () async {
      final client = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/push-tokens');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['installation_id'], 'Abcdefghijklmnopqrstuv');
          expect(body['target_type'], 'fid');
          expect(body['platform'], 'ios');
          return http.Response('', 204);
        }),
      )..setAccessToken('fixture-value');

      await client.registerPushInstallationId('Abcdefghijklmnopqrstuv', 'ios');
    },
  );

  test('push unregistration removes the authenticated FID', () async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/api/v1/push-tokens');
        expect(request.headers['Authorization'], 'Bearer fixture-value');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['installation_id'], 'Abcdefghijklmnopqrstuv');
        expect(body['target_type'], 'fid');
        return http.Response('', 204);
      }),
    )..setAccessToken('fixture-value');

    await client.unregisterPushInstallationId('Abcdefghijklmnopqrstuv');
  });

  test(
    'verifySMSCode stores access credential from backend response',
    () async {
      final client = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/auth/sms/verify');
          return http.Response(
            jsonEncode({'access_token': 'fixture-value'}),
            200,
          );
        }),
      );

      final data = await client.verifySMSCode('+996700000000', '123456');

      expect(data['access_token'], 'fixture-value');
      expect(client.accessToken, 'fixture-value');
    },
  );

  test('AI expense search sends parsed date bounds and search terms', () async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/expense-ai/search');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['project_id'], 'project-1');
        expect(body['query'], 'Сколько потратили на окна за май 2026?');
        expect(body['search_query'], 'окна');
        expect(body['from_date'], '2026-05-01');
        expect(body['to_date'], '2026-06-01');
        return http.Response(jsonEncode({'items': [], 'totals': {}}), 200);
      }),
    );

    await client.searchExpensesWithAI(
      projectId: 'project-1',
      query: 'Сколько потратили на окна за май 2026?',
      searchQuery: 'окна',
      fromDate: '2026-05-01',
      toDate: '2026-06-01',
    );
  });

  test(
    'createProject sends bearer header, accept header and JSON body',
    () async {
      final client = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/projects');
          expect(request.headers['Authorization'], 'Bearer fixture-value');
          expect(request.headers['Accept'], 'application/json');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['name'], 'Demo');
          expect(body['address'], 'Bishkek');
          expect(body['start_date'], '2026-09-06');
          expect(body['budget_amount'], 250000);
          expect(body['currency'], 'USD');
          return http.Response(
            jsonEncode({
              'id': 'project-1',
              'name': 'Demo',
              'start_date': '2026-09-06',
            }),
            201,
          );
        }),
      )..setAccessToken('fixture-value');

      final data = await client.createProject(
        'Demo',
        'Bishkek',
        startDate: '2026-09-06',
        budgetAmount: 250000,
        currency: 'USD',
      );

      expect(data['id'], 'project-1');
    },
  );

  test('listProjects supports wrapped items response', () async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/projects');
        return http.Response(
          jsonEncode({
            'items': [
              {'id': 'project-1'},
            ],
          }),
          200,
        );
      }),
    );

    final items = await client.listProjects();

    expect(items.length, 1);
    expect((items.first as Map<String, dynamic>)['id'], 'project-1');
  });

  test('listProjects can request archived projects', () async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.queryParameters['include_archived'], 'true');
        return http.Response('[]', 200);
      }),
    );

    final items = await client.listProjects(includeArchived: true);

    expect(items, isEmpty);
  });

  test('listTasks supports tasks wrapper response', () async {
    final client = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/tasks');
        return http.Response(
          jsonEncode({
            'tasks': [
              {'id': 'task-1'},
            ],
          }),
          200,
        );
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
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 401)
            .having((error) => error.isUnauthorized, 'isUnauthorized', isTrue),
      ),
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
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Сервер вернул некорректный ответ',
        ),
      ),
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
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 408)
            .having((error) => error.isNetworkError, 'isNetworkError', isTrue),
      ),
    );
  });

  test(
    'ApiClient converts http client errors to network ApiException',
    () async {
      final client = ApiClient(
        httpClient: MockClient((request) async {
          throw http.ClientException('offline');
        }),
      );

      expect(
        () => client.listProjects(),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'statusCode', 0)
              .having((error) => error.message, 'message', 'offline'),
        ),
      );
    },
  );

  test('encodes resource ids as single path segments', () async {
    final paths = <String>[];
    final client = ApiClient(
      httpClient: MockClient((request) async {
        paths.add(request.url.toString());
        return http.Response('{}', 200);
      }),
    );

    await client.deleteFile('a/b?c');
    await client.getProject('проект 1');

    expect(paths[0], endsWith('/api/v1/files/a%2Fb%3Fc'));
    expect(
      paths[1],
      endsWith('/api/v1/projects/%D0%BF%D1%80%D0%BE%D0%B5%D0%BA%D1%82%201'),
    );
  });

  test('patch and delete pass query parameters separately', () async {
    final urls = <Uri>[];
    final client = ApiClient(
      httpClient: MockClient((request) async {
        urls.add(request.url);
        return http.Response('{}', 200);
      }),
    );

    await client.patchJson(
      '/api/v1/project-members/u1',
      {'role': 'viewer'},
      {'project_id': 'p1'},
    );
    await client.deleteJson('/api/v1/project-members/u1', {'project_id': 'p1'});

    for (final url in urls) {
      expect(url.path, '/api/v1/project-members/u1');
      expect(url.queryParameters['project_id'], 'p1');
    }
  });

  group('subscription expiry detection', () {
    Future<bool> expires(Map<String, dynamic> body) async {
      final client = ApiClient(
        httpClient: MockClient(
          (request) async => http.Response(jsonEncode(body), 403),
        ),
      );
      var signalled = false;
      client.subscriptionExpired.listen((_) => signalled = true);
      try {
        await client.listProjects();
      } on ApiException catch (error) {
        await Future<void>.delayed(Duration.zero);
        expect(error.isSubscriptionExpired, signalled);
      }
      return signalled;
    }

    test('prefers the machine-readable code', () async {
      expect(
        await expires({'error': 'expired', 'code': 'subscription_expired'}),
        isTrue,
      );
      expect(
        await expires({
          'error': 'subscription is expired; choose a paid plan',
          'code': 'plan_limit',
        }),
        isFalse,
      );
    });

    test('falls back to the legacy English message', () async {
      expect(
        await expires({'error': 'subscription is expired; choose a paid plan'}),
        isTrue,
      );
      expect(await expires({'error': 'forbidden'}), isFalse);
    });
  });
}
