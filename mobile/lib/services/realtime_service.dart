import 'dart:async';
import 'dart:convert';

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

class RealtimeService {
  RealtimeService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;
  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();
  StreamSubscription<String>? _lineSubscription;
  bool _running = false;
  bool _closed = false;
  int _generation = 0;

  Stream<RealtimeEvent> get events => _events.stream;

  void start() {
    if (_closed || _running) return;
    _running = true;
    final generation = ++_generation;
    unawaited(_run(generation));
  }

  void stop() {
    _running = false;
    _generation++;
    final subscription = _lineSubscription;
    _lineSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  Future<void> _run(int generation) async {
    while (_running && generation == _generation) {
      try {
        await _readOnce(generation);
      } catch (_) {
        // Live updates are best effort; REST remains the source of truth.
      }
      if (_running && generation == _generation) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _readOnce(int generation) async {
    final token = _apiClient.accessToken;
    if (token == null || token.isEmpty) {
      await Future<void>.delayed(const Duration(seconds: 2));
      return;
    }

    final request = http.Request('GET', ApiConfig.endpoint('/api/v1/realtime'));
    request.headers.addAll({
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Authorization': 'Bearer ' + token,
    });
    final response = await _apiClient.httpClient
        .send(request)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      await response.stream.drain<void>();
      if (response.statusCode == 401) {
        await _apiClient.refreshAccessToken();
      }
      throw ApiException(
        response.statusCode,
        'Realtime stream returned ' + response.statusCode.toString(),
      );
    }

    var data = '';
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final done = Completer<void>();
    late final StreamSubscription<String> subscription;
    subscription = lines.listen(
      (line) {
        if (line.startsWith('data:')) {
          data += line.substring(5).trimLeft();
          return;
        }
        if (line.isEmpty && data.isNotEmpty) {
          _emit(data);
          data = '';
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
    try {
      await done.future;
    } finally {
      await subscription.cancel();
      if (identical(_lineSubscription, subscription)) {
        _lineSubscription = null;
      }
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
