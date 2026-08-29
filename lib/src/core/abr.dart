import 'dart:async';

import 'package:flutter/foundation.dart';

/// Tuning for Playora's adaptive bitrate governor.
///
/// mpv has no ABR of its own: for an HLS master playlist it picks one variant
/// (`--hls-bitrate=max`, i.e. the highest) and stays there, so a viewer whose
/// connection degrades just buffers forever. [PlayoraAbrGovernor] adds the
/// missing feedback loop on top of the regular track selection.
///
/// The defaults are tuned for *quality first*: bandwidth is assumed to be
/// cheap, so the governor opens at the top rung, climbs back to it as soon as
/// the measurement allows, and spends its patience on avoiding visible
/// switches rather than on saving traffic.
@immutable
class PlayoraAbrConfig {
  const PlayoraAbrConfig({
    this.enabled = true,
    this.startupHeightCeiling = 720,
    this.minBufferAhead = const Duration(seconds: 6),
    this.upshiftBufferAhead = const Duration(seconds: 12),
    this.runwayBufferAhead = const Duration(seconds: 60),
    this.probeInterval = const Duration(seconds: 1),
    this.upshiftCooldown = const Duration(seconds: 5),
    this.downshiftCooldown = const Duration(seconds: 4),
    this.switchSettleTime = const Duration(seconds: 5),
    this.startupGrace = const Duration(seconds: 5),
    this.upshiftGoodTicks = 2,
    this.headroom = 1.15,
    this.ceilingRelaxTime = const Duration(seconds: 45),
    this.decoderDropTolerance = 4,
    this.manifestTimeout = const Duration(milliseconds: 1500),
    this.allowRenditionSwitching = false,
  });

  /// Master switch. When false, "Auto" behaves as before (mpv's own pick).
  final bool enabled;

  /// Cap for the very first pick of a session, before any measurement exists.
  ///
  /// Opening at the top rendition means downloading the first segments at the
  /// highest bitrate before a single frame appears — on a weak link that is
  /// the long black screen, followed by the downshift the measurement was
  /// always going to force. 720p starts fast on a phone and the governor
  /// climbs from there within seconds when the link allows it. A remembered
  /// height from a previous session wins over this; null restores the old
  /// behaviour of opening at the top rung.
  final int? startupHeightCeiling;

  /// Below this much buffered-ahead media, the governor may step down. It sits
  /// well above zero on purpose: the point is to act *before* mpv's
  /// `cache-pause` freezes the picture, not after.
  final Duration minBufferAhead;

  /// Above this much buffered-ahead media, the governor may step up.
  final Duration upshiftBufferAhead;

  /// Buffer depth that counts as runway. Past it an over-optimistic jump costs
  /// nothing — there is a full minute of media to retreat through before the
  /// viewer could see a stall — so the governor takes the top rung outright
  /// instead of asking the fill rate for permission.
  final Duration runwayBufferAhead;

  /// How often the loop samples buffer/throughput.
  final Duration probeInterval;

  /// Quiet period after a switch before stepping up/down again. Up-shifts
  /// wait longer because they are the risky direction.
  final Duration upshiftCooldown;
  final Duration downshiftCooldown;

  /// Grace period after playback first starts during which the down branch is
  /// off entirely. Opening a source *is* a stall — mpv holds the picture until
  /// `cache-pause-initial` is satisfied — and reading that as a failing link
  /// drops the viewer a rung or two before the first frame has even settled.
  final Duration startupGrace;

  /// Grace period after a switch during which a stall is read as the new rung
  /// filling its cache rather than as the link failing. Without it the switch
  /// itself looks like trouble and the governor chases its own tail.
  final Duration switchSettleTime;

  /// Consecutive good samples required before stepping up, so one lucky tick
  /// cannot trigger a switch.
  final int upshiftGoodTicks;

  /// Extra measured throughput required before stepping up (1.15 = 15 %).
  final double headroom;

  /// How long a rung that just failed stays out of reach, per step back up.
  ///
  /// Without a cap the deep cache creates a loop on a weak link: the buffer
  /// refills at the low rung, the runway rule reads that as room to climb,
  /// the link cannot hold the higher rung, and the viewer pays for a visible
  /// switch in each direction — over and over. A downshift therefore caps the
  /// ladder at the rung the link just proved it can carry, and the cap lifts
  /// one rung at a time from there. Zero disables it.
  final Duration ceilingRelaxTime;

  /// Dropped frames per second that mark the device — not the link — as the
  /// bottleneck.
  ///
  /// A phone that cannot decode 1080p in real time drops frames while the
  /// buffer stays full, so every network-side signal reads healthy and the
  /// governor would hold the rung the viewer is watching as a slideshow.
  /// Sustained drops step it down a rung instead.
  final double decoderDropTolerance;

  /// How long the HLS master playlist may take to arrive before the source is
  /// opened without a ladder. It gates the first frame, so it is short.
  final Duration manifestTimeout;

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
    this.overloaded,
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

  /// Whether the decoder is falling behind — the device, not the link, is the
  /// bottleneck. Null when the platform cannot measure it.
  final bool Function()? overloaded;

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

  /// Highest rung the governor may climb to after a failure, and when that
  /// cap was last moved. It lifts one rung per
  /// [PlayoraAbrConfig.ceilingRelaxTime].
  int? _ceilingIndex;
  DateTime? _ceilingAt;

  /// When playback first got going for the current source. Everything before
  /// that plus [PlayoraAbrConfig.startupGrace] is the stream opening, not the
  /// link struggling.
  DateTime? _playingSince;

  void start() {
    if (!config.enabled || _timer != null) return;
    _timer = Timer.periodic(config.probeInterval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Restarts the settle window — call when a switch has finished opening
  /// its new source, so the refill that follows isn't read as a failing link.
  void noteSwitchSettled() {
    _lastSwitchAt = DateTime.now();
    _lastBuffer = null;
    _lastSampleAt = null;
  }

  /// Forget measurements — call on every new media source.
  void reset() {
    _lastBuffer = null;
    _lastSampleAt = null;
    _lastSwitchAt = null;
    _fillRate = 1.0;
    _goodTicks = 0;
    _ceilingIndex = null;
    _ceilingAt = null;
    _playingSince = null;
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
    _playingSince ??= now;

    final safeIndex = index.clamp(0, ladder.length - 1);
    final current = ladder[safeIndex];
    final sinceSwitch = _lastSwitchAt == null
        ? null
        : now.difference(_lastSwitchAt!);
    // Every switch costs a beat of re-buffering while the new rung fills its
    // cache. Reading that as a failing link would make the governor chase its
    // own tail all the way to the bottom rung.
    final settling =
        sinceSwitch != null && sinceSwitch < config.switchSettleTime;
    // Opening a source looks identical to a failing one: an empty cache, a
    // held picture, no throughput history. Judging it costs the viewer a rung
    // before the first frame has settled.
    final startingUp = now.difference(_playingSince!) < config.startupGrace;

    // ---- down ------------------------------------------------------------
    // A buffer under the floor is only survivable if it is visibly refilling;
    // "exactly keeping up" leaves nothing for the next dip.
    final starving = buffered < config.minBufferAhead;
    final struggling =
        stalled() || (starving && _fillRate < _recoveryHeadroom);
    // A decoder that cannot keep up looks perfectly healthy from the network
    // side: the buffer is full, nothing stalls, and the picture is a
    // slideshow anyway.
    final tooHeavy = overloaded?.call() ?? false;
    // Opening a source and switching rungs both start from an empty cache, a
    // held picture and no throughput history — indistinguishable from a link
    // that just died. Judging either one costs a rung the viewer never needed
    // to lose, and on a switch that is how a ladder walks itself to the
    // bottom one reload at a time.
    final losing = !startingUp && !settling && (struggling || tooHeavy);
    if (losing && safeIndex > 0) {
      if (sinceSwitch == null || sinceSwitch >= config.downshiftCooldown) {
        _goodTicks = 0;
        // Drop straight onto the rung the link can actually carry. Walking
        // down one step at a time on a collapsed connection means one visible
        // switch per step; this costs exactly one. A device that cannot
        // decode says nothing about bandwidth, so that case steps down by one
        // rung and measures again.
        final target = struggling
            ? _affordableIndex(ladder, current).clamp(0, safeIndex - 1)
            : safeIndex - 1;
        // The rung being left just failed: keep the ladder capped at what the
        // link demonstrably carries until the cap has relaxed back up there.
        _ceilingIndex = target;
        _ceilingAt = now;
        _switch(
          ladder[target],
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
    if (buffered < config.upshiftBufferAhead) {
      _goodTicks = 0;
      return;
    }
    // Two ways to earn the climb. Normally the measurement decides how far up
    // the link can carry us. A cache that is full (or a whole video ahead)
    // stops growing, so the fill rate reads ~1 even on a fast link — that much
    // runway earns a probe one rung up, whose retreat the buffer absorbs long
    // before the viewer sees it. It does not earn the top rung: a deep buffer
    // at 360p says nothing about 1080p, and jumping there on a weak link buys
    // a stall, a downshift, and the same jump again.
    final affordable = _affordableIndex(ladder, current);
    var target = affordable;
    if (target <= safeIndex && buffered >= config.runwayBufferAhead) {
      target = safeIndex + 1;
    }
    final ceiling = _relaxedCeiling(now, ladder.length - 1);
    if (target > ceiling) target = ceiling;
    if (target <= safeIndex) {
      _goodTicks = 0;
      return;
    }
    _goodTicks++;
    if (_goodTicks < config.upshiftGoodTicks) return;
    if (sinceSwitch != null && sinceSwitch < config.upshiftCooldown) return;
    _goodTicks = 0;
    _switch(
      ladder[target],
      AbrDecision.up,
      'buffer=${buffered.inSeconds}s fill=${_fillRate.toStringAsFixed(2)}',
    );
  }

  /// The cap left behind by the last downshift, lifted one rung per
  /// [PlayoraAbrConfig.ceilingRelaxTime] and dropped once it clears the top.
  int _relaxedCeiling(DateTime now, int top) {
    final ceiling = _ceilingIndex;
    final at = _ceilingAt;
    if (ceiling == null || at == null) return top;
    final relax = config.ceilingRelaxTime;
    if (relax <= Duration.zero) {
      _ceilingIndex = null;
      _ceilingAt = null;
      return top;
    }
    final steps = now.difference(at).inMilliseconds ~/ relax.inMilliseconds;
    final raised = ceiling + steps;
    if (raised >= top) {
      _ceilingIndex = null;
      _ceilingAt = null;
      return top;
    }
    if (steps > 0) {
      _ceilingIndex = raised;
      _ceilingAt = now;
    }
    return raised;
  }

  /// The highest rung the measured fill rate can carry, with
  /// [PlayoraAbrConfig.headroom] to spare.
  ///
  /// A fill rate of 2 means the connection delivers [current] twice as fast as
  /// it plays, so a rung costing up to ~2x as much would still keep up. The
  /// answer is an absolute ladder index, not a step: the governor moves to the
  /// right rung in one go rather than climbing a staircase of visible
  /// switches.
  int _affordableIndex(List<AbrLevel> ladder, AbrLevel current) {
    final budget = current.weight * (_fillRate / config.headroom);
    var best = 0;
    for (var i = 0; i < ladder.length; i++) {
      if (ladder[i].weight <= budget) best = i;
    }
    return best;
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
