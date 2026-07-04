import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/analytics_types.dart';

String _newSessionId() {
  final rng = Random.secure();
  String hex(int n) =>
      List.generate(n, (_) => rng.nextInt(16).toRadixString(16)).join();
  // RFC-4122 v4.
  final y = (8 + rng.nextInt(4)).toRadixString(16);
  return '${hex(8)}-${hex(4)}-4${hex(3)}-$y${hex(3)}-${hex(12)}';
}

String? _detectOS() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.fuchsia:
      return 'fuchsia';
  }
}

/// Emits player events to the Logplex ingest API. It batches (size + time),
/// retries transient failures, heartbeats while playing, and flushes when the
/// app goes to background so the final position isn't lost.
///
/// Mirrors the web player SDK contract: X-API-Key auth, snake_case payloads,
/// `/v1/ingest/event` · `/events/batch` · `/heartbeat`.
class LogplexAnalyticsClient {
  LogplexAnalyticsClient(this.config, {http.Client? httpClient})
      : sessionId = config.sessionId ?? _newSessionId(),
        _http = httpClient ?? http.Client(),
        _ownsHttp = httpClient == null;

  final LogplexAnalyticsConfig config;
  final String sessionId;
  final http.Client _http;
  final bool _ownsHttp;
  final String? _deviceOS = _detectOS();

  List<Map<String, Object?>> _queue = [];
  Timer? _flushTimer;
  Timer? _heartbeatTimer;
  bool _destroyed = false;

  /// Start the periodic flush timer. Idempotent.
  void start() {
    if (config.disabled || _flushTimer != null) return;
    _flushTimer = Timer.periodic(config.flushInterval, (_) => flush());
  }

  /// Record an event.
  void track(LogplexEventType type, [TrackFields fields = const TrackFields()]) {
    if (config.disabled || _destroyed) return;
    _queue.add(_build(type, fields));
    if (_queue.length >= config.batchSize) flush();
  }

  /// Begin periodic heartbeats (call when playback starts).
  void startHeartbeat(int Function() getPositionMs) {
    if (config.disabled || _heartbeatTimer != null) return;
    _heartbeatTimer = Timer.periodic(config.heartbeatInterval, (_) {
      _post('/v1/ingest/heartbeat', {
        'session_id': sessionId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'player_time_ms': getPositionMs(),
      });
    });
  }

  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Fetch the saved resume point for this (viewer, content). null = none.
  Future<ResumePoint?> getResume() async {
    if (config.disabled) return null;
    final url = '${config.baseUrl}/v1/ingest/playback/'
        '${Uri.encodeComponent(config.contentId)}/progress'
        '?user_id=${Uri.encodeComponent(config.userId)}';
    try {
      final res = await _http
          .get(Uri.parse(url), headers: {'X-API-Key': config.apiKey});
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final d = body['data'] as Map<String, dynamic>?;
      final positionSeconds = d?['position_seconds'];
      if (positionSeconds is! num) return null;
      return ResumePoint(
        position: Duration(milliseconds: (positionSeconds * 1000).round()),
        duration: Duration(
            milliseconds:
                (((d?['duration_seconds'] as num?) ?? 0) * 1000).round()),
        percentWatched: ((d?['percent_watched'] as num?) ?? 0).toDouble(),
        completed: d?['completed'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Register content metadata once (title/thumbnail/type) for reports.
  void registerContent() {
    if (config.disabled) return;
    _post(
      '/v1/ingest/playback/${Uri.encodeComponent(config.contentId)}/progress',
      {
        'session_id': sessionId,
        'user_id': config.userId,
        if (config.merchantUserId != null)
          'merchant_user_id': config.merchantUserId,
        if (config.contentType != null) 'content_type': config.contentType,
        if (config.contentTitle != null) 'content_title': config.contentTitle,
        if (config.contentThumbnailUrl != null)
          'content_thumbnail_url': config.contentThumbnailUrl,
      },
      method: 'PUT',
    );
  }

  /// Flush buffered events.
  Future<void> flush() async {
    if (_queue.isEmpty) return;
    final batch = _queue;
    _queue = [];
    await _post('/v1/ingest/events/batch', {'events': batch});
  }

  /// Stop timers + flush. Call on teardown.
  Future<void> destroy() async {
    if (_destroyed) return;
    _destroyed = true;
    stopHeartbeat();
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush();
    if (_ownsHttp) _http.close();
  }

  Map<String, Object?> _build(LogplexEventType type, TrackFields f) {
    return {
      'event_type': type.wire,
      'session_id': sessionId,
      'timestamp': f.timestamp ?? DateTime.now().millisecondsSinceEpoch,
      'user_id': config.userId,
      if (config.userType != null) 'user_type': config.userType,
      'content_id': config.contentId,
      if (config.contentType != null) 'content_type': config.contentType,
      if (config.contentDuration != null)
        'content_duration_ms': config.contentDuration!.inMilliseconds,
      if (f.episodeId != null) 'episode_id': f.episodeId,
      if (f.seriesId != null) 'series_id': f.seriesId,
      if (f.playerTimeMs != null) 'player_time_ms': f.playerTimeMs,
      if (f.seekFromMs != null) 'seek_from_ms': f.seekFromMs,
      if (f.seekToMs != null) 'seek_to_ms': f.seekToMs,
      if (f.bufferDurationMs != null) 'buffer_duration_ms': f.bufferDurationMs,
      if (f.bytesChunk != null) 'bytes_chunk': f.bytesChunk,
      if (f.bitrateKbps != null) 'bitrate_kbps': f.bitrateKbps,
      if (f.quality != null) 'quality': f.quality,
      'device_type': kIsWeb ? 'web' : 'mobile',
      if (_deviceOS != null) 'device_os': _deviceOS,
      if (config.appVersion != null) 'app_version': config.appVersion,
      if (f.error != null) 'error': f.error!.toWire(),
    };
  }

  Future<void> _post(String path, Map<String, Object?> body,
      {String method = 'POST'}) async {
    final url = Uri.parse('${config.baseUrl}$path');
    final data = jsonEncode(body);
    for (var attempt = 0; attempt <= 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: attempt * 500));
      }
      try {
        final req = http.Request(method, url)
          ..headers['Content-Type'] = 'application/json'
          ..headers['X-API-Key'] = config.apiKey
          ..body = data;
        final res = await _http.send(req);
        // Drain so the connection can be reused.
        unawaited(res.stream.drain<void>().catchError((_) {}));
        if (res.statusCode >= 200 && res.statusCode < 300) return;
        if (res.statusCode < 500) return; // 4xx won't succeed on retry
      } catch (_) {
        // network error → retry
      }
    }
  }
}
