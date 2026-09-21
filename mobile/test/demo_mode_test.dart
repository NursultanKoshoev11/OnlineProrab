import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:online_prorab/services/demo_mode.dart';

void main() {
  test('archiving preserves project details and allows restoring', () async {
    final client = DemoHttpClient();
    addTearDown(client.close);
    final project = Uri.parse(
      'http://offline.demo/api/v1/projects/demo-project-1',
    );
    expect((await client.delete(project)).statusCode, 200);
    final active =
        jsonDecode(
              (await client.get(
                Uri.parse('http://offline.demo/api/v1/projects'),
              )).body,
            )
            as List;
    expect(active.any((p) => p['id'] == 'demo-project-1'), isFalse);
    final archived = jsonDecode((await client.get(project)).body);
    expect(archived['status'], 'archived');
    final costs =
        jsonDecode(
              (await client.get(
                Uri.parse(
                  'http://offline.demo/api/v1/cost-items?project_id=demo-project-1',
                ),
              )).body,
            )
            as List;
    expect(costs, hasLength(3));
    await client.patch(project, body: jsonEncode({'status': 'active'}));
    expect(jsonDecode((await client.get(project)).body)['status'], 'active');
  });
  test(
    'loads project details and returns 404 for an unknown project',
    () async {
      final client = DemoHttpClient();
      addTearDown(client.close);
      final response = await client.get(
        Uri.parse('http://offline.demo/api/v1/projects/demo-project-1'),
      );
      expect(response.statusCode, 200);
      expect(jsonDecode(response.body)['name'], 'Дом на Иссык-Куле');
      final missing = await client.get(
        Uri.parse('http://offline.demo/api/v1/projects/missing'),
      );
      expect(missing.statusCode, 404);
    },
  );
  test('serves seeded projects without a network connection', () async {
    final client = DemoHttpClient();
    addTearDown(client.close);

    final response = await client.get(
      Uri.parse('http://offline.demo/api/v1/projects'),
    );

    expect(response.statusCode, 200);
    final projects = jsonDecode(response.body) as List<dynamic>;
    expect(projects, hasLength(2));
    expect(projects.first['name'], 'Дом на Иссык-Куле');
  });

  test('keeps expense and report changes in memory', () async {
    final client = DemoHttpClient();
    addTearDown(client.close);

    final expense = await client.post(
      Uri.parse('http://offline.demo/api/v1/cost-items'),
      body: jsonEncode({
        'project_id': 'demo-project-1',
        'title': 'Краска',
        'amount': 12500,
        'currency': 'KGS',
        'spent_at': '2026-09-06',
      }),
    );
    final report = await client.post(
      Uri.parse('http://offline.demo/api/v1/daily-reports'),
      body: jsonEncode({
        'project_id': 'demo-project-1',
        'summary': 'Проверили офлайн-режим',
        'workers_count': 2,
        'report_date': '2026-09-06',
      }),
    );

    expect(expense.statusCode, 201);
    expect(report.statusCode, 201);

    final expenses = await client.get(
      Uri.parse(
        'http://offline.demo/api/v1/cost-items?project_id=demo-project-1',
      ),
    );
    final reports = await client.get(
      Uri.parse(
        'http://offline.demo/api/v1/daily-reports?project_id=demo-project-1',
      ),
    );

    expect(
      (jsonDecode(expenses.body) as List<dynamic>).first['title'],
      'Краска',
    );
    expect(
      (jsonDecode(reports.body) as List<dynamic>).first['summary'],
      'Проверили офлайн-режим',
    );
  });

  test('returns a local demo file for the file preview flow', () async {
    final client = DemoHttpClient();
    addTearDown(client.close);

    final response = await client.get(
      Uri.parse(
        'http://offline.demo/api/v1/files/download?file_id=demo-file-1',
      ),
    );

    expect(response.statusCode, 200);
    expect(response.headers['content-type'], 'application/pdf');
    expect(response.bodyBytes, isNotEmpty);
  });

  test('persists demo team invite and role changes', () async {
    final client = DemoHttpClient();
    addTearDown(client.close);

    final invite = await client.post(
      Uri.parse('http://offline.demo/api/v1/project-invites'),
      body: jsonEncode({
        'project_id': 'demo-project-1',
        'phone': '+996777000000',
        'role': 'worker',
      }),
    );
    expect(invite.statusCode, 200);
    expect(
      (jsonDecode(invite.body) as Map<String, dynamic>)['status'],
      'added',
    );

    final membersResponse = await client.get(
      Uri.parse(
        'http://offline.demo/api/v1/project-members?project_id=demo-project-1',
      ),
    );
    final members = jsonDecode(membersResponse.body) as List<dynamic>;
    final invited =
        members.firstWhere((item) => item['phone'] == '+996777000000')
            as Map<String, dynamic>;

    final updated = await client.patch(
      Uri.parse(
        'http://offline.demo/api/v1/project-members/${invited['user_id']}?project_id=demo-project-1',
      ),
      body: jsonEncode({'role': 'manager'}),
    );
    expect(updated.statusCode, 200);
    expect(
      (jsonDecode(updated.body) as Map<String, dynamic>)['role'],
      'manager',
    );

    final removed = await client.delete(
      Uri.parse(
        'http://offline.demo/api/v1/project-members/${invited['user_id']}?project_id=demo-project-1',
      ),
    );
    expect(removed.statusCode, 200);

    final afterRemoval = await client.get(
      Uri.parse(
        'http://offline.demo/api/v1/project-members?project_id=demo-project-1',
      ),
    );
    expect(
      (jsonDecode(afterRemoval.body) as List<dynamic>).where(
        (item) => item['user_id'] == invited['user_id'],
      ),
      isEmpty,
    );
  });
}
