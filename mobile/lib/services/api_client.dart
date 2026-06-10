import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:online_prorab/services/api_config.dart';

class ApiClient {
  ApiClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  String? accessToken;

  Future<Map<String, dynamic>> requestSMSCode(String phone) async {
    return postJson('/api/v1/auth/sms/request', {'phone': phone});
  }

  Future<Map<String, dynamic>> verifySMSCode(String phone, String code) async {
    return postJson('/api/v1/auth/sms/verify', {'phone': phone, 'code': code});
  }

  Future<List<dynamic>> listProjects() async {
    final data = await getJson('/api/v1/projects');
    return data is List<dynamic> ? data : <dynamic>[];
  }

  Future<Map<String, dynamic>> createProject(String name, String address) async {
    return postJson('/api/v1/projects', {'name': name, 'address': address});
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) async {
    final response = await _httpClient.post(
      ApiConfig.endpoint(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _decodeObject(response);
  }

  Future<dynamic> getJson(String path, [Map<String, String>? query]) async {
    final response = await _httpClient.get(ApiConfig.endpoint(path, query), headers: _headers());
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
