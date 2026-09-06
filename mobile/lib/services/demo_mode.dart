import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// In-memory API used only by the offline demo APK.
///
/// It intentionally speaks the same JSON contract as the real API, so every
/// screen, repository and form can be exercised without a network connection.
class DemoHttpClient extends http.BaseClient {
  DemoHttpClient() : _state = DemoDataState.seeded();

  final DemoDataState _state;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Demo client is closed');
    final response = _state.handle(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }

  @override
  void close() => _closed = true;
}

class DemoDataState {
  DemoDataState.seeded()
    : projects = [
        {
          'id': 'demo-project-1',
          'name': 'Дом на Иссык-Куле',
          'address': 'с. Бостери, Иссык-Куль',
          'status': 'active',
          'cover_file_id': '',
          'start_date': '2026-08-18',
          'budget_amount': 0,
          'currency': 'KGS',
          'role': 'owner',
        },
        {
          'id': 'demo-project-2',
          'name': 'Коттедж Ала-Арча',
          'address': 'Ала-Арча, Бишкек',
          'status': 'active',
          'cover_file_id': '',
          'start_date': '2026-07-04',
          'budget_amount': 0,
          'currency': 'KGS',
          'role': 'manager',
        },
        {
          'id': 'demo-project-3',
          'name': 'Ремонт квартиры',
          'address': 'ул. Токтогула, Бишкек',
          'status': 'archived',
          'cover_file_id': '',
          'start_date': '2026-03-12',
          'budget_amount': 0,
          'currency': 'KGS',
          'role': 'owner',
        },
      ],
      costs = [
        {
          'id': 'demo-cost-1',
          'project_id': 'demo-project-1',
          'title': 'Окна',
          'category': 'materials',
          'amount': 85000,
          'currency': 'KGS',
          'vendor': 'ОсОО «Комфорт»',
          'receipt_file_id': 'demo-file-1',
          'spent_at': '2026-09-04',
          'created_at': '2026-09-04T10:00:00Z',
        },
        {
          'id': 'demo-cost-2',
          'project_id': 'demo-project-1',
          'title': 'Цемент и песок',
          'category': 'materials',
          'amount': 24600,
          'currency': 'KGS',
          'vendor': 'Строймаркет',
          'receipt_file_id': '',
          'spent_at': '2026-09-02',
          'created_at': '2026-09-02T09:00:00Z',
        },
        {
          'id': 'demo-cost-3',
          'project_id': 'demo-project-1',
          'title': 'Доставка материалов',
          'category': 'transport',
          'amount': 7000,
          'currency': 'KGS',
          'vendor': 'Нурбек',
          'receipt_file_id': '',
          'spent_at': '2026-08-29',
          'created_at': '2026-08-29T08:00:00Z',
        },
        {
          'id': 'demo-cost-4',
          'project_id': 'demo-project-2',
          'title': 'Арматура',
          'category': 'materials',
          'amount': 56000,
          'currency': 'KGS',
          'vendor': 'Металл-Сервис',
          'receipt_file_id': '',
          'spent_at': '2026-08-20',
          'created_at': '2026-08-20T08:00:00Z',
        },
      ],
      reports = [
        {
          'id': 'demo-report-1',
          'project_id': 'demo-project-1',
          'summary': 'Установили окна на первом этаже, подготовили откосы.',
          'workers_count': 4,
          'issues': 'Нужно заказать подоконники.',
          'report_date': '2026-09-04',
          'created_at': '2026-09-04T18:00:00Z',
        },
        {
          'id': 'demo-report-2',
          'project_id': 'demo-project-1',
          'summary': 'Завершили заливку основания террасы.',
          'workers_count': 3,
          'issues': '',
          'report_date': '2026-09-03',
          'created_at': '2026-09-03T18:00:00Z',
        },
      ],
      files = [
        {
          'id': 'demo-file-1',
          'project_id': 'demo-project-1',
          'kind': 'receipt',
          'original_name': 'chek-okna.pdf',
          'content_type': 'application/pdf',
          'size_bytes': 18432,
          'created_at': '2026-09-04T10:05:00Z',
        },
        {
          'id': 'demo-file-2',
          'project_id': 'demo-project-1',
          'kind': 'document',
          'original_name': 'plan-rabot.pdf',
          'content_type': 'application/pdf',
          'size_bytes': 53248,
          'created_at': '2026-08-25T12:00:00Z',
        },
      ],
      members = [
        {
          'user_id': 'demo-user-1',
          'phone': '+996700000001',
          'name': 'Нурсултан',
          'role': 'owner',
          'created_at': '2026-08-18T08:00:00Z',
        },
        {
          'user_id': 'demo-user-2',
          'phone': '+996555123456',
          'name': 'Айбек',
          'role': 'worker',
          'created_at': '2026-08-19T08:00:00Z',
        },
      ],
      auditLogs = [
        {
          'id': 'demo-audit-1',
          'action': 'upload',
          'entity_type': 'file',
          'entity_id': 'demo-file-1',
          'created_at': '2026-09-04T10:05:00Z',
        },
        {
          'id': 'demo-audit-2',
          'action': 'create',
          'entity_type': 'cost_item',
          'entity_id': 'demo-cost-1',
          'created_at': '2026-09-04T10:00:00Z',
        },
      ];

  final List<Map<String, dynamic>> projects;
  final List<Map<String, dynamic>> costs;
  final List<Map<String, dynamic>> reports;
  final List<Map<String, dynamic>> files;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> auditLogs;
  int _sequence = 100;

  http.Response handle(http.BaseRequest request) {
    final path = request.url.path;
    final method = request.method.toUpperCase();
    final body = request is http.Request ? _decode(request.body) : <String, dynamic>{};

    if (method == 'POST' && path == '/api/v1/auth/sms/request') {
      return _json({'dev_code': '111111'});
    }
    if (method == 'POST' && path == '/api/v1/auth/sms/verify') {
      return _json({'access_token': 'demo-access-token'});
    }
    if (method == 'POST' && path == '/api/v1/auth/session') {
      return _json({'refresh_token': 'demo-refresh-token'});
    }
    if (method == 'POST' && path == '/api/v1/auth/session/logout') {
      return _json({'status': 'logged_out'});
    }

    if (path == '/api/v1/projects') {
      if (method == 'GET') {
        final includeArchived = request.url.queryParameters['include_archived'] == 'true';
        return _json(projects.where((item) => includeArchived || item['status'] != 'archived').toList());
      }
      if (method == 'POST') {
        final item = _newProject(body);
        projects.insert(0, item);
        return _json(item, status: 201);
      }
    }
    if (method == 'POST' && path == '/api/v1/projects/create-with-cover') {
      final fields = request is http.MultipartRequest
          ? Map<String, dynamic>.from(request.fields)
          : <String, dynamic>{};
      final item = _newProject(fields);
      projects.insert(0, item);
      return _json(item, status: 201);
    }
    final projectId = _idAfter(path, '/api/v1/projects/');
    if (projectId != null) {
      if (method == 'PATCH') {
        final item = _find(projects, projectId);
        if (item == null) return _notFound();
        item.addAll(body);
        return _json(item);
      }
      if (method == 'DELETE') {
        projects.removeWhere((item) => item['id'] == projectId);
        return _json({});
      }
    }

    final costProjectId = request.url.queryParameters['project_id'];
    if (path == '/api/v1/cost-items' && method == 'GET') {
      return _json(costs.where((item) => item['project_id'] == costProjectId).toList());
    }
    if (path == '/api/v1/cost-items' && method == 'POST') {
      final item = _newCost(body);
      costs.insert(0, item);
      return _json(item, status: 201);
    }
    final costId = _idAfter(path, '/api/v1/cost-items/');
    if (costId != null) {
      if (method == 'PATCH') {
        final item = _find(costs, costId);
        if (item == null) return _notFound();
        item.addAll(body);
        return _json(item);
      }
      if (method == 'DELETE') {
        costs.removeWhere((item) => item['id'] == costId);
        return _json({});
      }
    }

    final reportProjectId = request.url.queryParameters['project_id'];
    if (path == '/api/v1/daily-reports' && method == 'GET') {
      return _json(reports.where((item) => item['project_id'] == reportProjectId).toList());
    }
    if (path == '/api/v1/daily-reports' && method == 'POST') {
      final item = _newReport(body);
      reports.insert(0, item);
      return _json(item, status: 201);
    }
    final reportId = _idAfter(path, '/api/v1/daily-reports/');
    if (reportId != null) {
      if (method == 'PATCH') {
        final item = _find(reports, reportId);
        if (item == null) return _notFound();
        item.addAll(body);
        return _json(item);
      }
      if (method == 'DELETE') {
        reports.removeWhere((item) => item['id'] == reportId);
        return _json({});
      }
    }

    if (path == '/api/v1/files' && method == 'GET') {
      return _json(files.where((item) => item['project_id'] == costProjectId).toList());
    }
    if (path == '/api/v1/files' && method == 'POST') {
      final item = _newFile(body);
      files.insert(0, item);
      return _json(item, status: 201);
    }
    if (path == '/api/v1/files/upload' && method == 'POST') {
      final fields = request is http.MultipartRequest
          ? request.fields
          : <String, String>{};
      final item = _newFile({
        'project_id': fields['project_id'] ?? 'demo-project-1',
        'kind': fields['kind'] ?? 'document',
        'original_name': 'demo-upload.pdf',
        'content_type': 'application/pdf',
        'size_bytes': 24576,
      });
      files.insert(0, item);
      return _json(item, status: 201);
    }
    final fileId = _idAfter(path, '/api/v1/files/');
    if (fileId != null && method == 'DELETE') {
      files.removeWhere((item) => item['id'] == fileId);
      return _json({});
    }
    if (path == '/api/v1/files/download' && method == 'GET') {
      return http.Response.bytes(
        Uint8List.fromList(utf8.encode('%PDF-1.4\n% OnlinePRorab demo file\n')),
        200,
        headers: {
          'content-type': 'application/pdf',
          'content-disposition': 'attachment; filename="demo.pdf"',
        },
      );
    }

    if (path == '/api/v1/project-members' && method == 'GET') {
      return _json(members);
    }
    if (path == '/api/v1/project-invites' && method == 'POST') {
      final phone = body['phone']?.toString() ?? '';
      members.removeWhere((item) => item['phone'] == phone);
      members.add({
        'user_id': _nextId('user'),
        'phone': phone,
        'name': phone,
        'role': body['role']?.toString() ?? 'viewer',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      return _json({'status': 'invited', 'expires_in': 86400, 'invite_token': 'demo-invite-token'}, status: 201);
    }
    if (path.startsWith('/api/v1/project-members/') && method == 'PATCH') {
      final memberId = _idAfter(path, '/api/v1/project-members/');
      final member = memberId == null ? null : _find(members, memberId);
      if (member == null) return _notFound();
      member['role'] = body['role']?.toString() ?? member['role'];
      return _json(member);
    }
    if (path.startsWith('/api/v1/project-members/') && method == 'DELETE') {
      final memberId = _idAfter(path, '/api/v1/project-members/');
      if (memberId == null) return _notFound();
      members.removeWhere((item) => item['user_id'] == memberId);
      return _json({'status': 'removed'});
    }
    if (path == '/api/v1/audit-logs' && method == 'GET') {
      return _json(auditLogs);
    }

    return _notFound();
  }

  Map<String, dynamic> _decode(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  String? _idAfter(String path, String prefix) {
    if (!path.startsWith(prefix)) return null;
    final value = path.substring(prefix.length);
    return value.isEmpty || value.contains('/') ? null : value;
  }

  Map<String, dynamic>? _find(List<Map<String, dynamic>> items, String id) {
    for (final item in items) {
      if (item['id'] == id) return item;
    }
    return null;
  }

  Map<String, dynamic> _newProject(Map<String, dynamic> body) => {
    'id': _nextId('project'),
    'name': body['name']?.toString() ?? 'Новый объект',
    'address': body['address']?.toString() ?? '',
    'status': 'active',
    'cover_file_id': '',
    'start_date': body['start_date']?.toString() ?? '',
    'budget_amount': body['budget_amount'] ?? 0,
    'currency': body['currency']?.toString() ?? 'KGS',
    'role': 'owner',
  };

  Map<String, dynamic> _newCost(Map<String, dynamic> body) => {
    'id': _nextId('cost'),
    'project_id': body['project_id']?.toString() ?? 'demo-project-1',
    'title': body['title']?.toString() ?? '',
    'category': body['category']?.toString() ?? 'other',
    'amount': body['amount'] ?? 0,
    'currency': body['currency']?.toString() ?? 'KGS',
    'vendor': body['vendor']?.toString() ?? '',
    'receipt_file_id': body['receipt_file_id']?.toString() ?? '',
    'spent_at': body['spent_at']?.toString() ?? '',
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };

  Map<String, dynamic> _newReport(Map<String, dynamic> body) => {
    'id': _nextId('report'),
    'project_id': body['project_id']?.toString() ?? 'demo-project-1',
    'summary': body['summary']?.toString() ?? '',
    'workers_count': body['workers_count'] ?? 0,
    'issues': body['issues']?.toString() ?? '',
    'report_date': body['report_date']?.toString() ?? '',
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };

  Map<String, dynamic> _newFile(Map<String, dynamic> body) => {
    'id': _nextId('file'),
    'project_id': body['project_id']?.toString() ?? 'demo-project-1',
    'kind': body['kind']?.toString() ?? 'document',
    'original_name': body['original_name']?.toString() ?? 'demo-file.pdf',
    'content_type': body['content_type']?.toString() ?? 'application/pdf',
    'size_bytes': body['size_bytes'] ?? 24576,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };

  String _nextId(String prefix) => 'demo-$prefix-${_sequence++}';

  http.Response _json(Object value, {int status = 200}) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json'},
  );

  http.Response _notFound() => _json({'error': 'Demo route not found'}, status: 404);
}
