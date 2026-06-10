import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:online_prorab/services/api_config.dart';

class ApiClient {
  ApiClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  String? accessToken;

  void setAccessToken(String? token) {
    accessToken = token;
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

  Future<List<dynamic>> listProjects() async {
    final data = await getJson('/api/v1/projects');
    return data is List<dynamic> ? data : <dynamic>[];
  }

  Future<Map<String, dynamic>> createProject(String name, String address) async {
    return postJson('/api/v1/projects', {'name': name, 'address': address});
  }

  Future<Map<String, dynamic>> updateProject(String projectId, String name, String address, {String status = 'active'}) async {
    return patchJson('/api/v1/projects/$projectId', {'name': name, 'address': address, 'status': status});
  }

  Future<void> deleteProject(String projectId) async {
    await deleteJson('/api/v1/projects/$projectId');
  }

  Future<List<dynamic>> listCostItems(String projectId) async {
    final data = await getJson('/api/v1/cost-items', {'project_id': projectId});
    return data is List<dynamic> ? data : <dynamic>[];
  }

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

  Future<List<dynamic>> listDailyReports(String projectId) async {
    final data = await getJson('/api/v1/daily-reports', {'project_id': projectId});
    return data is List<dynamic> ? data : <dynamic>[];
  }

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

  Future<List<dynamic>> listTasks(String projectId) async {
    final data = await getJson('/api/v1/tasks', {'project_id': projectId});
    return data is List<dynamic> ? data : <dynamic>[];
  }

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

  Future<List<dynamic>> listFiles(String projectId) async {
    final data = await getJson('/api/v1/files', {'project_id': projectId});
    return data is List<dynamic> ? data : <dynamic>[];
  }

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

  Future<List<dynamic>> listAuditLogs(String projectId) async {
    final data = await getJson('/api/v1/audit-logs', {'project_id': projectId});
    return data is List<dynamic> ? data : <dynamic>[];
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final response = await _httpClient.post(ApiConfig.endpoint(path), headers: _headers(), body: jsonEncode(body));
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> patchJson(String path, Map<String, dynamic> body) async {
    final response = await _httpClient.patch(ApiConfig.endpoint(path), headers: _headers(), body: jsonEncode(body));
    return _decodeObject(response);
  }

  Future<dynamic> getJson(String path, [Map<String, String>? query]) async {
    final response = await _httpClient.get(ApiConfig.endpoint(path, query), headers: _headers());
    return _decodeAny(response);
  }

  Future<dynamic> deleteJson(String path) async {
    final response = await _httpClient.delete(ApiConfig.endpoint(path), headers: _headers());
    return _decodeAny(response);
  }

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
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
    final body = response.body.isEmpty ? '{}' : response.body;
    final data = jsonDecode(body);
    if (response.statusCode >= 400) {
      final message = data is Map<String, dynamic> ? data['error']?.toString() : null;
      throw ApiException(response.statusCode, message ?? 'Request failed');
    }
    return data;
  }

  void close() {
    _httpClient.close();
  }
}

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
