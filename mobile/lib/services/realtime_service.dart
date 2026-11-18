import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:online_prorab/services/api_client.dart';
import 'package:online_prorab/services/api_config.dart';

class RealtimeEvent {
  const RealtimeEvent({
    required this.id,
    required this.projectId,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.createdAt,
  });

  final String id;
  final String projectId;
  final String entityType;
  final String entityId;
  final String action;
  final String createdAt;

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) => RealtimeEvent(
    id: json['id']?.toString() ?? '',
    projectId: json['project_id']?.toString() ?? '',
    entityType: json['entity_type']?.toString() ?? '',
    entityId: json['entity_id']?.toString() ?? '',
    action: json['action']?.toString() ?? '',
    createdAt: json['created_at']?.toString() ?? '',
  );
}

/// Server-sent events client for `/api/v1/realtime`.
///
/// The backend sends a `: keep-alive` comment every 20 seconds, so a stream
/// that stays silent for [idleTimeout] (60 seconds by default, three missed
/// heartbeats) is treated as dead and reconnected. Reconnects use exponential
/// backoff with jitter between [minReconnectDelay] and [maxReconnectDelay];
/// the backoff resets after a successful connection.
class RealtimeService {
  RealtimeService({
    required ApiClient apiClient,
    this.idleTimeout = const Duration(seconds: 60),
    this.connectTimeout = const Duration(seconds: 15),
    this.minReconnectDelay = const Duration(seconds: 2),
    this.maxReconnectDelay = const Duration(seconds: 60),
    double Function()? random,
  }) : _apiClient = apiClient,
       _random = random ?? math.Random().nextDouble;

  final ApiClient _apiClient;
  final Duration idleTimeout;
  final Duration connectTimeout;
  final Duration minReconnectDelay;
  final Duration maxReconnectDelay;
  final double Function() _random;

  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();
  StreamSubscription<String>? _lineSubscription;
  Completer<void>? _connectionDone;
  Completer<void>? _sleepWake;
  bool _running = false;
  bool _closed = false;
  int _generation = 0;
  int _failedAttempts = 0;

  Stream<RealtimeEvent> get events => _events.stream;

  /// Consecutive failed connection attempts since the last success.
  @visibleForTesting
  int get failedAttempts => _failedAttempts;

  void start() {
    if (_closed || _running) return;
    _running = true;
    _failedAttempts = 0;
    final generation = ++_generation;
    unawaited(_run(generation));
  }

  void stop() {
    _running = false;
    _generation++;
    final subscription = _lineSubscription;
    _lineSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    // Release the pending read and any backoff sleep so the old loop exits.
    final done = _connectionDone;
    _connectionDone = null;
    if (done != null && !done.isCompleted) done.complete();
    final wake = _sleepWake;
    _sleepWake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  /// Delay before reconnect attempt number [attempt] (0-based): exponential
  /// growth capped at [maxReconnectDelay], with "equal jitter" (50-100% of
  /// the capped value), never below [minReconnectDelay].
  @visibleForTesting
  Duration reconnectDelay(int attempt) {
    final minMs = minReconnectDelay.inMilliseconds;
    final maxMs = maxReconnectDelay.inMilliseconds;
    final exponent = math.min(attempt, 30);
    final capped = math.min(maxMs, minMs * math.pow(2, exponent)).toDouble();
    final jittered = capped / 2 + _random() * capped / 2;
    return Duration(milliseconds: jittered.round().clamp(minMs, maxMs));
  }

  bool _isCurrent(int generation) =>
      _running && !_closed && generation == _generation;

  Future<void> _run(int generation) async {
    while (_isCurrent(generation)) {
      _ConnectResult result;
      try {
        result = await _readOnce(generation);
      } catch (_) {
        // Live updates are best effort; REST remains the source of truth.
        result = _ConnectResult.failed;
      }
      if (!_isCurrent(generation)) break;
      final Duration delay;
      switch (result) {
        case _ConnectResult.connected:
          _failedAttempts = 0;
          delay = reconnectDelay(0);
        case _ConnectResult.failed:
          delay = reconnectDelay(_failedAttempts);
          _failedAttempts++;
        case _ConnectResult.noToken:
          delay = minReconnectDelay;
      }
      await _sleep(delay);
    }
  }

  Future<void> _sleep(Duration delay) async {
    final wake = Completer<void>();
    _sleepWake = wake;
    final timer = Timer(delay, () {
      if (!wake.isCompleted) wake.complete();
    });
    await wake.future;
    timer.cancel();
    if (identical(_sleepWake, wake)) _sleepWake = null;
  }

  Future<_ConnectResult> _readOnce(int generation) async {
    final token = _apiClient.accessToken;
    if (token == null || token.isEmpty) return _ConnectResult.noToken;

    final request = http.Request('GET', ApiConfig.endpoint('/api/v1/realtime'));
    request.headers.addAll({
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Authorization': 'Bearer $token',
    });
    final sending = _apiClient.httpClient.send(request);
    final http.StreamedResponse response;
    try {
      response = await sending.timeout(connectTimeout);
    } on TimeoutException {
      // Close the connection if the response eventually arrives.
      unawaited(sending.then(_discard, onError: (Object _) {}));
      rethrow;
    }
    if (!_isCurrent(generation)) {
      // stop() ran while the request was in flight: never attach this stream.
      await _discard(response);
      return _ConnectResult.failed;
    }
    if (response.statusCode != 200) {
      await _discard(response);
      if (response.statusCode == 401 && _isCurrent(generation)) {
        await _apiClient.refreshAccessToken();
      }
      throw ApiException(
        response.statusCode,
        'Не удалось обновить данные в реальном времени (код '
        '${response.statusCode})',
      );
    }

    final dataLines = <String>[];
    final lines = response.stream
        .timeout(idleTimeout)
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final done = Completer<void>();
    final subscription = lines.listen(
      (line) {
        if (line.startsWith('data:')) {
          dataLines.add(line.substring(5).trimLeft());
          return;
        }
        if (line.isEmpty && dataLines.isNotEmpty) {
          final data = dataLines.join('\n');
          dataLines.clear();
          if (_isCurrent(generation)) _emit(data);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: false,
    );
    _lineSubscription = subscription;
    _connectionDone = done;
    try {
      await done.future;
    } catch (_) {
      // Idle timeout or transport error after a successful connection: the
      // connection itself worked, so reconnect without growing the backoff.
    } finally {
      await subscription.cancel();
      if (identical(_lineSubscription, subscription)) {
        _lineSubscription = null;
      }
      if (identical(_connectionDone, done)) _connectionDone = null;
    }
    return _ConnectResult.connected;
  }

  Future<void> _discard(http.StreamedResponse response) async {
    try {
      await response.stream.listen(null, cancelOnError: true).cancel();
    } catch (_) {
      // Nothing useful to do with a failing body we are dropping.
    }
  }

  void _emit(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) return;
      if (_closed || !_running) return;
      final event = RealtimeEvent.fromJson(decoded);
      if (event.projectId.isEmpty || _events.isClosed) return;
      _events.add(event);
    } on FormatException {
      // Ignore malformed frames and let the next valid frame through.
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    stop();
    await _events.close();
  }
}

enum _ConnectResult { connected, failed, noToken }
