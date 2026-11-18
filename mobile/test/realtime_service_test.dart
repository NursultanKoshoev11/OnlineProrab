import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/realtime_service.dart';

/// A fake SSE connection whose body the test controls.
class _Connection {
  _Connection() {
    controller = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
  }

  late final StreamController<List<int>> controller;
  bool cancelled = false;

  void send(String text) => controller.add(utf8.encode(text));

  http.StreamedResponse response([int statusCode = 200]) =>
      http.StreamedResponse(controller.stream, statusCode);
}

const _frame =
    'event: change\n'
    'data: {"id":"e1","project_id":"p1","entity_type":"task",'
    '"entity_id":"t1","action":"updated","created_at":"2026-01-01"}\n\n';

RealtimeService _service(
  ApiClient apiClient, {
  Duration idleTimeout = const Duration(seconds: 60),
}) => RealtimeService(
  apiClient: apiClient,
  idleTimeout: idleTimeout,
  minReconnectDelay: const Duration(milliseconds: 10),
  maxReconnectDelay: const Duration(milliseconds: 40),
  random: () => 1.0,
);

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  test('parses SSE frames and ignores heartbeats', () async {
    final connection = _Connection();
    final apiClient = ApiClient(
      httpClient: MockClient.streaming((request, _) async {
        expect(request.url.path, '/api/v1/realtime');
        expect(request.headers['Authorization'], 'Bearer token');
        return connection.response();
      }),
    )..setAccessToken('token');
    final service = _service(apiClient);
    final events = <RealtimeEvent>[];
    service.events.listen(events.add);

    service.start();
    connection.send(': keep-alive\n\n');
    connection.send(_frame);
    await _until(() => events.isNotEmpty);

    expect(events.single.projectId, 'p1');
    expect(events.single.action, 'updated');
    await service.close();
    expect(connection.cancelled, isTrue);
  });

  test('stop() ends the read loop and does not reconnect', () async {
    var requests = 0;
    final connection = _Connection();
    final apiClient = ApiClient(
      httpClient: MockClient.streaming((request, _) async {
        requests++;
        return connection.response();
      }),
    )..setAccessToken('token');
    final service = _service(apiClient);

    service.start();
    await _until(() => connection.controller.hasListener);
    service.stop();
    await _until(() => connection.cancelled);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(requests, 1);
    await service.close();
  });

  test('closes a connection that completes after stop()', () async {
    final pending = Completer<http.StreamedResponse>();
    final connection = _Connection();
    final apiClient = ApiClient(
      httpClient: MockClient.streaming((request, _) => pending.future),
    )..setAccessToken('token');
    final service = _service(apiClient);
    final events = <RealtimeEvent>[];
    service.events.listen(events.add);

    service.start();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    service.stop();
    pending.complete(connection.response());
    await _until(() => connection.cancelled);
    connection.send(_frame);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(events, isEmpty);
    await service.close();
  });

  test('reconnects after the idle timeout without heartbeats', () async {
    final connections = <_Connection>[];
    final apiClient = ApiClient(
      httpClient: MockClient.streaming((request, _) async {
        final connection = _Connection();
        connections.add(connection);
        return connection.response();
      }),
    )..setAccessToken('token');
    final service = _service(
      apiClient,
      idleTimeout: const Duration(milliseconds: 50),
    );

    service.start();
    await _until(() => connections.length >= 2);

    expect(connections.first.cancelled, isTrue);
    expect(service.failedAttempts, 0);
    await service.close();
  });

  test('heartbeats keep an idle connection open', () async {
    var requests = 0;
    final connection = _Connection();
    final apiClient = ApiClient(
      httpClient: MockClient.streaming((request, _) async {
        requests++;
        return connection.response();
      }),
    )..setAccessToken('token');
    final service = _service(
      apiClient,
      idleTimeout: const Duration(milliseconds: 80),
    );

    service.start();
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      connection.send(': keep-alive\n\n');
    }

    expect(requests, 1);
    expect(connection.cancelled, isFalse);
    await service.close();
  });

  test('backs off on failures and resets after a success', () async {
    var requests = 0;
    final connections = <_Connection>[];
    final apiClient = ApiClient(
      httpClient: MockClient.streaming((request, _) async {
        requests++;
        if (requests <= 3) {
          return http.StreamedResponse(Stream.value(utf8.encode('{}')), 503);
        }
        final connection = _Connection();
        connections.add(connection);
        return connection.response();
      }),
    )..setAccessToken('token');
    final service = _service(apiClient);

    service.start();
    await _until(() => connections.isNotEmpty);
    expect(service.failedAttempts, 3);
    await connections.first.controller.close();
    await _until(() => connections.length >= 2);

    expect(service.failedAttempts, 0);
    await service.close();
  });

  test('reconnect delay grows exponentially, is capped and jittered', () {
    final apiClient = ApiClient(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
    );
    final upper = RealtimeService(apiClient: apiClient, random: () => 1.0);
    expect(upper.reconnectDelay(0), const Duration(seconds: 2));
    expect(upper.reconnectDelay(1), const Duration(seconds: 4));
    expect(upper.reconnectDelay(3), const Duration(seconds: 16));
    expect(upper.reconnectDelay(5), const Duration(seconds: 60));
    expect(upper.reconnectDelay(100), const Duration(seconds: 60));

    final lower = RealtimeService(apiClient: apiClient, random: () => 0.0);
    expect(lower.reconnectDelay(0), const Duration(seconds: 2));
    expect(lower.reconnectDelay(3), const Duration(seconds: 8));
    expect(lower.reconnectDelay(10), const Duration(seconds: 30));
  });
}
