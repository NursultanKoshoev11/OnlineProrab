import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:online_prorab/services/api_config.dart';

class ApiClient {
  ApiClient({http.Client? httpClient, Duration timeout = const Duration(seconds: 15)})
      : _httpClient = httpClient ?? http.Client(),
        _timeout = timeout;

  final http.Client _httpClient;
  final Duration _timeout;
  String? accessToken;
  Future<void> Function()? _onUnauthorized;

  void setAccessToken(String? token) {
    accessToken = token;
  }

  void setUnauthorizedHandler(Future<void> Function()? handler) {
    _onUnauthorized = handler;
  }

  Future<Map<String, dynamic>> requestSMSCode(String phone) async {
    return postJson('/api/v1/auth/sms/request', {'phone': phone});
  }

  Future<Map<String, dynamic>> verifySMSCode(String phone, String code) async {
    final data = await postJson('/api/v1/auth/sms/verify', {'phone': phone, 'code': code});
    final token = data['access_token']?.toString();
    if (token != null && token.isNotEmpty) {
      setAccessToken(token);
    }
    return data;
  }

  Future<List<dynamic>> listProjects() async => _asList(await getJson('/api/v1/projects'));

  Future<Map<String, dynamic>> createProject(String name, String address) async {
    return postJson('/api/v1/projects', {'name': name, 'address': address});
  }

  Future<Map<String, dynamic>> updateProject(String projectId, String name, String address, {String status = 'active'}) async {
    return patchJson('/api/v1/projects/$projectId', {'name': name, 'address': address, 'status': status});
  }

  Future<void> deleteProject(String projectId) async {
    await deleteJson('/api/v1/projects/$projectId');
  }

  Future<List<dynamic>> listCostItems(String projectId) async => _asList(await getJson('/api/v1/cost-items', {'project_id': projectId}));

  Future<Map<String, dynamic>> createCostItem({
    required String projectId,
    required String title,
    required double amount,
    String category = 'other',
    String currency = 'KGS',
    String vendor = '',
  }) async {
    return postJson('/api/v1/cost-items', {
      'project_id': projectId,
      'title': title,
      'amount': amount,
      'category': category,
      'currency': currency,
      'vendor': vendor,
    });
  }

  Future<Map<String, dynamic>> updateCostItem({
    required String costItemId,
    required String title,
    required double amount,
    String category = 'other',
    String currency = 'KGS',
    String vendor = '',
  }) async {
    return patchJson('/api/v1/cost-items/$costItemId', {
      'title': title,
      'amount': amount,
      'category': category,
      'currency': currency,
      'vendor': vendor,
    });
  }

  Future<void> deleteCostItem(String costItemId) async {
    await deleteJson('/api/v1/cost-items/$costItemId');
  }

  Future<List<dynamic>> listDailyReports(String projectId) async => _asList(await getJson('/api/v1/daily-reports', {'project_id': projectId}));

  Future<Map<String, dynamic>> createDailyReport({
    required String projectId,
    required String summary,
    required int workersCount,
    String issues = '',
  }) async {
    return postJson('/api/v1/daily-reports', {
      'project_id': projectId,
      'summary': summary,
      'workers_count': workersCount,
      'issues': issues,
    });
  }

  Future<Map<String, dynamic>> updateDailyReport({
    required String reportId,
    required String summary,
    required int workersCount,
    String issues = '',
  }) async {
    return patchJson('/api/v1/daily-reports/$reportId', {
      'summary': summary,
      'workers_count': workersCount,
      'issues': issues,
    });
  }

  Future<void> deleteDailyReport(String reportId) async {
    await deleteJson('/api/v1/daily-reports/$reportId');
  }

  Future<List<dynamic>> listTasks(String projectId) async => _asList(await getJson('/api/v1/tasks', {'project_id': projectId}));

  Future<Map<String, dynamic>> createTask({
    required String projectId,
    required String title,
    String description = '',
    String status = 'open',
  }) async {
    return postJson('/api/v1/tasks', {
      'project_id': projectId,
      'title': title,
      'description': description,
      'status': status,
    });
  }

  Future<Map<String, dynamic>> updateTask({
    required String taskId,
    required String title,
    String description = '',
    String status = 'open',
  }) async {
    return patchJson('/api/v1/tasks/$taskId', {
      'title': title,
      'description': description,
      'status': status,
    });
  }

  Future<void> deleteTask(String taskId) async {
    await deleteJson('/api/v1/tasks/$taskId');
  }

  Future<List<dynamic>> listFiles(String projectId) async => _asList(await getJson('/api/v1/files', {'project_id': projectId}));

  Future<Map<String, dynamic>> createFileMetadata({
    required String projectId,
    required String kind,
    required String originalName,
    required String storagePath,
    required String contentType,
    required int sizeBytes,
  }) async {
    return postJson('/api/v1/files', {
      'project_id': projectId,
      'kind': kind,
      'original_name': originalName,
      'storage_path': storagePath,
      'content_type': contentType,
      'size_bytes': sizeBytes,
    });
  }

  Future<List<dynamic>> listAuditLogs(String projectId) async => _asList(await getJson('/api/v1/audit-logs', {'project_id': projectId}));

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final response = await _send(() => _httpClient.post(ApiConfig.endpoint(path), headers: _headers(), body: jsonEncode(body)));
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> patchJson(String path, Map<String, dynamic> body) async {
    final response = await _send(() => _httpClient.patch(ApiConfig.endpoint(path), headers: _headers(), body: jsonEncode(body)));
    return _decodeObject(response);
  }

  Future<dynamic> getJson(String path, [Map<String, String>? query]) async {
    final response = await _send(() => _httpClient.get(ApiConfig.endpoint(path, query), headers: _headers()));
    return _decodeAny(response);
  }

  Future<dynamic> deleteJson(String path) async {
    final response = await _send(() => _httpClient.delete(ApiConfig.endpoint(path), headers: _headers()));
    return _decodeAny(response);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } on TimeoutException {
      throw ApiException(408, 'Request timed out. Check your internet connection and backend status.');
    } on http.ClientException catch (error) {
      throw ApiException(0, error.message);
    }
  }

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (accessToken != null && accessToken!.isNotEmpty) 'Authorization': 'Bearer $accessToken',
    };
  }

  Map<String, dynamic> _decodeObject(http.Response response) {
    final data = _decodeAny(response);
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {'data': data};
  }

  dynamic _decodeAny(http.Response response) {
    final body = response.body.trim().isEmpty ? '{}' : response.body;
    late final dynamic data;
    try {
      data = jsonDecode(body);
    } on FormatException {
      throw ApiException(response.statusCode, 'Backend returned invalid JSON');
    }

    if (response.statusCode >= 400) {
      if (response.statusCode == 401) {
        accessToken = null;
        final handler = _onUnauthorized;
        if (handler != null) {
          unawaited(handler());
        }
      }
      final message = data is Map<String, dynamic> ? data['error']?.toString() : null;
      throw ApiException(response.statusCode, message ?? 'Request failed');
    }
    return data;
  }

  List<dynamic> _asList(dynamic data) {
    if (data is List<dynamic>) return data;
    if (data is Map<String, dynamic>) {
      for (final key in const ['items', 'data', 'results', 'projects', 'cost_items', 'daily_reports', 'tasks', 'files', 'audit_logs']) {
        final value = data[key];
        if (value is List<dynamic>) return value;
      }
    }
    return const <dynamic>[];
  }

  void close() {
    _httpClient.close();
  }
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isNetworkError => statusCode == 0 || statusCode == 408;
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
