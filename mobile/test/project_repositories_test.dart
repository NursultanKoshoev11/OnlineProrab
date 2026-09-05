import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:online_prorab/features/projects/project_data_repositories.dart';
import 'package:online_prorab/features/projects/project_repository.dart';
import 'package:online_prorab/services/api_client.dart';

void main() {
  test(
    'ProjectRepository maps backend projects and filters invalid items',
    () async {
      final apiClient = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/v1/projects');
          return http.Response(
            jsonEncode([
              {
                'id': 'project-1',
                'name': 'House',
                'address': 'Bishkek',
                'status': 'active',
                'start_date': '2026-09-01',
              },
              {'id': '', 'name': 'Invalid'},
            ]),
            200,
          );
        }),
      );

      final projects = await ProjectRepository(
        apiClient: apiClient,
      ).listProjects();

      expect(projects.length, 1);
      expect(projects.first.id, 'project-1');
      expect(projects.first.name, 'House');
      expect(projects.first.startDate, '2026-09-01');
    },
  );

  test('CostItemRepository maps backend cost items', () async {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/cost-items');
        expect(request.url.queryParameters['project_id'], 'project-1');
        return http.Response(
          jsonEncode([
            {
              'id': 'cost-1',
              'project_id': 'project-1',
              'title': 'Cement',
              'amount': 1200,
              'category': 'other',
              'currency': 'KGS',
              'vendor': '',
              'spent_at': '2026-09-06',
            },
          ]),
          200,
        );
      }),
    );

    final items = await CostItemRepository(
      apiClient: apiClient,
    ).list('project-1');

    expect(items.length, 1);
    expect(items.first.amount, 1200);
    expect(items.first.currency, 'KGS');
    expect(items.first.spentAt, '2026-09-06');
  });

  test('DailyReportRepository handles numeric workers count safely', () async {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'id': 'report-1',
              'project_id': 'project-1',
              'summary': 'Work done',
              'workers_count': 4.0,
              'issues': '',
            },
          ]),
          200,
        );
      }),
    );

    final reports = await DailyReportRepository(
      apiClient: apiClient,
    ).list('project-1');

    expect(reports.length, 1);
    expect(reports.first.workersCount, 4);
  });

  test('TaskRepository markDone sends done status', () async {
    final task = RemoteTask(
      id: 'task-1',
      projectId: 'project-1',
      title: 'Buy cement',
      description: 'Call supplier',
      status: 'open',
    );
    final apiClient = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/api/v1/tasks/task-1');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['status'], 'done');
        return http.Response(
          jsonEncode({
            'id': 'task-1',
            'project_id': 'project-1',
            'title': 'Buy cement',
            'description': 'Call supplier',
            'status': 'done',
          }),
          200,
        );
      }),
    );

    final updated = await TaskRepository(apiClient: apiClient).markDone(task);

    expect(updated.status, 'done');
  });
}
