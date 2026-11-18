import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/project_file_download_service.dart';

void main() {
  test('downloads file with bearer token and response metadata', () async {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
    )..setAccessToken('access-123');

    final service = ProjectFileDownloadService(
      apiClient: apiClient,
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/files/download');
        expect(request.url.queryParameters['file_id'], 'file-1');
        expect(request.headers['Authorization'], 'Bearer access-123');
        return http.Response.bytes(
          <int>[1, 2, 3, 4],
          200,
          headers: {
            'content-type': 'image/png',
            'content-disposition': 'attachment; filename="photo.png"',
          },
        );
      }),
    );

    final file = await service.download(
      fileId: 'file-1',
      fallbackFileName: 'fallback.bin',
      fallbackContentType: 'application/octet-stream',
    );

    expect(file.bytes, <int>[1, 2, 3, 4]);
    expect(file.contentType, 'image/png');
    expect(file.fileName, 'photo.png');
    expect(file.isImage, isTrue);
  });

  test('uses fallback metadata when response headers are missing', () async {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
    );
    final service = ProjectFileDownloadService(
      apiClient: apiClient,
      httpClient: MockClient((request) async {
        return http.Response.bytes(<int>[37, 80, 68, 70], 200);
      }),
    );

    final file = await service.download(
      fileId: 'file-2',
      fallbackFileName: 'document.pdf',
      fallbackContentType: 'application/pdf',
    );

    expect(file.fileName, 'document.pdf');
    expect(file.contentType, 'application/pdf');
    expect(file.isPDF, isTrue);
  });

  test('refreshes the access token directly before retrying a 401', () async {
    var refreshCalls = 0;
    var downloadCalls = 0;
    final apiClient = ApiClient(
      httpClient: MockClient((request) async {
        refreshCalls++;
        expect(request.url.path, '/api/v1/auth/session/refresh');
        return http.Response(
          jsonEncode({
            'access_token': 'access-new',
            'refresh_token': 'refresh-new',
          }),
          200,
        );
      }),
    )..setTokens(accessToken: 'access-old', refreshToken: 'refresh-old');
    final service = ProjectFileDownloadService(
      apiClient: apiClient,
      httpClient: MockClient((request) async {
        downloadCalls++;
        if (downloadCalls == 1) return http.Response('{}', 401);
        expect(request.headers['Authorization'], 'Bearer access-new');
        return http.Response.bytes(<int>[1], 200);
      }),
    );

    final file = await service.download(
      fileId: 'file-3',
      fallbackFileName: 'file.bin',
      fallbackContentType: 'application/octet-stream',
    );

    expect(file.bytes, <int>[1]);
    expect(refreshCalls, 1);
    expect(downloadCalls, 2);
  });

  test('throws ApiException when backend returns error', () async {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
    );
    final service = ProjectFileDownloadService(
      apiClient: apiClient,
      httpClient: MockClient((request) async {
        return http.Response(jsonEncode({'error': 'not found'}), 404);
      }),
    );

    expect(
      () => service.download(
        fileId: 'missing',
        fallbackFileName: 'missing.pdf',
        fallbackContentType: 'application/pdf',
      ),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 404)
            .having((error) => error.message, 'message', 'not found'),
      ),
    );
  });

  test('sanitizes response filename before returning it', () async {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
    );
    final service = ProjectFileDownloadService(
      apiClient: apiClient,
      httpClient: MockClient((request) async {
        return http.Response.bytes(
          <int>[1],
          200,
          headers: {
            'content-disposition':
                'attachment; filename="../receipt\\private.jpg"',
          },
        );
      }),
    );

    final file = await service.download(
      fileId: 'file-4',
      fallbackFileName: 'fallback.jpg',
      fallbackContentType: 'image/jpeg',
    );

    expect(file.fileName, 'private.jpg');
  });

  test('reads lower-case RFC 5987 and unquoted filenames', () async {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
    );
    final service = ProjectFileDownloadService(
      apiClient: apiClient,
      httpClient: MockClient((request) async {
        return http.Response.bytes(
          <int>[1],
          200,
          headers: {
            'content-disposition':
                "attachment; filename*=utf-8''receipt%20may.pdf",
          },
        );
      }),
    );

    final file = await service.download(
      fileId: 'file-5',
      fallbackFileName: 'fallback.pdf',
      fallbackContentType: 'application/pdf',
    );

    expect(file.fileName, 'receipt may.pdf');
  });

  test('keeps Cyrillic file names from RFC 5987 headers', () async {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
    );
    final service = ProjectFileDownloadService(
      apiClient: apiClient,
      httpClient: MockClient((request) async {
        return http.Response.bytes(
          <int>[1],
          200,
          headers: {
            'content-disposition':
                "attachment; filename*=UTF-8''${Uri.encodeComponent('Смета №2.pdf')}",
          },
        );
      }),
    );

    final file = await service.download(
      fileId: 'file-6',
      fallbackFileName: 'fallback.pdf',
      fallbackContentType: 'application/pdf',
    );

    expect(file.fileName, 'Смета №2.pdf');
  });

  test('safeLocalFileName strips only unsafe characters', () {
    expect(safeLocalFileName('Отчёт: этап 1?.pdf'), 'Отчёт_ этап 1_.pdf');
    expect(safeLocalFileName('../..секрет.jpg'), 'секрет.jpg');
    expect(safeLocalFileName('a\u0000b\nc.txt'), 'a_b_c.txt');
    expect(safeLocalFileName('..'), 'download');
    expect(safeLocalFileName('   '), 'download');
    expect(safeLocalFileName('.hidden'), 'hidden');
    final long = safeLocalFileName('${'я' * 300}.pdf');
    expect(utf8.encode(long).length, lessThanOrEqualTo(200));
    expect(long, endsWith('.pdf'));
  });

  test('streams downloads to a per-file directory', () async {
    final temp = await Directory.systemTemp.createTemp('download_test');
    addTearDown(() => temp.delete(recursive: true));
    var downloadCalls = 0;
    final apiClient = ApiClient(
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode({'access_token': 'a2', 'refresh_token': 'r2'}),
          200,
        );
      }),
    )..setTokens(accessToken: 'a1', refreshToken: 'r1');
    final service = ProjectFileDownloadService(
      apiClient: apiClient,
      httpClient: MockClient.streaming((request, _) async {
        downloadCalls++;
        if (downloadCalls == 1) {
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), 401);
        }
        expect(request.headers['Authorization'], 'Bearer a2');
        return http.StreamedResponse(
          Stream.fromIterable([
            <int>[1, 2],
            <int>[3],
          ]),
          200,
          headers: {
            'content-type': 'application/pdf',
            'content-disposition':
                "attachment; filename*=utf-8''${Uri.encodeComponent('Акт.pdf')}",
          },
        );
      }),
    );

    final first = await service.downloadToFile(
      fileId: 'id/1',
      fallbackFileName: 'x.pdf',
      fallbackContentType: 'application/octet-stream',
      directory: temp,
    );
    final second = await service.downloadToFile(
      fileId: 'id-2',
      fallbackFileName: 'x.pdf',
      fallbackContentType: 'application/octet-stream',
      directory: temp,
    );

    expect(first.fileName, 'Акт.pdf');
    expect(first.contentType, 'application/pdf');
    expect(await first.file.readAsBytes(), <int>[1, 2, 3]);
    expect(first.file.parent.parent.path, temp.path);
    expect(second.file.path, isNot(first.file.path));
    expect(await second.file.exists(), isTrue);
    expect(downloadCalls, 3);
  });

  test('removes partial file when the stream fails', () async {
    final temp = await Directory.systemTemp.createTemp('download_test');
    addTearDown(() => temp.delete(recursive: true));
    final apiClient = ApiClient(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
    );
    final service = ProjectFileDownloadService(
      apiClient: apiClient,
      httpClient: MockClient.streaming((request, _) async {
        final body = StreamController<List<int>>();
        body.add(<int>[1]);
        body.addError(http.ClientException('connection reset'));
        body.close();
        return http.StreamedResponse(body.stream, 200);
      }),
    );

    await expectLater(
      service.downloadToFile(
        fileId: 'f',
        fallbackFileName: 'a.bin',
        fallbackContentType: 'application/octet-stream',
        directory: temp,
      ),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 0)),
    );
    final leftovers = await temp
        .list(recursive: true)
        .where((entity) => entity is File)
        .toList();
    expect(leftovers, isEmpty);
  });
}
