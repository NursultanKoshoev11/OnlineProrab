import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

/// A project file streamed straight to local storage.
class StoredProjectFile {
  const StoredProjectFile({
    required this.file,
    required this.contentType,
    required this.fileName,
  });

  final File file;
  final String contentType;
  final String fileName;
}

// Characters that are invalid in file names on Android/iOS filesystems (and
// FAT/exFAT SD cards), plus control characters.
final RegExp _invalidFileNameChars = RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]');

/// Returns a single path component that is safe to use as a local file name.
///
/// Unicode letters and digits (including Cyrillic) are preserved; only path
/// separators, control characters and characters forbidden on mobile
/// filesystems are replaced. The result is limited to [maxBytes] UTF-8 bytes
/// while keeping the extension.
String safeLocalFileName(
  String value, {
  String fallback = 'download',
  int maxBytes = 200,
}) {
  final baseName = value.replaceAll('\\', '/').split('/').last;
  final cleaned = baseName
      .replaceAll(_invalidFileNameChars, '_')
      .trim()
      // Leading dots would create hidden files (and cover "." / ".."); some
      // filesystems silently strip trailing dots and spaces.
      .replaceFirst(RegExp(r'^\.+'), '')
      .replaceFirst(RegExp(r'[. ]+$'), '');
  if (cleaned.isEmpty) return fallback;
  if (utf8.encode(cleaned).length <= maxBytes) return cleaned;

  final dot = cleaned.lastIndexOf('.');
  var extension = dot > 0 ? cleaned.substring(dot) : '';
  if (utf8.encode(extension).length > 16) extension = '';
  final stem = extension.isEmpty ? cleaned : cleaned.substring(0, dot);
  final budget = maxBytes - utf8.encode(extension).length;
  final runes = stem.runes.toList();
  while (runes.isNotEmpty &&
      utf8.encode(String.fromCharCodes(runes)).length > budget) {
    runes.removeLast();
  }
  final truncated = String.fromCharCodes(runes).trim();
  return truncated.isEmpty ? fallback : truncated + extension;
}

class ProjectFileDownloadService {
  ProjectFileDownloadService({
    required ApiClient apiClient,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 30),
  }) : _apiClient = apiClient,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _timeout = timeout;

  final ApiClient _apiClient;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final Duration _timeout;

  /// Downloads a file into memory. Use for small payloads such as previews;
  /// prefer [downloadToFile] for user documents.
  Future<DownloadedProjectFile> download({
    required String fileId,
    required String fallbackFileName,
    required String fallbackContentType,
  }) async {
    final response = await _open(fileId);
    final builder = BytesBuilder(copy: false);
    await _guardBody(response.stream).forEach(builder.add);
    return DownloadedProjectFile(
      bytes: builder.takeBytes(),
      contentType: _contentType(response, fallbackContentType),
      fileName: _fileName(response, fallbackFileName),
    );
  }

  /// Streams a file to `<directory>/<fileId>/<fileName>` without buffering the
  /// whole body in memory. The per-file subdirectory avoids collisions between
  /// different files that share a name, while keeping the original name for
  /// the app that opens it.
  Future<StoredProjectFile> downloadToFile({
    required String fileId,
    required String fallbackFileName,
    required String fallbackContentType,
    required Directory directory,
  }) async {
    final response = await _open(fileId);
    final fileName = _fileName(response, fallbackFileName);
    final separator = Platform.pathSeparator;
    final target = Directory(
      '${directory.path}$separator${safeLocalFileName(fileId, fallback: 'file')}',
    );
    await target.create(recursive: true);
    final file = File('${target.path}$separator$fileName');
    final partial = File('${file.path}.part');
    final sink = partial.openWrite();
    try {
      await sink.addStream(_guardBody(response.stream));
      await sink.flush();
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {
        // The original error is more useful than a close failure.
      }
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
    if (await file.exists()) await file.delete();
    await partial.rename(file.path);
    return StoredProjectFile(
      file: file,
      contentType: _contentType(response, fallbackContentType),
      fileName: fileName,
    );
  }

  Future<http.StreamedResponse> _open(String fileId) async {
    var response = await _request(fileId);
    if (response.statusCode == 401) {
      await _discard(response);
      final refreshed = await _apiClient.refreshAccessToken();
      if (!refreshed) {
        throw const ApiException(401, 'Сессия истекла. Войдите снова.');
      }
      response = await _request(fileId);
      if (response.statusCode == 401) {
        await _discard(response);
        await _apiClient.expireSession();
        throw const ApiException(401, 'Сессия истекла. Войдите снова.');
      }
    }

    if (response.statusCode >= 400) {
      final body = await _readErrorBody(response);
      throw ApiException(response.statusCode, _readErrorMessage(body));
    }
    return response;
  }

  Future<http.StreamedResponse> _request(String fileId) async {
    final request = http.Request(
      'GET',
      ApiConfig.endpoint('/api/v1/files/download', {'file_id': fileId}),
    );
    final token = _apiClient.accessToken;
    request.headers.addAll({
      'Accept': '*/*',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    });
    try {
      return await _httpClient.send(request).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(408, 'Загрузка файла превысила время ожидания');
    } on http.ClientException catch (error) {
      throw ApiException(0, error.message);
    }
  }

  Future<void> _discard(http.StreamedResponse response) async {
    try {
      await response.stream.drain<void>().timeout(_timeout);
    } catch (_) {
      // The body of a rejected response is irrelevant.
    }
  }

  /// Fails the body stream if no bytes arrive for the configured timeout and
  /// maps transport errors to [ApiException].
  Stream<List<int>> _guardBody(Stream<List<int>> body) => body
      .timeout(_timeout)
      .handleError(
        (Object error) => throw const ApiException(
          408,
          'Загрузка файла превысила время ожидания',
        ),
        test: (error) => error is TimeoutException,
      )
      .handleError(
        (Object error) =>
            throw ApiException(0, (error as http.ClientException).message),
        test: (error) => error is http.ClientException,
      );

  Future<String> _readErrorBody(http.StreamedResponse response) async {
    // Error bodies are small JSON documents; cap reads defensively.
    final builder = BytesBuilder(copy: false);
    try {
      await for (final chunk in response.stream.timeout(_timeout)) {
        builder.add(chunk);
        if (builder.length > 64 * 1024) break;
      }
    } catch (_) {
      // Fall back to whatever was read.
    }
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }

  String _contentType(http.BaseResponse response, String fallback) {
    final value = response.headers['content-type']?.split(';').first.trim();
    if (value != null && value.isNotEmpty) return value;
    return fallback;
  }

  String _fileName(http.BaseResponse response, String fallback) {
    final disposition = response.headers['content-disposition'] ?? '';
    final utf8Match = RegExp(
      "filename\\*=utf-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(disposition);
    if (utf8Match != null) {
      try {
        return safeLocalFileName(Uri.decodeComponent(utf8Match.group(1)!));
      } on FormatException {
        return safeLocalFileName(fallback);
      } on ArgumentError {
        return safeLocalFileName(fallback);
      }
    }
    final quotedMatch = RegExp('filename="([^"]+)"').firstMatch(disposition);
    if (quotedMatch != null) return safeLocalFileName(quotedMatch.group(1)!);
    final unquotedMatch = RegExp(
      r'filename=([^;]+)',
      caseSensitive: false,
    ).firstMatch(disposition);
    if (unquotedMatch != null) {
      return safeLocalFileName(unquotedMatch.group(1)!);
    }
    return safeLocalFileName(fallback);
  }

  String _readErrorMessage(String body) {
    final text = body.trim();
    if (text.isEmpty) return 'Не удалось загрузить файл';
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
    if (text.length > 300) return 'Не удалось загрузить файл';
    return text;
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }
}
