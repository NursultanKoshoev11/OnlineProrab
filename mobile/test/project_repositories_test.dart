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
                'budget_amount': 250000,
                'currency': 'KGS',
                'role': 'manager',
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
      expect(projects.first.budgetAmount, 250000);
      expect(projects.first.currency, 'KGS');
      expect(projects.first.role, 'manager');
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
              'receipt_file_id': 'file-1',
              'created_at': '2026-09-06T10:00:00Z',
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
    expect(items.first.receiptFileId, 'file-1');
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
              'report_date': '2026-09-05',
              'created_at': '2026-09-05T18:00:00Z',
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
    expect(reports.first.reportDate, '2026-09-05');
    expect(reports.first.createdAt, '2026-09-05T18:00:00Z');
  });

  test('TaskRepository markDone sends done status', () async {
    final task = RemoteTask(
      id: 'task-1',
      projectId: 'project-1',
      title: 'Buy cement',
      description: 'Call supplier',
      status: 'open',
      dueDate: '2026-09-10',
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
            'due_date': '2026-09-10',
          }),
          200,
        );
      }),
    );

    final updated = await TaskRepository(apiClient: apiClient).markDone(task);

    expect(updated.status, 'done');
    expect(updated.dueDate, '2026-09-10');
  });

  test('TaskRepository create sends the selected status', () async {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/tasks');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['status'], 'cancelled');
        return http.Response(
          jsonEncode({
            'id': 'task-2',
            'project_id': 'project-1',
            'title': 'Stop delivery',
            'description': '',
            'status': 'cancelled',
          }),
          201,
        );
      }),
    );

    final created = await TaskRepository(apiClient: apiClient).create(
      projectId: 'project-1',
      title: 'Stop delivery',
      status: 'cancelled',
    );

    expect(created.status, 'cancelled');
  });

  test('AuditLogRepository maps wrapped audit log responses', () async {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/v1/audit-logs');
        expect(request.url.queryParameters['project_id'], 'project-1');
        return http.Response(
          jsonEncode({
            'audit_logs': [
              {
                'id': 'log-1',
                'action': 'create',
                'entity_type': 'task',
                'entity_id': 'task-1',
                'created_at': '2026-09-06T10:00:00Z',
              },
            ],
          }),
          200,
        );
      }),
    );

    final logs = await AuditLogRepository(apiClient: apiClient).list(
      'project-1',
    );

    expect(logs.length, 1);
    expect(logs.first.action, 'create');
    expect(logs.first.entityType, 'task');
  });
}
