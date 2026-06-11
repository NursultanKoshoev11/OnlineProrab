import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:online_prorab/services/api_config.dart';

class ApiClient {
  ApiClient({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 15),
  })  : _httpClient = httpClient ?? http.Client(),
        _timeout = timeout;

  final http.Client _httpClient;
  final Duration _timeout;

  String? accessToken;
  String? refreshToken;
  Future<void> Function(String accessToken, String refreshToken)?
      _onTokensUpdated;
  Future<void> Function()? _onSessionExpired;
  Future<bool>? _refreshInFlight;

  void setAccessToken(String? token) => accessToken = token;

  void setTokens({String? accessToken, String? refreshToken}) {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  void setSessionHandlers({
    Future<void> Function(String accessToken, String refreshToken)?
        onTokensUpdated,
    Future<void> Function()? onSessionExpired,
  }) {
    _onTokensUpdated = onTokensUpdated;
    _onSessionExpired = onSessionExpired;
  }

  Future<Map<String, dynamic>> requestSMSCode(String phone) =>
      _postJson('/api/v1/auth/sms/request', {'phone': phone}, retry: false);

  Future<Map<String, dynamic>> verifySMSCode(String phone, String code) async {
    final data = await _postJson(
      '/api/v1/auth/sms/verify',
      {'phone': phone, 'code': code},
      retry: false,
    );
    final token = data['access_token']?.toString() ?? '';
    if (token.isNotEmpty) accessToken = token;
    return data;
  }

  Future<String> createRefreshSession({String deviceName = 'mobile'}) async {
    final data = await _postJson(
      '/api/v1/auth/session',
      {'device_name': deviceName},
      retry: false,
    );
    final token = data['refresh_token']?.toString() ?? '';
    if (token.isEmpty) {
      throw const ApiException(500, 'Backend did not return a refresh token');
    }
    refreshToken = token;
    return token;
  }

  Future<void> logoutSession() async {
    final token = refreshToken;
    if (token != null && token.isNotEmpty) {
      try {
        await _postJson(
          '/api/v1/auth/session/logout',
          {'refresh_token': token},
          retry: false,
          includeBearer: false,
        );
      } catch (_) {
        // Local logout must still complete when the server is unavailable.
      }
    }
    await _expireSession();
  }

  Future<List<dynamic>> listProjects() async =>
      _asList(await getJson('/api/v1/projects'));

  Future<Map<String, dynamic>> createProject(String name, String address) =>
      postJson('/api/v1/projects', {'name': name, 'address': address});

  Future<Map<String, dynamic>> updateProject(
    String projectId,
    String name,
    String address, {
    String status = 'active',
  }) =>
      patchJson('/api/v1/projects/$projectId', {
        'name': name,
        'address': address,
        'status': status,
      });

  Future<void> deleteProject(String projectId) async {
    await deleteJson('/api/v1/projects/$projectId');
  }

  Future<List<dynamic>> listCostItems(String projectId) async =>
      _asList(await getJson('/api/v1/cost-items', {'project_id': projectId}));

  Future<Map<String, dynamic>> createCostItem({
    required String projectId,
    required String title,
    required double amount,
    String category = 'other',
    String currency = 'KGS',
    String vendor = '',
  }) =>
      postJson('/api/v1/cost-items', {
        'project_id': projectId,
        'title': title,
        'amount': amount,
        'category': category,
        'currency': currency,
        'vendor': vendor,
      });

  Future<Map<String, dynamic>> updateCostItem({
    required String costItemId,
    required String title,
    required double amount,
    String category = 'other',
    String currency = 'KGS',
    String vendor = '',
  }) =>
      patchJson('/api/v1/cost-items/$costItemId', {
        'title': title,
        'amount': amount,
        'category': category,
        'currency': currency,
        'vendor': vendor,
      });

  Future<void> deleteCostItem(String costItemId) async {
    await deleteJson('/api/v1/cost-items/$costItemId');
  }

  Future<List<dynamic>> listDailyReports(String projectId) async => _asList(
        await getJson('/api/v1/daily-reports', {'project_id': projectId}),
      );

  Future<Map<String, dynamic>> createDailyReport({
    required String projectId,
    required String summary,
    required int workersCount,
    String issues = '',
  }) =>
      postJson('/api/v1/daily-reports', {
        'project_id': projectId,
        'summary': summary,
        'workers_count': workersCount,
        'issues': issues,
      });

  Future<Map<String, dynamic>> updateDailyReport({
    required String reportId,
    required String summary,
    required int workersCount,
    String issues = '',
  }) =>
      patchJson('/api/v1/daily-reports/$reportId', {
        'summary': summary,
        'workers_count': workersCount,
        'issues': issues,
      });

  Future<void> deleteDailyReport(String reportId) async {
    await deleteJson('/api/v1/daily-reports/$reportId');
  }

  Future<List<dynamic>> listTasks(String projectId) async =>
      _asList(await getJson('/api/v1/tasks', {'project_id': projectId}));

  Future<Map<String, dynamic>> createTask({
    required String projectId,
    required String title,
    String description = '',
    String status = 'open',
  }) =>
      postJson('/api/v1/tasks', {
        'project_id': projectId,
        'title': title,
        'description': description,
        'status': status,
      });

  Future<Map<String, dynamic>> updateTask({
    required String taskId,
    required String title,
    String description = '',
    String status = 'open',
  }) =>
      patchJson('/api/v1/tasks/$taskId', {
        'title': title,
        'description': description,
        'status': status,
      });

  Future<void> deleteTask(String taskId) async {
    await deleteJson('/api/v1/tasks/$taskId');
  }

  Future<List<dynamic>> listFiles(String projectId) async =>
      _asList(await getJson('/api/v1/files', {'project_id': projectId}));

  Future<Map<String, dynamic>> createFileMetadata({
    required String projectId,
    required String kind,
    required String originalName,
    required String storagePath,
    required String contentType,
    required int sizeBytes,
  }) =>
      postJson('/api/v1/files', {
        'project_id': projectId,
        'kind': kind,
        'original_name': originalName,
        'storage_path': storagePath,
        'content_type': contentType,
        'size_bytes': sizeBytes,
      });

  Future<Map<String, dynamic>> uploadProjectFile({
    required String projectId,
    required String kind,
    required String filePath,
    required String fileName,
  }) async {
    Future<http.Response> sendUpload() async {
      final request = http.MultipartRequest(
        'POST',
        ApiConfig.endpoint('/api/v1/files/upload'),
      );
      request.headers['Accept'] = 'application/json';
      final token = accessToken;
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.fields['project_id'] = projectId;
      request.fields['kind'] = kind;
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          filename: fileName,
        ),
      );
      final streamed = await _httpClient.send(request).timeout(_timeout);
      return http.Response.fromStream(streamed);
    }

    final response = await _send(sendUpload);
    return _decodeObject(response);
  }

  Future<void> deleteFile(String fileId) async {
    await deleteJson('/api/v1/files/$fileId');
  }

  Future<List<dynamic>> listAuditLogs(String projectId) async => _asList(
        await getJson('/api/v1/audit-logs', {'project_id': projectId}),
      );

  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) =>
      _postJson(path, body);

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body, {
    bool retry = true,
    bool includeBearer = true,
  }) async {
    final response = await _send(
      () => _httpClient.post(
        ApiConfig.endpoint(path),
        headers: _headers(includeBearer: includeBearer),
        body: jsonEncode(body),
      ),
      retry: retry,
    );
    return _decodeObject(response);
  }

  Future<Map<String, dynamic>> patchJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _send(
      () => _httpClient.patch(
        ApiConfig.endpoint(path),
        headers: _headers(),
        body: jsonEncode(body),
      ),
    );
    return _decodeObject(response);
  }

  Future<dynamic> getJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await _send(
      () => _httpClient.get(
        ApiConfig.endpoint(path, query),
        headers: _headers(),
      ),
    );
    return _decodeAny(response);
  }

  Future<dynamic> deleteJson(String path) async {
    final response = await _send(
      () => _httpClient.delete(ApiConfig.endpoint(path), headers: _headers()),
    );
    return _decodeAny(response);
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    bool retry = true,
  }) async {
    final response = await _perform(request);
    if (response.statusCode != 401 || !retry) return response;

    final refreshed = await _refreshTokens();
    if (!refreshed) {
      await _expireSession();
      return response;
    }

    final retried = await _perform(request);
    if (retried.statusCode == 401) await _expireSession();
    return retried;
  }

  Future<http.Response> _perform(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        408,
        'Request timed out. Check your internet connection and backend status.',
      );
    } on http.ClientException catch (error) {
      throw ApiException(0, error.message);
    }
  }

  Future<bool> _refreshTokens() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final future = _doRefreshTokens();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _doRefreshTokens() async {
    final token = refreshToken;
    if (token == null || token.isEmpty) return false;

    try {
      final response = await _perform(
        () => _httpClient.post(
          ApiConfig.endpoint('/api/v1/auth/session/refresh'),
          headers: _headers(includeBearer: false),
          body: jsonEncode({'refresh_token': token}),
        ),
      );
      if (response.statusCode >= 400) return false;
      final data = _decodeObject(response);
      final newAccess = data['access_token']?.toString() ?? '';
      final newRefresh = data['refresh_token']?.toString() ?? '';
      if (newAccess.isEmpty || newRefresh.isEmpty) return false;

      accessToken = newAccess;
      refreshToken = newRefresh;
      final handler = _onTokensUpdated;
      if (handler != null) await handler(newAccess, newRefresh);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _expireSession() async {
    accessToken = null;
    refreshToken = null;
    final handler = _onSessionExpired;
    if (handler != null) await handler();
  }

  Map<String, String> _headers({bool includeBearer = true}) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (includeBearer && accessToken != null && accessToken!.isNotEmpty)
          'Authorization': 'Bearer $accessToken',
      };

  Map<String, dynamic> _decodeObject(http.Response response) {
    final data = _decodeAny(response);
    if (data is Map<String, dynamic>) return data;
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
      final message =
          data is Map<String, dynamic> ? data['error']?.toString() : null;
      throw ApiException(response.statusCode, message ?? 'Request failed');
    }
    return data;
  }

  List<dynamic> _asList(dynamic data) {
    if (data is List<dynamic>) return data;
    if (data is Map<String, dynamic>) {
      for (final key in const [
        'items',
        'data',
        'results',
        'projects',
        'cost_items',
        'daily_reports',
        'tasks',
        'files',
        'audit_logs',
      ]) {
        final value = data[key];
        if (value is List<dynamic>) return value;
      }
    }
    return const <dynamic>[];
  }

  void close() => _httpClient.close();
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
