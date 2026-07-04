import 'dart:async';

import '../core/controller.dart';
import '../models/analytics_types.dart';
import 'client.dart';

/// Wires a [PlayoraController] to a [LogplexAnalyticsClient]: playback
/// state changes become canonical Logplex events, heartbeats run while
/// playing, progress milestones (25/50/75/90) fire once each, and an `exit`
/// is emitted on [detach].
///
/// Content analytics is suspended while an ad plays — the orchestrator calls
/// [suspend]/[resumeTracking] around ad breaks so ad playback never registers
/// as content play/heartbeat.
class PlayerAnalyticsTracker {
  PlayerAnalyticsTracker(this.client, this.controller) {
    _attach();
  }

  final LogplexAnalyticsClient client;
  final PlayoraController controller;

  final List<StreamSubscription<dynamic>> _subs = [];
  bool _suspended = false;
  bool _started = false;
  bool _paused = true;
  DateTime? _bufferStartedAt;
  bool _wasBuffering = false;
  bool _wasPlaying = false;
  final Set<int> _milestonesFired = {};
  bool _detached = false;

  int get _posMs => controller.position.value.inMilliseconds;

  String _currentQuality() {
    final v = controller.state.value.selected.video;
    final h = v.h ?? controller.state.value.height;
    if (h == null || controller.isAutoQuality) return 'auto';
    if (h >= 2160) return '4k';
    if (h >= 1440) return '1440p';
    if (h >= 1080) return '1080p';
    if (h >= 720) return '720p';
    if (h >= 480) return '480p';
    return '360p';
  }

  void _attach() {
    controller.state.addListener(_onState);
    controller.position.addListener(_onPosition);
    _subs.addAll([
      controller.onSeek.listen((seek) {
        if (_suspended) return;
        client.track(
          LogplexEventType.seek,
          TrackFields(
            seekFromMs: seek.from.inMilliseconds,
            seekToMs: seek.to.inMilliseconds,
            playerTimeMs: seek.to.inMilliseconds,
          ),
        );
      }),
      controller.onQualityChanged.listen((_) {
        if (_suspended) return;
        client.track(
          LogplexEventType.qualityChange,
          TrackFields(quality: _currentQuality(), playerTimeMs: _posMs),
        );
      }),
      controller.onCompleted.listen((_) {
        if (_suspended) return;
        client.stopHeartbeat();
        client.track(
            LogplexEventType.complete, TrackFields(playerTimeMs: _posMs));
      }),
      controller.onError.listen((message) {
        if (_suspended) return;
        client.track(
          LogplexEventType.error,
          TrackFields(
            playerTimeMs: _posMs,
            error: PlayerErrorInfo(code: 'PLAYER_ERROR', message: message),
          ),
        );
      }),
    ]);
  }

  void _onState() {
    if (_suspended || _detached) return;
    final v = controller.state.value;

    if (v.playing && !_wasPlaying) {
      if (!_started) {
        _started = true;
        client
          ..track(LogplexEventType.play, TrackFields(playerTimeMs: _posMs))
          ..track(LogplexEventType.playStartSuccess,
              TrackFields(playerTimeMs: _posMs));
      } else if (_paused) {
        client.track(LogplexEventType.resume, TrackFields(playerTimeMs: _posMs));
      }
      _endBuffer();
      _paused = false;
      client.startHeartbeat(() => _posMs);
    } else if (!v.playing && _wasPlaying && !_paused) {
      _paused = true;
      client.stopHeartbeat();
      client.track(LogplexEventType.pause, TrackFields(playerTimeMs: _posMs));
    }

    if (v.buffering && !_wasBuffering) {
      _bufferStartedAt = DateTime.now();
      client.track(
          LogplexEventType.bufferStart, TrackFields(playerTimeMs: _posMs));
    } else if (!v.buffering && _wasBuffering && v.playing) {
      _endBuffer();
    }

    _wasPlaying = v.playing;
    _wasBuffering = v.buffering;
  }

  void _endBuffer() {
    final startedAt = _bufferStartedAt;
    if (startedAt == null) return;
    _bufferStartedAt = null;
    client.track(
      LogplexEventType.bufferEnd,
      TrackFields(
        playerTimeMs: _posMs,
        bufferDurationMs: DateTime.now().difference(startedAt).inMilliseconds,
      ),
    );
  }

  void _onPosition() {
    if (_suspended || _detached) return;
    final duration = controller.duration.value;
    if (duration <= Duration.zero) return;
    final pct =
        controller.position.value.inMilliseconds / duration.inMilliseconds * 100;
    for (final milestone in const [25, 50, 75, 90]) {
      if (pct >= milestone && _milestonesFired.add(milestone)) {
        client.track(
          switch (milestone) {
            25 => LogplexEventType.progress25,
            50 => LogplexEventType.progress50,
            75 => LogplexEventType.progress75,
            _ => LogplexEventType.progress90,
          },
          TrackFields(playerTimeMs: _posMs),
        );
      }
    }
  }

  /// Pause content tracking (an ad is playing).
  void suspend() {
    if (_suspended) return;
    _suspended = true;
    client.stopHeartbeat();
  }

  /// Resume content tracking after an ad.
  void resumeTracking() {
    _suspended = false;
    // Re-sync flags with the actual state so the next transition is clean.
    _wasPlaying = controller.state.value.playing;
    _wasBuffering = controller.state.value.buffering;
    if (_wasPlaying) client.startHeartbeat(() => _posMs);
  }

  /// Emit `exit`, stop listening. Does NOT destroy the client.
  void detach() {
    if (_detached) return;
    _detached = true;
    client.stopHeartbeat();
    client.track(LogplexEventType.exit, TrackFields(playerTimeMs: _posMs));
    controller.state.removeListener(_onState);
    controller.position.removeListener(_onPosition);
    for (final sub in _subs) {
      sub.cancel();
    }
  }
}
