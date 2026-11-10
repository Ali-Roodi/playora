import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/controller.dart';
import '../core/hls_manifest.dart';
import '../models/analytics_types.dart';

/// Periodic "user watch" heartbeat for an external back-end (the pre-Logplex
/// tracker). Mirrors logplex-player's `sendUserWatchIntervalHandler`:
///
/// - samples once a second, counting a second of play only while frames are
///   actually moving (not paused, not stalled, not waiting on a seek);
/// - reports the resolution as the time-weighted average of what was shown,
///   as "WIDTH*HEIGHT" with a literal asterisk — the host back-end derives
///   traffic from that exact shape and reads anything else as zero pixels;
/// - estimates the bytes fetched from the newly buffered stretch of timeline
///   and the bitrate the manifest advertises for the playing rung, per host;
/// - every [interval] reports, chaining the returned id into the next call,
///   one report at a time;
/// - fires a final report on [dispose].
class WatchIntervalReporter {
  WatchIntervalReporter(
    this.controller,
    this.handler, {
    this.interval = const Duration(seconds: 5),
    this.client,
  }) {
    _sampler = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
    _scheduleNext();
  }

  final PlayoraController controller;
  final WatchIntervalHandler handler;
  final Duration interval;
  /// Used to size a source that has no ladder; a private one when null.
  final http.Client? client;

  final WatchIntervalAccumulator _totals = WatchIntervalAccumulator();
  final _StreamRate _rate = _StreamRate();
  String? _watchId;
  Timer? _sampler;
  Timer? _reportTimer;
  Future<void>? _inFlight;
  bool _suspended = false;
  bool _disposed = false;

  /// Seconds of real playback counted so far.
  int get playDuration => _totals.playDuration;

  /// Suspend sampling and reporting while an ad plays.
  void suspend() => _suspended = true;

  void resume() => _suspended = false;

  void _sample() {
    if (_suspended || _disposed) return;
    final state = controller.state.value;
    final position = controller.position.value.inMilliseconds / 1000;
    final height = state.selected.video.h ?? state.height;
    final width = state.selected.video.w ?? state.width;
    _totals.sample(
      playing: state.playing && state.canPlay && !state.buffering,
      position: position,
      width: width,
      height: height,
      buffered: (position, controller.buffer.value.inMilliseconds / 1000),
      rate: _rate.resolve(controller, height, client),
    );
  }

  void _scheduleNext() {
    if (_disposed) return;
    _reportTimer = Timer(interval, () async {
      await report();
      _scheduleNext();
    });
  }

  /// Send one report now (also used as the final report on teardown). Calls
  /// queue behind the one in flight so a watch id is never raced.
  Future<void> report() {
    final previous = _inFlight ?? Future<void>.value();
    final next = previous.then((_) => _send());
    _inFlight = next;
    return next.whenComplete(() {
      if (identical(_inFlight, next)) _inFlight = null;
    });
  }

  Future<void> _send() async {
    if (_suspended) return;
    final info = _totals.snapshot(
      userWatchId: _watchId,
      fallback: _currentResolution(),
    );
    if (info == null) return;
    try {
      final result = await handler(info);
      if (result != null) _watchId = result;
    } catch (e) {
      debugPrint('playora: failed to send watch interval: $e');
    }
  }

  (int, int)? _currentResolution() {
    final state = controller.state.value;
    final w = state.selected.video.w ?? state.width;
    final h = state.selected.video.h ?? state.height;
    return (w != null && h != null && w > 0 && h > 0) ? (w, h) : null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _sampler?.cancel();
    _reportTimer?.cancel();
    final last = report();
    _disposed = true;
    await last;
  }
}

/// Bytes per second of the playing stream and the host serving it.
typedef StreamRate = ({String host, double bytesPerSecond});

/// The bookkeeping behind [WatchIntervalReporter], free of timers and
/// players so it can be driven sample by sample.
@visibleForTesting
class WatchIntervalAccumulator {
  int _playDuration = 0;
  double _lastPosition = 0;
  double _pixelSeconds = 0;
  int _sizedSeconds = 0;
  double _aspect = 16 / 9;
  double _estimated = 0;
  final Map<String, double> _bytesByHost = {};
  List<(double, double)> _covered = [];

  int get playDuration => _playDuration;

  /// Records one second. [buffered] is the stretch of timeline the player
  /// holds right now; only the part not seen before is charged, at [rate].
  void sample({
    required bool playing,
    required double position,
    required int? width,
    required int? height,
    (double, double)? buffered,
    StreamRate? rate,
  }) {
    if (rate != null && buffered != null && buffered.$2 > buffered.$1) {
      final merged = _merge(_covered, buffered);
      final fresh = _length(merged) - _length(_covered);
      _covered = merged;
      if (fresh > 0) {
        final bytes = fresh * rate.bytesPerSecond;
        _bytesByHost.update(rate.host, (v) => v + bytes, ifAbsent: () => bytes);
        _estimated += bytes;
      }
    }
    if (!playing) return;
    _playDuration++;
    if (position > 0) _lastPosition = position;
    if (width != null && height != null && width > 0 && height > 0) {
      _pixelSeconds += width * height;
      _sizedSeconds++;
      _aspect = width / height;
    }
  }

  /// Time-weighted average resolution as "W*H", or [fallback] before any
  /// sized second was counted.
  String quality([(int, int)? fallback]) {
    if (_sizedSeconds == 0 || _pixelSeconds == 0) {
      return fallback == null ? '' : '${fallback.$1}*${fallback.$2}';
    }
    final average = _pixelSeconds / _sizedSeconds;
    final h = math.max(1, math.sqrt(average / _aspect).round());
    final w = math.max(1, (average / h).round());
    return '$w*$h';
  }

  /// The payload to report, or null while there is nothing worth sending.
  WatchIntervalInfo? snapshot({String? userWatchId, (int, int)? fallback}) {
    if (_lastPosition <= 1 || _playDuration <= 0) return null;
    final byHost = {
      for (final entry in _bytesByHost.entries) entry.key: entry.value.round(),
    };
    final total = byHost.values.fold<int>(0, (sum, v) => sum + v);
    return WatchIntervalInfo(
      playDuration: _playDuration,
      position: _lastPosition,
      quality: quality(fallback),
      userWatchId: userWatchId,
      downloadedBytes: total,
      bytesByHost: byHost,
      estimatedBytes: math.min(total, _estimated.round()),
    );
  }

  static List<(double, double)> _merge(
    List<(double, double)> ranges,
    (double, double) next,
  ) {
    final sorted = [...ranges, next]..sort((a, b) => a.$1.compareTo(b.$1));
    final out = <(double, double)>[];
    for (final range in sorted) {
      if (out.isNotEmpty && range.$1 <= out.last.$2) {
        final last = out.removeLast();
        out.add((last.$1, math.max(last.$2, range.$2)));
      } else {
        out.add(range);
      }
    }
    return out;
  }

  static double _length(List<(double, double)> ranges) =>
      ranges.fold(0, (sum, r) => sum + (r.$2 - r.$1));
}

/// Works out how many bytes a second of the current source costs: from the
/// master playlist's bitrate for the playing rung, or from an MP4's size over
/// its duration. Lookups run once per source, in the background.
class _StreamRate {
  String? _source;
  List<HlsVariant> _variants = const [];
  int _contentLength = 0;

  StreamRate? resolve(
    PlayoraController controller,
    int? height,
    http.Client? client,
  ) {
    final master = controller.hlsMaster;
    if (master != null) {
      final index = controller.currentVariantIndex;
      final variant =
          index != null && index >= 0 && index < master.variants.length
          ? master.variants[index]
          : _nearest(master.variants, height);
      return variant == null ? null : _rateOf(variant);
    }
    final source = controller.sourceUrl;
    if (source == null) return null;
    if (source != _source) _lookup(source, client);
    if (_variants.isNotEmpty) {
      final variant = _nearest(_variants, height);
      return variant == null ? null : _rateOf(variant);
    }
    final seconds = controller.duration.value.inMilliseconds / 1000;
    if (_contentLength > 0 && seconds > 0) {
      return (host: _hostOf(source), bytesPerSecond: _contentLength / seconds);
    }
    return null;
  }

  void _lookup(String source, http.Client? client) {
    _source = source;
    _variants = const [];
    _contentLength = 0;
    final uri = Uri.tryParse(source);
    if (uri == null || !uri.scheme.startsWith('http')) return;
    final active = client ?? http.Client();
    final isPlaylist = RegExp(
      r'\.m3u8(\?|#|$)',
      caseSensitive: false,
    ).hasMatch(source);
    final Future<void> request = isPlaylist
        ? active.get(uri).then((response) {
            if (_source != source || response.statusCode != 200) return;
            _variants =
                parseHlsMaster(
                  response.body,
                  source,
                  minVariants: 1,
                )?.variants ??
                const [];
          })
        : active.head(uri).then((response) {
            if (_source != source) return;
            _contentLength =
                int.tryParse(response.headers['content-length'] ?? '') ?? 0;
          });
    request
        .timeout(const Duration(seconds: 10))
        .catchError((Object _) {})
        .whenComplete(() {
          if (client == null) active.close();
        });
  }

  static HlsVariant? _nearest(List<HlsVariant> variants, int? height) {
    if (variants.isEmpty) return null;
    if (height == null || height <= 0) {
      return variants.reduce(
        (a, b) => b.plannedBitrate > a.plannedBitrate ? b : a,
      );
    }
    return variants.reduce(
      (a, b) =>
          ((b.height ?? 0) - height).abs() < ((a.height ?? 0) - height).abs()
          ? b
          : a,
    );
  }

  static StreamRate _rateOf(HlsVariant variant) =>
      (host: _hostOf(variant.url), bytesPerSecond: variant.plannedBitrate / 8);

  static String _hostOf(String url) => Uri.tryParse(url)?.host ?? '';
}
