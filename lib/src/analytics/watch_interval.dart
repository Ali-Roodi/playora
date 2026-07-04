import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/controller.dart';
import '../models/analytics_types.dart';

/// Periodic "user watch" heartbeat for an external back-end (the pre-Logplex
/// tracker). Mirrors hamrah-player's `sendUserWatchIntervalHandler`:
///
/// - accumulates real play time (incremented while playing, frozen while
///   paused);
/// - every [interval] reports { playDuration, position, quality, userWatchId };
/// - chains the returned id into the next call;
/// - fires a final report on [dispose] (the orchestrator also reports when the
///   app goes to background);
/// - skips ticks before the first second of playback.
///
/// The host back-end derives traffic from the resolution string and only
/// accepts the exact form "WIDTH*HEIGHT" with a literal asterisk
/// (width*height = pixels, ×playDuration = bytes). Any other shape fails its
/// regex → pixels 0 → traffic 0 while watch duration still climbs. So the
/// quality is always reported as "WIDTH*HEIGHT".
class WatchIntervalReporter {
  WatchIntervalReporter(
    this.controller,
    this.handler, {
    this.interval = const Duration(seconds: 5),
  }) {
    _secondTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_suspended && controller.state.value.playing) _playDuration++;
    });
    _scheduleNext();
  }

  final PlayoraController controller;
  final WatchIntervalHandler handler;
  final Duration interval;

  int _playDuration = 0;
  String? _watchId;
  Timer? _secondTicker;
  Timer? _reportTimer;
  bool _suspended = false;
  bool _disposed = false;

  /// Accumulated play seconds so far (visible for tests).
  int get playDuration => _playDuration;

  /// Suspend accumulation + reporting while an ad plays.
  void suspend() => _suspended = true;

  void resume() => _suspended = false;

  String _currentQuality() {
    final selected = controller.state.value.selected.video;
    final w = selected.w ?? controller.state.value.width;
    final h = selected.h ?? controller.state.value.height;
    return (w != null && h != null) ? '$w*$h' : '';
  }

  void _scheduleNext() {
    if (_disposed) return;
    _reportTimer = Timer(interval, () async {
      await report();
      _scheduleNext();
    });
  }

  /// Send one report now (also used as the final report on teardown).
  Future<void> report() async {
    if (_suspended) return;
    final position = controller.position.value;
    if (position.inMilliseconds <= 1000) return;
    try {
      final result = await handler(WatchIntervalInfo(
        playDuration: _playDuration,
        position: position.inMilliseconds / 1000,
        quality: _currentQuality(),
        userWatchId: _watchId,
      ));
      if (result != null) _watchId = result;
    } catch (e) {
      debugPrint('playora: failed to send watch interval: $e');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _secondTicker?.cancel();
    _reportTimer?.cancel();
    await report();
  }
}
