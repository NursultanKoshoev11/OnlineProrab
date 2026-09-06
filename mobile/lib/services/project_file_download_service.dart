import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/api_config.dart';

class DownloadedProjectFile {
  const DownloadedProjectFile({
    required this.bytes,
    required this.contentType,
    required this.fileName,
  });

  final Uint8List bytes;
  final String contentType;
  final String fileName;

  bool get isImage => contentType.startsWith('image/');
  bool get isPDF => contentType == 'application/pdf';
}

class ProjectFileDownloadService {
  ProjectFileDownloadService({
    required ApiClient apiClient,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 30),
  }) : _apiClient = apiClient,
       _httpClient = httpClient ?? http.Client(),
       _timeout = timeout;

  final ApiClient _apiClient;
  final http.Client _httpClient;
  final Duration _timeout;

  Future<DownloadedProjectFile> download({
    required String fileId,
    required String fallbackFileName,
    required String fallbackContentType,
  }) async {
    var response = await _request(fileId);
    if (response.statusCode == 401) {
      final refreshed = await _apiClient.refreshAccessToken();
      if (!refreshed) {
        throw const ApiException(401, 'Session expired. Please sign in again.');
      }
      response = await _request(fileId);
      if (response.statusCode == 401) {
        await _apiClient.expireSession();
        throw const ApiException(401, 'Session expired. Please sign in again.');
      }
    }

    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, _readErrorMessage(response));
    }

    return DownloadedProjectFile(
      bytes: response.bodyBytes,
      contentType: _contentType(response, fallbackContentType),
      fileName: _fileName(response, fallbackFileName),
    );
  }

  Future<http.Response> _request(String fileId) async {
    try {
      return await _httpClient
          .get(
            ApiConfig.endpoint('/api/v1/files/download', {'file_id': fileId}),
            headers: {
              'Accept': '*/*',
              if (_apiClient.accessToken != null &&
                  _apiClient.accessToken!.isNotEmpty)
                'Authorization': 'Bearer ${_apiClient.accessToken}',
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(408, 'File download timed out');
    } on http.ClientException catch (error) {
      throw ApiException(0, error.message);
    }
  }

  String _contentType(http.Response response, String fallback) {
    final value = response.headers['content-type']?.split(';').first.trim();
    if (value != null && value.isNotEmpty) return value;
    return fallback;
  }

  String _fileName(http.Response response, String fallback) {
    final disposition = response.headers['content-disposition'] ?? '';
    final utf8Match = RegExp(
      "filename\\*=utf-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(disposition);
    if (utf8Match != null) {
      try {
        return _safeFileName(Uri.decodeComponent(utf8Match.group(1)!));
      } on FormatException {
        return _safeFileName(fallback);
      }
    }
    final quotedMatch = RegExp('filename="([^"]+)"').firstMatch(disposition);
    if (quotedMatch != null) return _safeFileName(quotedMatch.group(1)!);
    final unquotedMatch = RegExp(
      r'filename=([^;]+)',
      caseSensitive: false,
    ).firstMatch(disposition);
    if (unquotedMatch != null) return _safeFileName(unquotedMatch.group(1)!);
    return _safeFileName(fallback);
  }

  String _safeFileName(String value) {
    final baseName = value.replaceAll('\\', '/').split('/').last.trim();
    final cleaned = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
        ? 'download'
        : cleaned;
  }

  String _readErrorMessage(http.Response response) {
    final text = response.body.trim();
    if (text.isEmpty) return 'File download failed';
    try {
      final data = jsonDecode(text);
      if (data is Map<String, dynamic>) {
        final message = data['error']?.toString().trim();
        if (message != null && message.isNotEmpty && message.length <= 300) {
          return message;
        }
      }
    } on FormatException {
      // Fall back to the raw response below.
    }
    if (text.length > 300) return 'File download failed';
    return text;
  }

  void close() => _httpClient.close();
}
