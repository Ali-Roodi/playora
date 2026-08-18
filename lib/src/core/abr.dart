import 'dart:async';

import 'package:flutter/foundation.dart';

/// Tuning for Playora's adaptive bitrate governor.
///
/// mpv has no ABR of its own: for an HLS master playlist it picks one variant
/// (`--hls-bitrate=max`, i.e. the highest) and stays there, so a viewer whose
/// connection degrades just buffers forever. [PlayoraAbrGovernor] adds the
/// missing feedback loop on top of the regular track selection.
@immutable
class PlayoraAbrConfig {
  const PlayoraAbrConfig({
    this.enabled = true,
    this.startupHeightCeiling = 720,
    this.minBufferAhead = const Duration(seconds: 8),
    this.upshiftBufferAhead = const Duration(seconds: 30),
    this.probeInterval = const Duration(seconds: 2),
    this.upshiftCooldown = const Duration(seconds: 20),
    this.downshiftCooldown = const Duration(seconds: 8),
    this.headroom = 1.3,
    this.allowRenditionSwitching = false,
  });

  /// Master switch. When false, "Auto" behaves as before (mpv's own pick).
  final bool enabled;

  /// Cap for the very first pick of a session, before any measurement exists.
  /// Null starts at the top rendition.
  final int? startupHeightCeiling;

  /// Below this much buffered-ahead media, the governor may step down.
  final Duration minBufferAhead;

  /// Above this much buffered-ahead media, the governor may step up.
  final Duration upshiftBufferAhead;

  /// How often the loop samples buffer/throughput.
  final Duration probeInterval;

  /// Quiet period after a switch before stepping up/down again. Up-shifts
  /// wait longer because they are the risky direction.
  final Duration upshiftCooldown;
  final Duration downshiftCooldown;

  /// Extra measured throughput required before stepping up (1.3 = 30 %).
  final double headroom;

  /// Whether the governor may also switch between manual MP4 renditions.
  /// Off by default: those are separate files, so a switch reloads the media
  /// and the viewer sees a visible hiccup.
  final bool allowRenditionSwitching;
}

/// One rung of the quality ladder the governor can select.
@immutable
class AbrLevel {
  const AbrLevel({required this.index, required this.height, this.bitrate});

  /// Index into the ladder, 0 = lowest quality.
  final int index;
  final int height;

  /// Bits per second, when the stream reports it.
  final int? bitrate;

  /// Relative cost of this rung, used when the manifest reports no bitrate.
  /// Bitrate scales roughly with the pixel count.
  double get weight => bitrate?.toDouble() ?? _heightWeight(height);

  static double _heightWeight(int height) {
    final h = height <= 0 ? 360 : height;
    return 4500000 * (h / 1080) * (h / 1080);
  }
}

/// The decision the governor reached on a tick.
enum AbrDecision { hold, up, down }

/// Fill rate a starving buffer has to beat to be considered recovering.
const double _recoveryHeadroom = 1.1;

/// Buffer-driven ABR loop.
///
/// Throughput is measured as a *fill rate*: how many seconds of media land in
/// the cache per second of wall clock. A fill rate of 2 means the connection
/// delivers the current rendition twice as fast as it plays, so a rung with up
/// to ~2x the bitrate would still keep up. This needs no manifest bandwidth
/// data and self-calibrates to whatever is actually playing.
class PlayoraAbrGovernor {
  PlayoraAbrGovernor({
    required this.config,
    required this.levels,
    required this.currentIndex,
    required this.bufferAhead,
    required this.playing,
    required this.stalled,
    required this.onSwitch,
    this.onLog,
  });

  final PlayoraAbrConfig config;

  /// The ladder, ascending by quality. Re-read every tick — HLS track lists
  /// arrive after the first frames.
  final List<AbrLevel> Function() levels;
  final int? Function() currentIndex;
  final Duration Function() bufferAhead;
  final bool Function() playing;
  final bool Function() stalled;
  final void Function(AbrLevel level, AbrDecision decision) onSwitch;
  final void Function(String message)? onLog;

  Timer? _timer;
  Duration? _lastBuffer;
  DateTime? _lastSampleAt;
  DateTime? _lastSwitchAt;
  AbrDecision _lastDecision = AbrDecision.hold;

  /// Smoothed fill rate (media seconds cached per wall second, playback
  /// included). 1.0 means "exactly keeping up".
  double _fillRate = 1.0;

  double get fillRate => _fillRate;

  AbrDecision get lastDecision => _lastDecision;

  /// Sustained-good counter, so one lucky sample can't trigger an up-shift.
  int _goodTicks = 0;

  void start() {
    if (!config.enabled || _timer != null) return;
    _timer = Timer.periodic(config.probeInterval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Forget measurements — call on every new media source.
  void reset() {
    _lastBuffer = null;
    _lastSampleAt = null;
    _lastSwitchAt = null;
    _fillRate = 1.0;
    _goodTicks = 0;
  }

  void dispose() => stop();

  /// The rung to open a fresh source with, given an optional remembered
  /// height from a previous session.
  AbrLevel? startupLevel(List<AbrLevel> ladder, {int? rememberedHeight}) {
    if (ladder.isEmpty) return null;
    final ceiling = rememberedHeight ?? config.startupHeightCeiling;
    if (ceiling == null) return ladder.last;
    AbrLevel? best;
    for (final level in ladder) {
      if (level.height <= ceiling &&
          (best == null || level.height > best.height)) {
        best = level;
      }
    }
    return best ?? ladder.first;
  }

  @visibleForTesting
  void tick() => _tick();

  void _tick() {
    if (!config.enabled) return;
    final ladder = levels();
    final index = currentIndex();
    if (ladder.length < 2 || index == null) {
      _lastBuffer = null;
      _lastSampleAt = null;
      return;
    }
    final now = DateTime.now();
    final buffered = bufferAhead();
    final isPlaying = playing();

    // ---- measure ---------------------------------------------------------
    final lastAt = _lastSampleAt;
    final lastBuffer = _lastBuffer;
    _lastSampleAt = now;
    _lastBuffer = buffered;
    if (lastAt != null && lastBuffer != null) {
      final elapsed = now.difference(lastAt).inMilliseconds / 1000;
      if (elapsed > 0.25) {
        final drained = isPlaying ? elapsed : 0.0;
        final grown = (buffered - lastBuffer).inMilliseconds / 1000;
        // Media cached per wall second = growth of the buffer plus whatever
        // playback consumed in the meantime.
        final sample = ((grown + drained) / elapsed).clamp(0.0, 20.0);
        _fillRate = _fillRate * 0.6 + sample * 0.4;
      }
    }

    if (!isPlaying) return;

    final safeIndex = index.clamp(0, ladder.length - 1);
    final current = ladder[safeIndex];
    final sinceSwitch =
        _lastSwitchAt == null ? null : now.difference(_lastSwitchAt!);

    // ---- down ------------------------------------------------------------
    // A buffer under the floor is only survivable if it is visibly refilling;
    // "exactly keeping up" leaves nothing for the next dip.
    final starving = buffered < config.minBufferAhead;
    final losing = stalled() || (starving && _fillRate < _recoveryHeadroom);
    if (losing && safeIndex > 0) {
      if (sinceSwitch == null || sinceSwitch >= config.downshiftCooldown) {
        _goodTicks = 0;
        _switch(
          ladder[safeIndex - 1],
          AbrDecision.down,
          'buffer=${buffered.inSeconds}s fill=${_fillRate.toStringAsFixed(2)}',
        );
      }
      return;
    }

    // ---- up --------------------------------------------------------------
    if (safeIndex >= ladder.length - 1) {
      _goodTicks = 0;
      return;
    }
    // A cache that is full (or a whole video ahead) stops growing, so the
    // fill rate reads ~1 even on a fast link. Treat a deep buffer as proof of
    // headroom on its own.
    final saturated = buffered >= config.upshiftBufferAhead * 4;
    if (buffered < config.upshiftBufferAhead) {
      _goodTicks = 0;
      return;
    }
    final next = ladder[safeIndex + 1];
    final needed = (next.weight / current.weight) * config.headroom;
    if (!saturated && _fillRate < needed) {
      _goodTicks = 0;
      return;
    }
    _goodTicks++;
    if (_goodTicks < 3) return;
    if (sinceSwitch != null && sinceSwitch < config.upshiftCooldown) return;
    _goodTicks = 0;
    _switch(
      next,
      AbrDecision.up,
      'buffer=${buffered.inSeconds}s fill=${_fillRate.toStringAsFixed(2)} '
      'needed=${needed.toStringAsFixed(2)}',
    );
  }

  void _switch(AbrLevel level, AbrDecision decision, String why) {
    _lastSwitchAt = DateTime.now();
    _lastDecision = decision;
    // The new rendition starts with an empty cache; don't let that read as a
    // collapsing connection on the next tick.
    _lastBuffer = null;
    _lastSampleAt = null;
    onLog?.call('abr ${decision.name} -> ${level.height}p ($why)');
    onSwitch(level, decision);
  }
}
