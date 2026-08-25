import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import '../models/types.dart';
import 'abr.dart';
import 'buffering.dart';
import 'cache_dir_io.dart' if (dart.library.js_interop) 'cache_dir_web.dart';
import 'hls_compat_stub.dart'
    if (dart.library.js_interop) 'hls_compat_web.dart';
import 'mpv_tuning_io.dart' if (dart.library.js_interop) 'mpv_tuning_web.dart';

/// A selectable quality option — either "Auto" (adaptive), an embedded (HLS)
/// video track, or one of the manual MP4 renditions.
@immutable
class QualityOption {
  const QualityOption.auto()
      : isAuto = true,
        height = null,
        label = 'AUTO',
        track = null,
        renditionIndex = null,
        hlsLevelIndex = null;

  QualityOption.track(mk.VideoTrack this.track)
      : isAuto = false,
        height = track.h,
        label = track.h != null ? '${track.h}p' : (track.title ?? track.id),
        renditionIndex = null,
        hlsLevelIndex = null;

  const QualityOption.rendition({
    required this.label,
    required int this.renditionIndex,
    this.height,
  })  : isAuto = false,
        track = null,
        hlsLevelIndex = null;

  /// A quality level of the hls.js instance (web HLS playback only).
  const QualityOption.hlsLevel({
    required this.label,
    required int this.hlsLevelIndex,
    this.height,
  })  : isAuto = false,
        track = null,
        renditionIndex = null;

  final bool isAuto;
  final int? height;
  final String label;
  final mk.VideoTrack? track;
  final int? renditionIndex;
  final int? hlsLevelIndex;
}

/// A selectable audio track (embedded in the stream).
@immutable
class AudioOption {
  const AudioOption(this.track);

  final mk.AudioTrack track;

  String get label =>
      track.title ?? track.language ?? track.id;
}

/// A selectable subtitle option — an embedded track or an external file.
@immutable
class SubtitleOption {
  const SubtitleOption.embedded(mk.SubtitleTrack this.track) : external = null;

  const SubtitleOption.external(ExternalSubtitle this.external) : track = null;

  final mk.SubtitleTrack? track;
  final ExternalSubtitle? external;

  String get label =>
      external?.label ?? track?.title ?? track?.language ?? track?.id ?? '';

  String get id => external?.src ?? track!.id;
}

/// A seek recorded by [PlayoraController.seek] — the analytics layer
/// listens to these (media_kit has no seeking/seeked events of its own).
@immutable
class SeekEvent {
  const SeekEvent(this.from, this.to);

  final Duration from;
  final Duration to;
}

/// Consolidated low-frequency playback state. High-frequency values (position,
/// buffer) live in dedicated [ValueNotifier]s on the controller so per-tick
/// updates don't rebuild the whole skin.
@immutable
class PlaybackValue {
  const PlaybackValue({
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.started = false,
    this.canPlay = false,
    this.volume = 1.0,
    this.muted = false,
    this.rate = 1.0,
    this.width,
    this.height,
    this.tracks = const mk.Tracks(),
    this.selected = const mk.Track(),
    this.activeExternalSubtitle,
    this.renditionIndex = 0,
    this.switchingQuality = false,
    this.error,
  });

  final bool playing;
  final bool buffering;
  final bool completed;

  /// Playback has started at least once for the current source.
  final bool started;

  /// The source is loaded enough to play (duration is known).
  final bool canPlay;

  /// 0..1.
  final double volume;
  final bool muted;
  final double rate;
  final int? width;
  final int? height;
  final mk.Tracks tracks;
  final mk.Track selected;

  /// The external subtitle currently showing, if any.
  final ExternalSubtitle? activeExternalSubtitle;

  /// Index into the manual renditions list (when the source is a list).
  final int renditionIndex;

  /// True while the governor is moving to another rung of the quality ladder.
  /// The move always costs a beat of re-buffering; the skin uses this to hold
  /// the last frame instead of flashing a spinner, so the switch reads as
  /// nothing happening at all.
  final bool switchingQuality;

  final String? error;

  PlaybackValue copyWith({
    bool? playing,
    bool? buffering,
    bool? completed,
    bool? started,
    bool? canPlay,
    double? volume,
    bool? muted,
    double? rate,
    int? width,
    int? height,
    mk.Tracks? tracks,
    mk.Track? selected,
    ExternalSubtitle? activeExternalSubtitle,
    bool clearExternalSubtitle = false,
    int? renditionIndex,
    bool? switchingQuality,
    String? error,
    bool clearError = false,
  }) {
    return PlaybackValue(
      playing: playing ?? this.playing,
      buffering: buffering ?? this.buffering,
      completed: completed ?? this.completed,
      started: started ?? this.started,
      canPlay: canPlay ?? this.canPlay,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      rate: rate ?? this.rate,
      width: width ?? this.width,
      height: height ?? this.height,
      tracks: tracks ?? this.tracks,
      selected: selected ?? this.selected,
      activeExternalSubtitle: clearExternalSubtitle
          ? null
          : (activeExternalSubtitle ?? this.activeExternalSubtitle),
      renditionIndex: renditionIndex ?? this.renditionIndex,
      switchingQuality: switchingQuality ?? this.switchingQuality,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Playback engine of the Playora player — wraps a media_kit [mk.Player] and
/// exposes a Flutter-friendly, testable surface: a [ValueNotifier] for state,
/// dedicated notifiers for the high-frequency position/buffer, quality/audio/
/// subtitle track selection, and mute/volume/rate with 0..1 volume semantics.
///
/// Hosts normally don't construct this — [PlayoraPlayer] owns one and hands
/// it out through `onPlayerReady` for imperative control.
class PlayoraController {
  PlayoraController({
    mk.PlayerConfiguration? configuration,
    PlayoraBufferConfig? buffering,
    PlayoraAbrConfig abr = const PlayoraAbrConfig(),
    mkv.VideoControllerConfiguration? videoConfiguration,
    this.positionUpdateInterval = const Duration(milliseconds: 200),
  })  : bufferConfig = buffering ?? const PlayoraBufferConfig.aggressive(),
        abrConfig = abr,
        player = mk.Player(
          configuration: configuration ??
              mk.PlayerConfiguration(
                title: 'playora',
                // Raised again — on disk — once a writable cache directory is
                // confirmed; this value has to stay RAM-safe.
                bufferSize:
                    (buffering ?? const PlayoraBufferConfig.aggressive())
                        .initialMaxBytes,
              ),
        ) {
    // Must run before the first open(); media_kit consults canPlayType there.
    ensureWebHlsPlayable();
    videoController = mkv.VideoController(
      player,
      configuration:
          videoConfiguration ?? const mkv.VideoControllerConfiguration(),
    );
    _bind();
    _tuning = _applyTuning();
    _governor = PlayoraAbrGovernor(
      config: abrConfig,
      levels: () => [for (final entry in _ladder()) entry.level],
      currentIndex: _currentLadderIndex,
      bufferAhead: () => bufferAhead,
      playing: () => state.value.playing,
      stalled: () => state.value.buffering && state.value.started,
      onSwitch: _applyAbrLevel,
      onLog: (message) {
        if (debugLogging) debugPrint('[playora] $message');
      },
    );
  }

  final mk.Player player;
  late final mkv.VideoController videoController;

  /// Demuxer/network tuning applied to the native backend.
  final PlayoraBufferConfig bufferConfig;

  /// Adaptive quality tuning.
  final PlayoraAbrConfig abrConfig;

  /// Minimum wall-clock gap between [position] notifications. mpv reports the
  /// playhead once per frame; forwarding every one of those rebuilds the
  /// scrubber 25–60 times a second for no visible gain.
  final Duration positionUpdateInterval;

  late final PlayoraAbrGovernor _governor;
  late final Future<void> _tuning;

  /// Backstop that ends a quality switch the new rung never reported back on.
  Timer? _qualitySwitchTimer;
  String? _diskCachePath;

  /// Resolves once the native backend has been tuned. [load] awaits it, so
  /// the first `open()` already runs with the large cache in place.
  Future<void> get ready => _tuning;

  /// The directory backing the demuxer cache, or null when it lives in RAM.
  String? get diskCachePath => _diskCachePath;

  /// Hides embedded renditions from the adaptive ladder, mirroring the same
  /// predicate the quality menu uses.
  bool Function(int height)? qualityValidate;

  /// Height the adaptive ladder should aim for when a source is opened
  /// (typically the last height a previous session settled on).
  int? preferredStartHeight;

  /// Fired whenever the governor settles on a height, so the host can
  /// remember it for the next session.
  ValueChanged<int>? onAutoHeightChanged;

  /// Print `[playora]` diagnostics for the adaptive-quality decisions.
  bool debugLogging = false;

  /// Low-frequency consolidated state.
  final ValueNotifier<PlaybackValue> state =
      ValueNotifier(const PlaybackValue());

  /// High-frequency values, separated so the skin can subscribe narrowly.
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> buffer = ValueNotifier(Duration.zero);

  /// 0..100 while the backend refills after an underrun.
  final ValueNotifier<double> bufferingPercent = ValueNotifier(0);

  /// True while an ad break is on screen. [position] then belongs to the ad,
  /// not to the content — hosts reporting a watch position must skip those.
  final ValueNotifier<bool> adPlaying = ValueNotifier(false);

  /// Current subtitle cue lines (empty when none). Rendered by the skin.
  final ValueNotifier<List<String>> subtitleCues = ValueNotifier(const []);

  /// How much media is cached ahead of the playhead.
  Duration get bufferAhead {
    final ahead = buffer.value - position.value;
    return ahead.isNegative ? Duration.zero : ahead;
  }

  /// Media seconds cached per second of wall clock — 1.0 means the connection
  /// is exactly keeping up with playback. Exposed for diagnostics.
  double get fillRate => _governor.fillRate;

  final StreamController<SeekEvent> _seeks = StreamController.broadcast();
  final StreamController<String> _errors = StreamController.broadcast();
  final StreamController<void> _completions = StreamController.broadcast();
  final StreamController<mk.VideoTrack> _qualityChanges =
      StreamController.broadcast();

  /// Seeks issued through [seek] (from → to).
  Stream<SeekEvent> get onSeek => _seeks.stream;
  Stream<String> get onError => _errors.stream;

  /// Fires when the current source plays to the end.
  Stream<void> get onCompleted => _completions.stream;
  Stream<mk.VideoTrack> get onQualityChanged => _qualityChanges.stream;

  final List<StreamSubscription<dynamic>> _subs = [];
  List<VideoSource>? _renditions;
  List<ExternalSubtitle> _externalSubtitles = const [];
  double _volumeBeforeMute = 1.0;
  bool _disposed = false;

  /// A seek issued before the media reported a duration — mpv silently drops
  /// those, so it's parked here and applied when the duration arrives.
  Duration? _pendingSeek;

  // Position throttling.
  Duration _rawPosition = Duration.zero;
  DateTime _lastPositionPush = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _positionFlush;

  /// Whether the adaptive governor — not a manual pick — owns the quality.
  bool _autoQuality = true;

  /// Whether the ladder has been seeded for the media that is currently open.
  bool _startupLevelApplied = false;

  /// True while [load] is re-opening the same logical source (a rendition
  /// swap), so the ladder and the governor's measurements survive it.
  bool _internalReload = false;

  /// Manual MP4 renditions of the current source, if it was opened as a list.
  List<VideoSource>? get renditions => _renditions;

  /// External subtitles registered for the current source.
  List<ExternalSubtitle> get externalSubtitles => _externalSubtitles;

  void _bind() {
    final s = player.stream;
    _subs.addAll([
      s.playing.listen((playing) {
        _update((v) => v.copyWith(
            playing: playing, started: v.started || playing));
      }),
      s.buffering.listen((buffering) {
        // A stall is the strongest signal the governor gets — surface it
        // right away instead of on the next throttled position tick.
        if (buffering) _flushPosition();
        _update((v) => v.copyWith(buffering: buffering));
        // The new rung has filled its cache: the switch is over.
        if (!buffering) _endQualitySwitch();
      }),
      s.bufferingPercentage.listen((p) => bufferingPercent.value = p),
      s.completed.listen((completed) {
        if (completed) _flushPosition();
        _update((v) => v.copyWith(completed: completed));
        if (completed) _completions.add(null);
      }),
      s.position.listen(_onPosition),
      s.duration.listen((d) {
        duration.value = d;
        if (d > Duration.zero) {
          _update((v) => v.copyWith(canPlay: true));
          final pending = _pendingSeek;
          if (pending != null) {
            _pendingSeek = null;
            final clamped = pending > d ? d : pending;
            _setPosition(clamped);
            player.seek(clamped);
          }
        }
      }),
      s.buffer.listen((b) => buffer.value = b),
      s.volume.listen((vol) {
        final norm = (vol / 100).clamp(0.0, 1.0);
        _update((v) => v.copyWith(volume: norm, muted: norm == 0));
      }),
      s.rate.listen((rate) => _update((v) => v.copyWith(rate: rate))),
      s.width.listen((w) => _update((v) => v.copyWith(width: w))),
      s.height.listen((h) => _update((v) => v.copyWith(height: h))),
      s.tracks.listen((t) {
        _update((v) => v.copyWith(tracks: t));
        // HLS variant lists land a moment after the first frames — that is
        // the first chance to seed the adaptive ladder.
        _seedStartupLevel();
      }),
      s.track.listen((t) {
        final wasVideo = state.value.selected.video;
        _update((v) => v.copyWith(
              selected: t,
              // Selecting an embedded subtitle clears the external one.
              clearExternalSubtitle: !t.subtitle.uri,
            ));
        if (t.video != wasVideo) {
          _qualityChanges.add(t.video);
          final h = t.video.h;
          if (_autoQuality && h != null) onAutoHeightChanged?.call(h);
        }
      }),
      s.subtitle.listen((cues) {
        subtitleCues.value =
            cues.where((c) => c.trim().isNotEmpty).toList(growable: false);
      }),
      s.error.listen((e) {
        _update((v) => v.copyWith(error: e));
        _errors.add(e);
      }),
    ]);
  }

  void _update(PlaybackValue Function(PlaybackValue) fn) {
    if (_disposed) return;
    state.value = fn(state.value);
  }

  // ------------------------------------------------------------- native tune

  Future<void> _applyTuning() async {
    if (!mpvTuningSupported) return;
    final path = await resolveCacheDirectory(bufferConfig);
    if (_disposed) return;
    _diskCachePath = path;
    await setMpvProperties(
      player,
      bufferConfig.mpvProperties(diskCachePath: path),
    );
    if (_disposed || path == null) return;
    // The large cap is only safe because the cache is a file. If this libmpv
    // build refused `cache-on-disk`, that many bytes would land on the heap —
    // pull the cap back to the RAM-safe one.
    final onDisk = await getMpvProperty(player, 'cache-on-disk');
    if (_disposed || onDisk == 'yes') return;
    _diskCachePath = null;
    await setMpvProperties(player, {
      'demuxer-max-bytes': '${bufferConfig.memoryMaxBytes}',
    });
  }

  // -------------------------------------------------------- position throttle

  void _onPosition(Duration p) {
    _rawPosition = p;
    if (positionUpdateInterval <= Duration.zero) {
      position.value = p;
      return;
    }
    final now = DateTime.now();
    final elapsed = now.difference(_lastPositionPush);
    if (elapsed >= positionUpdateInterval) {
      _positionFlush?.cancel();
      _positionFlush = null;
      _lastPositionPush = now;
      position.value = p;
      return;
    }
    _positionFlush ??= Timer(positionUpdateInterval - elapsed, _flushPosition);
  }

  void _flushPosition() {
    _positionFlush?.cancel();
    _positionFlush = null;
    if (_disposed) return;
    _lastPositionPush = DateTime.now();
    position.value = _rawPosition;
  }

  /// Publishes a position we set ourselves (seek, resume, source swap) and
  /// drops any throttled update still queued from the old playhead.
  void _setPosition(Duration value) {
    _positionFlush?.cancel();
    _positionFlush = null;
    _rawPosition = value;
    _lastPositionPush = DateTime.now();
    position.value = value;
  }

  // ---------------------------------------------------------------- ABR glue

  /// The adaptive ladder, ascending by height, paired with the menu option
  /// that selects each rung.
  List<({AbrLevel level, QualityOption option})> _ladder() {
    if (!abrConfig.enabled) return const [];
    if (_renditions != null && !abrConfig.allowRenditionSwitching) {
      return const [];
    }
    // Web HLS has hls.js's own ABR; don't fight it.
    if (webHlsLevels().isNotEmpty) return const [];
    final options = qualityOptions(validate: qualityValidate)
        .where((o) => !o.isAuto && o.height != null)
        .toList()
      ..sort((a, b) => a.height!.compareTo(b.height!));
    return [
      for (var i = 0; i < options.length; i++)
        (
          level: AbrLevel(
            index: i,
            height: options[i].height!,
            bitrate: options[i].track?.bitrate,
          ),
          option: options[i],
        ),
    ];
  }

  int? _currentLadderIndex() {
    if (!_autoQuality) return null;
    final ladder = _ladder();
    if (ladder.isEmpty) return null;
    final renditions = _renditions;
    if (renditions != null) {
      final height = renditions[
              state.value.renditionIndex.clamp(0, renditions.length - 1)]
          .height;
      if (height == null) return null;
      return _indexForHeight(ladder, height);
    }
    final height = state.value.selected.video.h;
    if (height == null) return null;
    return _indexForHeight(ladder, height);
  }

  int? _indexForHeight(
    List<({AbrLevel level, QualityOption option})> ladder,
    int height,
  ) {
    for (final entry in ladder) {
      if (entry.level.height == height) return entry.level.index;
    }
    return null;
  }

  /// Picks the opening rung for a fresh source. mpv would otherwise take the
  /// highest variant of an HLS manifest and stall its way through it.
  void _seedStartupLevel() {
    if (_startupLevelApplied || !_autoQuality || !abrConfig.enabled) return;
    final ladder = _ladder();
    if (ladder.length < 2) return;
    _startupLevelApplied = true;
    final target = _governor.startupLevel(
      [for (final entry in ladder) entry.level],
      rememberedHeight: preferredStartHeight,
    );
    if (target == null) return;
    if (_currentLadderIndex() == target.index) return;
    _applyAbrLevel(target, AbrDecision.hold);
  }

  /// Opens the window during which a re-buffer means "the switch is working",
  /// not "the stream died". Nothing tears the video output down, so the last
  /// decoded frame stays on screen for its duration — the spinner is the only
  /// thing the viewer would otherwise see, and [PlaybackValue.switchingQuality]
  /// is what suppresses it.
  void _beginQualitySwitch() {
    _qualitySwitchTimer?.cancel();
    _update((v) => v.copyWith(switchingQuality: true));
    // Backstop: if the new rung never reports back, stop hiding a real stall.
    _qualitySwitchTimer = Timer(
      abrConfig.switchSettleTime + const Duration(seconds: 2),
      _endQualitySwitch,
    );
  }

  void _endQualitySwitch() {
    _qualitySwitchTimer?.cancel();
    _qualitySwitchTimer = null;
    if (!state.value.switchingQuality) return;
    _update((v) => v.copyWith(switchingQuality: false));
  }

  void _applyAbrLevel(AbrLevel level, AbrDecision decision) {
    if (_disposed) return;
    final ladder = _ladder();
    final entry = ladder
        .where((e) => e.level.index == level.index)
        .firstOrNull;
    if (entry == null) return;
    // The startup seed is excluded: nothing is on screen to protect yet, so
    // the spinner there is honest.
    if (decision != AbrDecision.hold) _beginQualitySwitch();
    onAutoHeightChanged?.call(entry.level.height);
    // Keep `_autoQuality` on — this is the governor moving, not the viewer.
    unawaited(_applyQuality(entry.option));
  }

  /// Open a source. Either a single [url] (HLS/MP4) or a list of MP4
  /// [renditions] for a manual quality menu. Optionally start at [startAt].
  Future<void> load({
    String? url,
    List<VideoSource>? renditions,
    List<ExternalSubtitle> externalSubtitles = const [],
    bool play = false,
    Duration? startAt,
    int renditionIndex = 0,
  }) async {
    assert(url != null || (renditions?.isNotEmpty ?? false));
    // The demuxer cache has to be sized before the first open, otherwise the
    // stream starts on media_kit's 10 s read-ahead.
    await ready;
    if (_disposed) return;
    _pendingSeek = null; // a parked seek belongs to the previous source
    _renditions = renditions;
    _externalSubtitles = externalSubtitles;
    final target = url ?? renditions![renditionIndex].src;
    // Reset per-source state before the new media reports in.
    state.value = state.value.copyWith(
      started: false,
      completed: false,
      canPlay: false,
      renditionIndex: renditionIndex,
      clearError: true,
      clearExternalSubtitle: true,
    );
    _setPosition(startAt ?? Duration.zero);
    buffer.value = startAt ?? Duration.zero;
    if (!_internalReload) {
      // A genuinely new source: forget the old ladder and measurements. A
      // rendition swap driven by the governor keeps both — including the
      // switch window that is hiding its re-buffer.
      _startupLevelApplied = false;
      _governor.reset();
      _endQualitySwitch();
    }
    await player.open(
      mk.Media(target, start: startAt),
      play: play,
    );
    _governor.start();
    final def = externalSubtitles.where((e) => e.isDefault).firstOrNull;
    if (def != null) await selectExternalSubtitle(def);
  }

  // ---------------------------------------------------------------- playback

  Future<void> play() => player.play();

  Future<void> pause() async {
    await player.pause();
    // Land the exact playhead the viewer stopped at — resume points are read
    // straight off [position].
    _flushPosition();
  }

  Future<void> togglePlay() => player.playOrPause();

  /// Seek and record the jump for analytics.
  Future<void> seek(Duration to) async {
    final from = position.value;
    final d = duration.value;
    var clamped = to < Duration.zero ? Duration.zero : to;
    if (d > Duration.zero && clamped > d) clamped = d;
    _setPosition(clamped); // optimistic, keeps the scrubber snappy
    if (d == Duration.zero) {
      // Not ready yet (e.g. the resume banner tapped right after open) —
      // park the seek; the duration listener applies it once known.
      _pendingSeek = clamped;
      _seeks.add(SeekEvent(from, clamped));
      return;
    }
    await player.seek(clamped);
    _seeks.add(SeekEvent(from, clamped));
  }

  /// Seek relative to the current position (e.g. ±10s).
  Future<void> seekBy(Duration delta) => seek(position.value + delta);

  Future<void> setRate(double rate) => player.setRate(rate);

  /// [volume] is 0..1.
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    if (clamped > 0) _volumeBeforeMute = clamped;
    await player.setVolume(clamped * 100);
  }

  Future<void> mute() async {
    if (state.value.volume > 0) _volumeBeforeMute = state.value.volume;
    await player.setVolume(0);
  }

  Future<void> unmute() async {
    final restore = _volumeBeforeMute <= 0 ? 1.0 : _volumeBeforeMute;
    await player.setVolume(restore * 100);
  }

  Future<void> toggleMute() =>
      state.value.muted ? unmute() : mute();

  // ----------------------------------------------------------------- quality

  /// Selectable qualities. Manual renditions when the source is a list;
  /// otherwise the embedded (HLS) video tracks plus "Auto". [validate] hides
  /// embedded renditions whose height fails the predicate (Auto stays).
  List<QualityOption> qualityOptions({bool Function(int height)? validate}) {
    final renditions = _renditions;
    if (renditions != null) {
      return [
        for (var i = 0; i < renditions.length; i++)
          QualityOption.rendition(
            label: renditions[i].qualityLabel,
            renditionIndex: i,
            height: renditions[i].height,
          ),
        if (supportsAutoQuality) const QualityOption.auto(),
      ];
    }
    // Web HLS: mpv track lists stay empty; read the hls.js levels instead.
    final webLevels = webHlsLevels();
    if (webLevels.isNotEmpty) {
      final withHeights = webLevels.where((l) => l.height != null).toList()
        ..sort((a, b) => b.height!.compareTo(a.height!));
      final seenHeights = <int>{};
      return [
        for (final level in withHeights)
          if (seenHeights.add(level.height!) &&
              (validate == null || validate(level.height!)))
            QualityOption.hlsLevel(
              label: '${level.height}p',
              hlsLevelIndex: level.index,
              height: level.height,
            ),
        const QualityOption.auto(),
      ];
    }
    final tracks = state.value.tracks.video
        .where((t) => t.id != 'auto' && t.id != 'no' && t.image != true)
        .where((t) => t.h != null)
        .where((t) => validate == null || validate(t.h!))
        .toList()
      ..sort((a, b) => (b.h ?? 0).compareTo(a.h ?? 0));
    // Deduplicate equal heights (mpv can list codec variants per rendition).
    final seen = <int>{};
    final unique = <mk.VideoTrack>[
      for (final t in tracks)
        if (seen.add(t.h!)) t,
    ];
    return [
      for (final t in unique) QualityOption.track(t),
      const QualityOption.auto(),
    ];
  }

  /// Whether adaptive ("Auto") selection is active.
  ///
  /// On the native backend with the governor enabled this tracks Playora's own
  /// auto mode: mpv itself has no ABR, it just pins the highest HLS variant.
  bool get isAutoQuality {
    if (webHlsLevels().isNotEmpty) return webHlsAutoEnabled();
    if (_renditions != null) {
      return _autoQuality &&
          abrConfig.enabled &&
          abrConfig.allowRenditionSwitching;
    }
    if (abrConfig.enabled && mpvTuningSupported) return _autoQuality;
    return state.value.selected.video.id == 'auto';
  }

  /// Whether the "Auto" entry should be offered at all. Manual MP4 renditions
  /// only get one when the governor is allowed to swap between them.
  bool get supportsAutoQuality {
    if (webHlsLevels().isNotEmpty) return true;
    if (_renditions != null) {
      return abrConfig.enabled && abrConfig.allowRenditionSwitching;
    }
    return true;
  }

  /// Index of the hls.js level currently playing (web only, -1 otherwise).
  int get activeHlsLevel => webHlsCurrentLevel();

  /// Label for the quality button — the manual rendition's label, the selected
  /// track's height, or AUTO.
  String get qualityLabel {
    final renditions = _renditions;
    if (renditions != null) {
      if (isAutoQuality) return 'AUTO';
      final i = state.value.renditionIndex.clamp(0, renditions.length - 1);
      return renditions[i].qualityLabel;
    }
    if (isAutoQuality && webHlsLevels().isEmpty) return 'AUTO';
    final webLevels = webHlsLevels();
    if (webLevels.isNotEmpty) {
      if (webHlsAutoEnabled()) return 'AUTO';
      final current = webHlsCurrentLevel();
      final height = webLevels
          .where((l) => l.index == current)
          .map((l) => l.height)
          .firstOrNull;
      return height != null ? '${height}p' : 'AUTO';
    }
    final v = state.value.selected.video;
    if (v.id == 'auto' || v.id == 'no') return 'AUTO';
    return v.h != null ? '${v.h}p' : 'AUTO';
  }

  /// Viewer-driven selection. Picking a concrete rendition hands quality back
  /// to the viewer; picking "Auto" hands it to the governor.
  Future<void> selectQuality(QualityOption option) async {
    // A viewer-driven switch re-buffers exactly like a governor-driven one, so
    // hide it the same way. Before the first frame there is nothing to hold on
    // screen and the spinner is the honest answer.
    if (state.value.started) _beginQualitySwitch();
    _autoQuality = option.isAuto;
    if (option.isAuto && abrConfig.enabled && webHlsLevels().isEmpty) {
      _governor.reset();
      _startupLevelApplied = false;
      _seedStartupLevel();
      return;
    }
    await _applyQuality(option);
  }

  Future<void> _applyQuality(QualityOption option) async {
    if (option.renditionIndex != null) {
      final renditions = _renditions;
      if (renditions == null) return;
      final index = option.renditionIndex!.clamp(0, renditions.length - 1);
      if (index == state.value.renditionIndex) return;
      // Swap the file but keep position + play state.
      final at = position.value;
      final wasPlaying = state.value.playing;
      final subs = _externalSubtitles;
      final active = state.value.activeExternalSubtitle;
      _internalReload = true;
      try {
        await load(
          renditions: renditions,
          externalSubtitles: subs,
          renditionIndex: index,
          startAt: at,
          play: wasPlaying,
        );
      } finally {
        _internalReload = false;
      }
      if (active != null) await selectExternalSubtitle(active);
      return;
    }
    if (option.hlsLevelIndex != null) {
      setWebHlsLevel(option.hlsLevelIndex!);
      // Labels derive from hls.js state — emit a fresh value so the UI
      // rebuilds (PlaybackValue has identity equality).
      _update((v) => v.copyWith());
      return;
    }
    if (option.isAuto) {
      if (webHlsLevels().isNotEmpty) {
        setWebHlsLevel(-1);
        _update((v) => v.copyWith());
        return;
      }
      await player.setVideoTrack(mk.VideoTrack.auto());
      return;
    }
    if (option.track != null) {
      await player.setVideoTrack(option.track!);
    }
  }

  // ------------------------------------------------------------------- audio

  /// Embedded audio tracks (multi-language). Empty unless there is a choice.
  List<AudioOption> get audioOptions {
    final tracks = state.value.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no' && !t.uri)
        .toList();
    return tracks.length > 1 ? [for (final t in tracks) AudioOption(t)] : const [];
  }

  Future<void> selectAudio(AudioOption option) =>
      player.setAudioTrack(option.track);

  // --------------------------------------------------------------- subtitles

  /// Subtitle choices: embedded (HLS) tracks plus registered external files.
  List<SubtitleOption> get subtitleOptions {
    final embedded = state.value.tracks.subtitle
        .where((t) => t.id != 'auto' && t.id != 'no' && !t.uri && !t.data);
    return [
      for (final t in embedded) SubtitleOption.embedded(t),
      for (final e in _externalSubtitles) SubtitleOption.external(e),
    ];
  }

  /// Whether any subtitle (embedded or external) is currently showing.
  bool get subtitlesOn {
    if (state.value.activeExternalSubtitle != null) return true;
    final s = state.value.selected.subtitle;
    return s.id != 'no' && s.id != 'auto';
  }

  /// The id ([SubtitleOption.id]) of the active subtitle, or null when off.
  String? get activeSubtitleId {
    final ext = state.value.activeExternalSubtitle;
    if (ext != null) return ext.src;
    final s = state.value.selected.subtitle;
    return (s.id == 'no' || s.id == 'auto') ? null : s.id;
  }

  Future<void> selectSubtitle(SubtitleOption option) async {
    if (option.external != null) {
      await selectExternalSubtitle(option.external!);
    } else {
      await player.setSubtitleTrack(option.track!);
    }
  }

  Future<void> selectExternalSubtitle(ExternalSubtitle subtitle) async {
    await player.setSubtitleTrack(mk.SubtitleTrack.uri(
      subtitle.src,
      title: subtitle.label,
      language: subtitle.language,
    ));
    _update((v) => v.copyWith(activeExternalSubtitle: subtitle));
  }

  Future<void> disableSubtitles() async {
    await player.setSubtitleTrack(mk.SubtitleTrack.no());
    _update((v) => v.copyWith(clearExternalSubtitle: true));
  }

  // ----------------------------------------------------------------- cleanup

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _governor.dispose();
    _qualitySwitchTimer?.cancel();
    _positionFlush?.cancel();
    for (final sub in _subs) {
      await sub.cancel();
    }
    await _seeks.close();
    await _errors.close();
    await _completions.close();
    await _qualityChanges.close();
    state.dispose();
    position.dispose();
    duration.dispose();
    buffer.dispose();
    bufferingPercent.dispose();
    adPlaying.dispose();
    subtitleCues.dispose();
    await player.dispose();
  }
}
