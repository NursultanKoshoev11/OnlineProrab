import 'dart:convert';

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
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          404,
        ),
      ),
    );
  });
}
