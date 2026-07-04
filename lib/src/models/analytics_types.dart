import 'package:flutter/foundation.dart';

/// Canonical event_type strings accepted by the Logplex ingest API.
enum LogplexEventType {
  play('play'),
  pause('pause'),
  resume('resume'),
  seek('seek'),
  bufferStart('buffer_start'),
  bufferEnd('buffer_end'),
  qualityChange('quality_change'),
  heartbeat('heartbeat'),
  downloadChunk('download_chunk'),
  complete('complete'),
  exit('exit'),
  error('error'),
  playStartSuccess('play_start_success'),
  progress25('progress_25'),
  progress50('progress_50'),
  progress75('progress_75'),
  progress90('progress_90'),
  like('like'),
  watchlistAdd('watchlist_add'),
  share('share'),
  autoplayAttempt('autoplay_attempt'),
  autoplayStart('autoplay_start'),
  searchQuery('search_query'),
  searchResultClick('search_result_click'),
  adRequest('ad_request'),
  adStart('ad_start'),
  adComplete('ad_complete'),
  appOpen('app_open');

  const LogplexEventType(this.wire);

  /// snake_case value sent on the wire.
  final String wire;
}

/// Configures the built-in Logplex analytics + resume integration.
@immutable
class LogplexAnalyticsConfig {
  const LogplexAnalyticsConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.userId,
    required this.contentId,
    this.userType,
    this.contentType,
    this.contentDuration,
    this.contentTitle,
    this.contentThumbnailUrl,
    this.merchantUserId,
    this.sessionId,
    this.heartbeatInterval = const Duration(seconds: 10),
    this.batchSize = 20,
    this.flushInterval = const Duration(seconds: 5),
    this.appVersion,
    this.disabled = false,
  });

  /// Ingest API base URL, e.g. "https://ingest.example.com".
  final String baseUrl;

  /// API key sent to your ingest endpoint (X-API-Key).
  final String apiKey;

  /// Opaque, stable per-viewer identity.
  final String userId;

  /// 'authenticated' or 'guest'.
  final String? userType;

  /// Opaque content id this session plays.
  final String contentId;

  /// 'movie' | 'series' | 'live'.
  final String? contentType;
  final Duration? contentDuration;
  final String? contentTitle;
  final String? contentThumbnailUrl;

  /// Merchant's own user id (optional, for their reports).
  final String? merchantUserId;

  /// Reused across restarts if you persist it; generated otherwise.
  final String? sessionId;

  /// Heartbeat cadence while playing.
  final Duration heartbeatInterval;

  /// Max events buffered before a flush.
  final int batchSize;

  /// Max time events sit buffered before a flush.
  final Duration flushInterval;
  final String? appVersion;

  /// Turn the whole integration off (e.g. for previews).
  final bool disabled;

  LogplexAnalyticsConfig copyWith({
    String? contentId,
    Duration? contentDuration,
    String? contentTitle,
  }) {
    return LogplexAnalyticsConfig(
      baseUrl: baseUrl,
      apiKey: apiKey,
      userId: userId,
      contentId: contentId ?? this.contentId,
      userType: userType,
      contentType: contentType,
      contentDuration: contentDuration ?? this.contentDuration,
      contentTitle: contentTitle ?? this.contentTitle,
      contentThumbnailUrl: contentThumbnailUrl,
      merchantUserId: merchantUserId,
      sessionId: sessionId,
      heartbeatInterval: heartbeatInterval,
      batchSize: batchSize,
      flushInterval: flushInterval,
      appVersion: appVersion,
      disabled: disabled,
    );
  }
}

/// Error details attached to an `error` event.
@immutable
class PlayerErrorInfo {
  const PlayerErrorInfo({required this.code, this.message, this.httpStatus, this.url});

  final String code;
  final String? message;
  final int? httpStatus;
  final String? url;

  Map<String, Object?> toWire() => {
        'code': code,
        if (message != null) 'message': message,
        if (httpStatus != null) 'http_status': httpStatus,
        if (url != null) 'url': url,
      };
}

/// Per-event fields layered on top of the session-constant fields.
@immutable
class TrackFields {
  const TrackFields({
    this.playerTimeMs,
    this.seekFromMs,
    this.seekToMs,
    this.bufferDurationMs,
    this.bytesChunk,
    this.bitrateKbps,
    this.quality,
    this.episodeId,
    this.seriesId,
    this.error,
    this.timestamp,
  });

  final int? playerTimeMs;
  final int? seekFromMs;
  final int? seekToMs;
  final int? bufferDurationMs;
  final int? bytesChunk;
  final int? bitrateKbps;

  /// 'auto' | '360p' | '480p' | '720p' | '1080p' | '1440p' | '4k'.
  final String? quality;
  final String? episodeId;
  final String? seriesId;
  final PlayerErrorInfo? error;

  /// Override the event timestamp (unix ms); defaults to now.
  final int? timestamp;
}

/// Resume point returned by GET /v1/ingest/playback/{contentId}/progress —
/// or supplied by the host's own back-end via `resolveResume`.
@immutable
class ResumePoint {
  const ResumePoint({
    required this.position,
    this.duration = Duration.zero,
    this.percentWatched = 0,
    this.completed = false,
  });

  final Duration position;
  final Duration duration;
  final double percentWatched;
  final bool completed;
}

/// Payload handed to the watch-interval handler each tick.
@immutable
class WatchIntervalInfo {
  const WatchIntervalInfo({
    required this.playDuration,
    required this.position,
    this.quality,
    this.userWatchId,
  });

  /// Accumulated wall-clock seconds the viewer actually spent playing.
  final int playDuration;

  /// Current playback position, in seconds.
  final double position;

  /// Current resolution as "W*H" with a literal asterisk (e.g. "1920*1080"),
  /// or "" when unknown.
  final String? quality;

  /// The id returned by the previous handler call, chained back so the
  /// back-end can update the same watch record.
  final String? userWatchId;
}

/// Periodic "user watch" reporter for an external (pre-Logplex) tracker.
/// Return a watch id to have it chained into subsequent calls.
typedef WatchIntervalHandler = Future<String?> Function(WatchIntervalInfo info);

/// Supplies a saved resume point from a host back-end (used instead of the
/// built-in Logplex analytics, e.g. while Logplex is not yet launched).
typedef ResumeResolver = Future<ResumePoint?> Function();
