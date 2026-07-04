import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import '../models/types.dart';

/// A selectable quality option — either "Auto" (adaptive), an embedded (HLS)
/// video track, or one of the manual MP4 renditions.
@immutable
class QualityOption {
  const QualityOption.auto()
      : isAuto = true,
        height = null,
        label = 'AUTO',
        track = null,
        renditionIndex = null;

  QualityOption.track(mk.VideoTrack this.track)
      : isAuto = false,
        height = track.h,
        label = track.h != null ? '${track.h}p' : (track.title ?? track.id),
        renditionIndex = null;

  const QualityOption.rendition({
    required this.label,
    required int this.renditionIndex,
    this.height,
  })  : isAuto = false,
        track = null;

  final bool isAuto;
  final int? height;
  final String label;
  final mk.VideoTrack? track;
  final int? renditionIndex;
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
  PlayoraController({mk.PlayerConfiguration? configuration})
      : player = mk.Player(
          configuration: configuration ??
              const mk.PlayerConfiguration(title: 'playora'),
        ) {
    videoController = mkv.VideoController(player);
    _bind();
  }

  final mk.Player player;
  late final mkv.VideoController videoController;

  /// Low-frequency consolidated state.
  final ValueNotifier<PlaybackValue> state =
      ValueNotifier(const PlaybackValue());

  /// High-frequency values, separated so the skin can subscribe narrowly.
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> buffer = ValueNotifier(Duration.zero);

  /// Current subtitle cue lines (empty when none). Rendered by the skin.
  final ValueNotifier<List<String>> subtitleCues = ValueNotifier(const []);

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
      s.buffering.listen(
          (buffering) => _update((v) => v.copyWith(buffering: buffering))),
      s.completed.listen((completed) {
        _update((v) => v.copyWith(completed: completed));
        if (completed) _completions.add(null);
      }),
      s.position.listen((p) => position.value = p),
      s.duration.listen((d) {
        duration.value = d;
        if (d > Duration.zero) _update((v) => v.copyWith(canPlay: true));
      }),
      s.buffer.listen((b) => buffer.value = b),
      s.volume.listen((vol) {
        final norm = (vol / 100).clamp(0.0, 1.0);
        _update((v) => v.copyWith(volume: norm, muted: norm == 0));
      }),
      s.rate.listen((rate) => _update((v) => v.copyWith(rate: rate))),
      s.width.listen((w) => _update((v) => v.copyWith(width: w))),
      s.height.listen((h) => _update((v) => v.copyWith(height: h))),
      s.tracks.listen((t) => _update((v) => v.copyWith(tracks: t))),
      s.track.listen((t) {
        final wasVideo = state.value.selected.video;
        _update((v) => v.copyWith(
              selected: t,
              // Selecting an embedded subtitle clears the external one.
              clearExternalSubtitle: !t.subtitle.uri,
            ));
        if (t.video != wasVideo) _qualityChanges.add(t.video);
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
    position.value = startAt ?? Duration.zero;
    await player.open(
      mk.Media(target, start: startAt),
      play: play,
    );
    final def = externalSubtitles.where((e) => e.isDefault).firstOrNull;
    if (def != null) await selectExternalSubtitle(def);
  }

  // ---------------------------------------------------------------- playback

  Future<void> play() => player.play();

  Future<void> pause() => player.pause();

  Future<void> togglePlay() => player.playOrPause();

  /// Seek and record the jump for analytics.
  Future<void> seek(Duration to) async {
    final from = position.value;
    final d = duration.value;
    var clamped = to < Duration.zero ? Duration.zero : to;
    if (d > Duration.zero && clamped > d) clamped = d;
    position.value = clamped; // optimistic, keeps the scrubber snappy
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

  /// Whether adaptive ("Auto") selection is active (embedded sources only).
  bool get isAutoQuality =>
      _renditions == null && state.value.selected.video.id == 'auto';

  /// Label for the quality button — the manual rendition's label, the selected
  /// track's height, or AUTO.
  String get qualityLabel {
    final renditions = _renditions;
    if (renditions != null) {
      final i = state.value.renditionIndex.clamp(0, renditions.length - 1);
      return renditions[i].qualityLabel;
    }
    final v = state.value.selected.video;
    if (v.id == 'auto' || v.id == 'no') return 'AUTO';
    return v.h != null ? '${v.h}p' : 'AUTO';
  }

  Future<void> selectQuality(QualityOption option) async {
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
      await load(
        renditions: renditions,
        externalSubtitles: subs,
        renditionIndex: index,
        startAt: at,
        play: wasPlaying,
      );
      if (active != null) await selectExternalSubtitle(active);
      return;
    }
    if (option.isAuto) {
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
    subtitleCues.dispose();
    await player.dispose();
  }
}
