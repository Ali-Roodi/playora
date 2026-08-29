import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import '../analytics/client.dart';
import '../analytics/tracker.dart';
import '../analytics/watch_interval.dart';
import '../core/abr.dart';
import '../core/buffering.dart';
import '../core/controller.dart';
import '../core/prefs.dart';
import '../core/vod.dart';
import '../core/vtt_thumbnails.dart';
import '../i18n/strings.dart';
import '../models/analytics_types.dart';
import '../models/types.dart';
import '../theme/player_theme.dart';
import 'overlays/ad_overlay.dart';
import 'overlays/overlays.dart';
import 'skin.dart';

/// An ad break with a stable id (for played-tracking).
class _PositionedAdBreak {
  _PositionedAdBreak(this.id, this.brk);

  final String id;
  final AdBreak brk;
}

/// Playora video player — a production-grade player widget with a custom
/// RTL-aware gold-on-dark skin, HLS/MP4 playback, quality/speed/subtitle/
/// audio menus, pre/mid/post-roll ads, touch gestures, playlist + up-next,
/// optional Logplex analytics with a "continue watching" banner, VOD provider
/// token exchange, and settings persistence.
///
/// Feature-parity port of `logplex-player-react` for Flutter.
class PlayoraPlayer extends StatefulWidget {
  const PlayoraPlayer({
    super.key,
    this.src,
    this.sources,
    this.vodType = VodProvider.standard,
    this.vodCustomUrl,
    this.qualityValidate,
    this.title,
    this.episodeLabel,
    this.poster,
    this.thumbnails,
    this.subtitles = const [],
    this.autoPlay = false,
    this.muted = false,
    this.locale = PlayerLocale.fa,
    this.textDirection,
    this.theme,
    this.appearance = PlayerAppearance.dark,
    this.aspectRatio = 16 / 9,
    this.expand = false,
    this.videoFit = BoxFit.contain,
    this.liveScrubPreview = true,
    this.episodes,
    this.currentEpisodeId,
    this.onEpisodeChange,
    this.ad,
    this.ads,
    this.notice,
    this.restriction,
    this.badge,
    this.loading = false,
    this.fullscreenOnPlay = false,
    this.orientationsAfterFullscreen = DeviceOrientation.values,
    this.analytics,
    this.resume = true,
    this.resumeMode = PlayerResumeMode.prompt,
    this.resolveResume,
    this.onWatchInterval,
    this.watchInterval = const Duration(seconds: 5),
    this.onPlayerReady,
    this.persistSettings = false,
    this.settingsKey = defaultPrefsKey,
    this.buffering,
    this.abr = const PlayoraAbrConfig(),
    this.videoConfiguration,
    this.pauseOnBackground = true,
    this.debugLogging = false,
    this.onBack,
    this.onLike,
    this.liked,
    this.strings,
    this.overlayBuilder,
  }) : assert(
         src != null || sources != null || episodes != null,
         'PlayoraPlayer needs src, sources or episodes',
       );

  /// Source: an HLS/MP4 URL (ignored if `episodes`/`currentEpisodeId` resolve
  /// one). For a non-standard [vodType], an opaque play token.
  final String? src;

  /// MP4 renditions for a manual quality menu (alternative to [src]).
  final List<VideoSource>? sources;

  /// VOD provider. For non-standard providers, [src] is treated as an opaque
  /// play token exchanged for the real stream URL (+ scrub thumbnails).
  final VodProvider vodType;

  /// Override provider API endpoints (per provider); `{token}` is substituted.
  final Map<VodProvider, String>? vodCustomUrl;

  /// Hide embedded (HLS) qualities whose height fails this predicate (e.g.
  /// drop sub-400p renditions). Auto stays available.
  final bool Function(int height)? qualityValidate;
  final String? title;

  /// e.g. "قسمت سوم".
  final String? episodeLabel;

  /// Cover image (before play).
  final String? poster;

  /// WebVTT thumbnails track URL for scrub previews.
  final String? thumbnails;

  /// External subtitle files (HLS-embedded subtitles + audio tracks are
  /// detected automatically).
  final List<ExternalSubtitle> subtitles;
  final bool autoPlay;
  final bool muted;

  /// UI language. fa → RTL text.
  final PlayerLocale locale;

  /// Defaults from locale (fa → rtl, en → ltr). Text-only: layout, controls
  /// order, seek direction and gestures stay physical.
  final TextDirection? textDirection;

  /// Visual token overrides. Defaults from [appearance].
  final PlayoraTheme? theme;
  final PlayerAppearance appearance;

  /// Aspect ratio of the inline player box.
  final double aspectRatio;

  /// Fill the parent instead of sizing to [aspectRatio] — for hosts that give
  /// the player a fixed box (e.g. a full-height portrait page). The video
  /// letterboxes inside per [videoFit]; the control bars pin to the box edges.
  final bool expand;

  /// How the video scales inside the surface (fullscreen included).
  final BoxFit videoFit;

  /// Without a [thumbnails] track, dragging the scrubber pauses and seeks
  /// (throttled, keyframe-fast) so the video surface itself previews the
  /// target frame; playback resumes on release.
  final bool liveScrubPreview;

  /// Playlist; enables the panel + prev/next. [Episode.group] adds season
  /// headers; an up-next card appears near the end.
  final List<Episode>? episodes;
  final String? currentEpisodeId;
  final ValueChanged<String>? onEpisodeChange;

  /// Pre-roll shorthand (single `ads` entry with offset pre).
  final AdConfig? ad;

  /// Multiple ad breaks: pre-roll, mid-rolls and post-roll.
  final List<AdBreak>? ads;

  /// Operator/network (or any) notice shown over the player.
  final PlayerNotice? notice;

  /// Blocking restriction overlay (e.g. IP/network not allowed). Covers the
  /// player and pauses playback while present.
  final PlayerRestriction? restriction;

  /// Short badge (e.g. "تمام‌بها") that animates in at the start and out
  /// after a few seconds.
  final String? badge;

  /// Force the loading overlay — e.g. while the host is still fetching ads.
  /// Also shown automatically while a provider source resolves.
  final bool loading;

  /// Enter fullscreen when playback starts — from the cover tap, or right
  /// away when [autoPlay] (or a pre-roll) starts playback by itself.
  final bool fullscreenOnPlay;

  /// Orientations restored when leaving fullscreen. Pass the portrait pair
  /// in a portrait-locked app; defaults to all orientations.
  final List<DeviceOrientation> orientationsAfterFullscreen;

  /// Built-in Logplex analytics + resume. Omit to disable (no network calls).
  final LogplexAnalyticsConfig? analytics;

  /// Show the "continue watching" resume banner. Needs either [analytics] or
  /// [resolveResume].
  final bool resume;

  /// What to do with a resolved resume point.
  ///
  /// [PlayerResumeMode.prompt] (the default) starts at zero and waits for the
  /// viewer to tap the banner — ignore it and the watch heartbeat overwrites
  /// the stored position with the new near-zero one. [PlayerResumeMode.auto]
  /// opens the media at the saved position instead and offers "start over".
  final PlayerResumeMode resumeMode;

  /// Supply a saved resume point from your own back-end — drives the resume
  /// banner without the Logplex integration.
  final ResumeResolver? resolveResume;

  /// External "user watch" heartbeat for a non-Logplex tracker.
  final WatchIntervalHandler? onWatchInterval;

  /// Cadence of the watch-interval heartbeat.
  final Duration watchInterval;

  /// Exposes the [PlayoraController] for imperative control. Called
  /// with the controller when ready and with null on teardown.
  final ValueChanged<PlayoraController?>? onPlayerReady;

  /// How far ahead the stream is pre-loaded, and how the network stack
  /// behaves on a weak link. Defaults to [PlayoraBufferConfig.aggressive].
  final PlayoraBufferConfig? buffering;

  /// Adaptive quality tuning. mpv itself never switches HLS variants, so this
  /// is what makes "Auto" actually adapt on the native backends.
  final PlayoraAbrConfig abr;

  /// Video-output tuning passed straight to media_kit.
  ///
  /// The default (`vo=gpu`) is right almost everywhere. Android players that
  /// have to run on low-end hardware can hand mpv the decoder's own surface
  /// instead — `VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec:
  /// 'mediacodec')` — which skips a full-frame GPU copy per frame at the cost
  /// of mpv-drawn overlays. Playora draws subtitles in Flutter, so that trade
  /// mostly costs nothing.
  final mkv.VideoControllerConfiguration? videoConfiguration;

  /// Pause playback when the app leaves the foreground — the screen locks,
  /// the viewer switches apps, a call comes in.
  ///
  /// Playback is never resumed automatically: coming back to find the video
  /// has run on without its viewer is worse than one tap. Turn this off only
  /// for a player meant to keep running in the background (audio-style
  /// playback with its own notification).
  final bool pauseOnBackground;

  /// Print `[playora]` diagnostics for the resume, buffering and adaptive
  /// quality paths. Debug builds only — it is a no-op in release.
  final bool debugLogging;

  /// Remember volume/mute/speed/brightness and restore them next session.
  final bool persistSettings;

  /// Storage key for persisted settings (scope per app/profile).
  final String settingsKey;

  /// Show a back button in the top bar.
  final VoidCallback? onBack;

  /// Show a Like button. Called when toggled; emits a `like` event when liked.
  final ValueChanged<bool>? onLike;

  /// Controlled like state.
  final bool? liked;

  /// Override the built-in fa/en strings.
  final PlayerStrings? strings;

  /// Extra overlays rendered inside the player surface.
  final List<Widget> Function(BuildContext context)? overlayBuilder;

  @override
  State<PlayoraPlayer> createState() => PlayoraPlayerState();
}

class PlayoraPlayerState extends State<PlayoraPlayer>
    with WidgetsBindingObserver {
  static bool _mediaKitReady = false;

  late final PlayoraController _controller;
  late PlayerPrefsStore _prefsStore;

  // Source resolution.
  bool _vodLoading = false;
  String? _resolvedThumbnailsUrl;
  ThumbnailTrack? _thumbnailTrack;
  int _loadGeneration = 0;

  // Cover.
  bool _coverDismissed = false;

  // Ads.
  List<_PositionedAdBreak> _adBreaks = const [];
  final Set<String> _playedAds = {};
  _PositionedAdBreak? _activeAd;
  Duration? _resumeAfterAd;

  /// Content duration captured when a post-roll starts (the controller's
  /// duration belongs to the ad creative while it plays).
  Duration _contentEnd = Duration.zero;

  // Episodes.
  String? _episodeId;
  bool _wasPlaying = false;
  bool _forcePlayNext = false;

  /// A src-less episode was selected; the host is resolving the stream and
  /// will swap `widget.src`.
  bool _awaitingHostSource = false;
  bool _pendingEpisodePlay = false;

  /// The episode the currently-loaded media belongs to (null for a plain
  /// src). Lets an episode re-selection that maps to the already-loaded
  /// media (a host revert) skip the reload.
  String? _loadedEpisodeId;

  // Analytics.
  LogplexAnalyticsClient? _analyticsClient;
  PlayerAnalyticsTracker? _tracker;
  WatchIntervalReporter? _watchReporter;
  LogplexAnalyticsConfig? _activeAnalyticsCfg;

  // Resume banner.
  ResumePoint? _resumePoint;
  bool _resumeFetched = false;

  // Fullscreen.
  bool _isFullscreen = false;

  /// Bumped on every setState so the fullscreen route (a separate element
  /// tree) re-renders orchestrator-level changes (ads, loading, resume, …).
  final ValueNotifier<int> _revision = ValueNotifier(0);

  // Persistence debounce.
  Timer? _persistDebounce;
  double? _lastSavedVolume;
  bool? _lastSavedMuted;
  double? _lastSavedRate;
  int? _lastSavedAutoHeight;
  Timer? _autoHeightDebounce;

  Widget? _cachedVideo;
  BoxFit? _cachedVideoFit;

  StreamSubscription<void>? _completedSub;

  Episode? get _episode {
    final episodes = widget.episodes;
    if (episodes == null || episodes.isEmpty) return null;
    return episodes.firstWhere(
      (e) => e.id == widget.currentEpisodeId,
      orElse: () => episodes.first,
    );
  }

  int get _episodeIndex {
    final episodes = widget.episodes;
    final episode = _episode;
    if (episodes == null || episode == null) return -1;
    return episodes.indexOf(episode);
  }

  bool get _hasPrev => _episodeIndex > 0;

  bool get _hasNext {
    final episodes = widget.episodes;
    return episodes != null &&
        _episodeIndex >= 0 &&
        _episodeIndex < episodes.length - 1;
  }

  Episode? get _nextEpisode =>
      _hasNext ? widget.episodes![_episodeIndex + 1] : null;

  String? get _effectivePoster => _episode?.poster ?? widget.poster;
  String? get _effectiveTitle => widget.title ?? _episode?.title;
  String? get _effectiveEpisodeLabel =>
      widget.episodeLabel ?? _episode?.subtitle;

  @override
  void initState() {
    super.initState();
    if (!_mediaKitReady) {
      mk.MediaKit.ensureInitialized();
      _mediaKitReady = true;
    }
    WidgetsBinding.instance.addObserver(this);
    _controller = PlayoraController(
      // mpv's own log is the only way to see where a slow open goes.
      logLevel: widget.debugLogging ? mk.MPVLogLevel.info : null,
      buffering: widget.buffering,
      abr: widget.abr,
      videoConfiguration: widget.videoConfiguration,
    );
    _controller.qualityValidate = widget.qualityValidate;
    _controller.debugLogging = widget.debugLogging;
    _controller.onAutoHeightChanged = _onAutoHeightChanged;
    _prefsStore = PlayerPrefsStore(widget.settingsKey);
    _episodeId = _episode?.id;
    _adBreaks = _normalizeAdBreaks();
    _completedSub = _controller.onCompleted.listen((_) => _onCompleted());
    _controller.position.addListener(_checkMidRolls);
    _controller.state.addListener(_onPlaybackState);
    _setupAnalytics();
    _bootstrap();
    widget.onPlayerReady?.call(_controller);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _revision.value++;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _revision.dispose();
    widget.onPlayerReady?.call(null);
    _persistDebounce?.cancel();
    _autoHeightDebounce?.cancel();
    _completedSub?.cancel();
    _controller.position.removeListener(_checkMidRolls);
    _controller.state.removeListener(_onPlaybackState);
    _tracker?.detach();
    _watchReporter?.dispose();
    _analyticsClient?.destroy();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }
    // The app is going away: stop the video where the viewer left it, then
    // flush the pending analytics and a final watch report so the last
    // position isn't lost (the pagehide equivalent). `hidden` is the earliest
    // of the three — on a screen lock it arrives while the picture is still
    // up, so nothing plays on into a locked phone.
    if (widget.pauseOnBackground && _controller.state.value.playing) {
      _log('lifecycle $state -> pause');
      _controller.pause();
    }
    _analyticsClient?.flush();
    _watchReporter?.report();
  }

  @override
  void didUpdateWidget(PlayoraPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;

    // Host prop changes (liked, title, notice, …) must also reach the
    // fullscreen route — it lives in a separate element tree and only
    // re-renders off this notifier and the playback state. Deferred:
    // notifying mid-build would mark a sibling route dirty.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revision.value++;
    });

    if (old.ad != widget.ad || !listEquals(old.ads, widget.ads)) {
      // A new ad schedule (e.g. the host refetched ads for a new episode)
      // starts a fresh played-state; the old one belonged to the old list.
      _adBreaks = _normalizeAdBreaks();
      _playedAds.clear();
      // A pending pre-roll only makes sense while the content is still at the
      // start (the schedule usually lands right after an episode loads).
      if (_activeAd == null &&
          _controller.position.value < const Duration(seconds: 10)) {
        final pre = _nextPendingAd((b) => b.brk.offset.isPre);
        if (pre != null) {
          _resumeAfterAd = _controller.position.value;
          _controller.pause();
          _playAd(pre);
        }
      }
    }
    if (old.settingsKey != widget.settingsKey) {
      _prefsStore = PlayerPrefsStore(widget.settingsKey);
    }

    // Restriction appeared → pause immediately.
    if (widget.restriction != null && old.restriction == null) {
      _controller.pause();
    }

    final episodeChanged = _episode?.id != _episodeId;
    final sourceChanged =
        old.src != widget.src ||
        !listEquals(old.sources, widget.sources) ||
        old.vodType != widget.vodType;

    if (episodeChanged && _episodeId == null && !sourceChanged) {
      // The playlist arrived after mount for the content that is already
      // playing (hosts often fetch it async) — adopt it, don't reload.
      _episodeId = _episode?.id;
      _loadedEpisodeId ??= _episodeId;
    } else if (episodeChanged && _episode == null) {
      // Playlist removed — keep playing the current source.
      _episodeId = null;
    } else if (episodeChanged) {
      // Resume playback automatically if it was already playing (so the new
      // episode plays without a separate tap). Auto-advance forces play.
      final play = _wasPlaying || _forcePlayNext || _pendingEpisodePlay;
      _forcePlayNext = false;
      _episodeId = _episode?.id;
      // Each episode gets its own continue-watching offer.
      _resumeFetched = false;
      _resumePoint = null;
      final episode = _episode;
      if (episode?.id == _loadedEpisodeId && !sourceChanged) {
        // Back to the episode whose media is already loaded — e.g. the host
        // couldn't resolve the previously selected one and reverted. Cancel
        // the wait and keep going.
        _awaitingHostSource = false;
        _pendingEpisodePlay = false;
        if (_vodLoading) setState(() => _vodLoading = false);
        if (play) _controller.play();
      } else if (episode != null &&
          episode.src == null &&
          episode.sources == null &&
          !sourceChanged) {
        // Host-resolved episode: pause on a spinner until the host swaps
        // `src` (see [Episode.src]). (When the host swaps id + src in one
        // rebuild, sourceChanged is true and we load right away below.)
        _setupAnalytics();
        _awaitingHostSource = true;
        _pendingEpisodePlay = play;
        _controller.pause();
        setState(() => _vodLoading = true);
      } else {
        _setupAnalytics();
        _awaitingHostSource = false;
        _loadContent(play: play, startAt: Duration.zero);
      }
    } else if (sourceChanged) {
      if (_awaitingHostSource) {
        // The host delivered the stream for the episode selected above —
        // analytics identity was already re-keyed there.
        _awaitingHostSource = false;
        final play = _pendingEpisodePlay;
        _pendingEpisodePlay = false;
        setState(() => _vodLoading = false);
        _loadContent(play: play, startAt: Duration.zero);
      } else {
        _setupAnalytics();
        _loadContent(play: _wasPlaying, startAt: Duration.zero);
      }
    } else if (_analyticsConfigIdentityChanged(
      old.analytics,
      widget.analytics,
    )) {
      _setupAnalytics();
    }
  }

  // ------------------------------------------------------------------- setup

  List<_PositionedAdBreak> _normalizeAdBreaks() {
    final list = <_PositionedAdBreak>[];
    final ad = widget.ad;
    if (ad != null) {
      list.add(
        _PositionedAdBreak(
          'pre',
          AdBreak(
            src: ad.src,
            skipAfter: ad.skipAfter,
            clickThrough: ad.clickThrough,
          ),
        ),
      );
    }
    final ads = widget.ads;
    if (ads != null) {
      for (var i = 0; i < ads.length; i++) {
        list.add(_PositionedAdBreak('ads-$i', ads[i]));
      }
    }
    return list;
  }

  Future<void> _bootstrap() async {
    if (widget.persistSettings) await _restorePrefs();
    if (widget.muted) await _controller.mute();

    final pre = _nextPendingAd((b) => b.brk.offset.isPre);
    if (pre != null) {
      _coverDismissed = true;
      _resumeAfterAd = Duration.zero;
      _maybeFullscreenOnAutoStart();
      await _playAd(pre);
      return;
    }
    if (widget.autoPlay) {
      _coverDismissed = true;
      _maybeFullscreenOnAutoStart();
    }
    await _loadContent(play: widget.autoPlay);
  }

  Future<void> _restorePrefs() async {
    final prefs = await _prefsStore.load();
    if (!mounted) return;
    if (prefs.volume != null) await _controller.setVolume(prefs.volume!);
    if (prefs.muted == true) await _controller.mute();
    if (prefs.rate != null) await _controller.setRate(prefs.rate!);
    _controller.preferredStartHeight = prefs.autoHeight;
    _lastSavedVolume = prefs.volume;
    _lastSavedMuted = prefs.muted;
    _lastSavedRate = prefs.rate;
    _lastSavedAutoHeight = prefs.autoHeight;
  }

  bool _analyticsConfigIdentityChanged(
    LogplexAnalyticsConfig? a,
    LogplexAnalyticsConfig? b,
  ) {
    if (identical(a, b)) return false;
    if (a == null || b == null) return true;
    return a.baseUrl != b.baseUrl ||
        a.apiKey != b.apiKey ||
        a.contentId != b.contentId ||
        a.userId != b.userId ||
        a.sessionId != b.sessionId ||
        a.disabled != b.disabled;
  }

  /// (Re)create the analytics client + tracker + watch reporter for the
  /// current config/episode identity.
  void _setupAnalytics() {
    _tracker?.detach();
    _analyticsClient?.destroy();
    _tracker = null;
    _analyticsClient = null;
    _activeAnalyticsCfg = null;

    final base = widget.analytics;
    if (base != null && !base.disabled) {
      // Per-episode content id so reports change when the episode changes.
      final episode = _episode;
      final cfg = base.copyWith(
        contentId: episode?.contentId,
        contentDuration: base.contentDuration ?? episode?.duration,
        contentTitle: base.contentTitle ?? _effectiveTitle,
      );
      _activeAnalyticsCfg = cfg;
      final client = LogplexAnalyticsClient(cfg)
        ..start()
        ..registerContent();
      _analyticsClient = client;
      _tracker = PlayerAnalyticsTracker(client, _controller);
      if (_activeAd != null) _tracker!.suspend();
    }

    _watchReporter?.dispose();
    _watchReporter = null;
    final onWatch = widget.onWatchInterval;
    if (onWatch != null) {
      _watchReporter = WatchIntervalReporter(
        _controller,
        onWatch,
        interval: widget.watchInterval,
      );
      if (_activeAd != null) _watchReporter!.suspend();
    }

    _maybeFetchResume();
  }

  /// `[playora]` diagnostics, opt-in via [PlayoraPlayer.debugLogging].
  void _log(String message) {
    if (!widget.debugLogging) return;
    debugPrint('[playora] $message');
  }

  bool get _resumeEnabled =>
      widget.resume &&
      (widget.resolveResume != null || _activeAnalyticsCfg != null);

  Future<ResumePoint?> _fetchResumePoint() async {
    final source =
        widget.resolveResume ??
        () => _analyticsClient?.getResume() ?? Future.value(null);
    try {
      // Auto mode blocks the first open() on this call — a back-end having a
      // bad day must not hold playback hostage.
      final point = await source().timeout(const Duration(seconds: 5));
      _log(
        'resume resolved: ${point == null ? 'none' : '${point.position} '
                  '(completed=${point.completed})'}',
      );
      return point;
    } catch (e) {
      _log('resume lookup failed: $e');
      return null;
    }
  }

  /// Whether a point is worth acting on at all.
  bool _resumeUsable(ResumePoint? point) =>
      point != null && !point.completed && point.position.inSeconds > 5;

  /// [PlayerResumeMode.auto]: the position the next [_loadContent] should open
  /// at. Resolved before the first `open()` so mpv's own `start:` does the
  /// seek — mid-flight seeks right after open are the unreliable ones.
  Future<Duration?> _autoResumeStart() async {
    if (_resumeFetched || !_resumeEnabled) return null;
    _resumeFetched = true;
    final point = await _fetchResumePoint();
    if (!mounted || !_resumeUsable(point)) return null;
    _log('auto-resume at ${point!.position}');
    // The card doubles as the "start over" offer in this mode.
    setState(() => _resumePoint = point);
    return point.position;
  }

  void _maybeFetchResume() {
    if (_resumeFetched) return;
    if (widget.resumeMode == PlayerResumeMode.auto) return; // handled on load
    // (A pre-roll no longer suppresses this — the banner lives in the skin,
    // which isn't shown while an ad plays, so it appears after the ad.)
    if (!_resumeEnabled) return;
    _resumeFetched = true;
    _fetchResumePoint().then((point) {
      if (!mounted) return;
      // Only offer it when it's worth showing.
      if (_resumeUsable(point)) {
        setState(() => _resumePoint = point);
      }
    });
  }

  // ------------------------------------------------------------------ source

  Future<void> _loadContent({bool play = false, Duration? startAt}) async {
    final generation = ++_loadGeneration;
    var start = startAt;
    if (start == null && widget.resumeMode == PlayerResumeMode.auto) {
      start = await _autoResumeStart();
      if (!mounted || generation != _loadGeneration) return;
    }
    final episode = _episode;
    final sources = episode?.sources ?? widget.sources;
    final rawSrc = episode?.src ?? widget.src;
    final thumbnailsUrl = episode?.thumbnails ?? widget.thumbnails;

    if (sources != null && sources.isNotEmpty) {
      // Manual MP4 renditions — provider resolution doesn't apply.
      _resolvedThumbnailsUrl = thumbnailsUrl;
      _log('load renditions (${sources.length}) play=$play start=$start');
      await _controller.load(
        renditions: sources,
        externalSubtitles: widget.subtitles,
        play: play,
        startAt: start,
      );
      _loadedEpisodeId = _episodeId;
      _fetchThumbnails(generation);
      return;
    }
    if (rawSrc == null) return;

    var url = rawSrc;
    _resolvedThumbnailsUrl = thumbnailsUrl;
    if (widget.vodType != VodProvider.standard) {
      setState(() => _vodLoading = true);
      try {
        final resolved = await resolveVodSource(
          rawSrc,
          widget.vodType,
          customUrl: widget.vodCustomUrl,
        );
        if (!mounted || generation != _loadGeneration) return;
        url = resolved.src;
        _resolvedThumbnailsUrl = resolved.thumbnails ?? thumbnailsUrl;
      } catch (e) {
        if (mounted && generation == _loadGeneration) {
          setState(() => _vodLoading = false);
        }
        debugPrint('playora: VOD resolution failed: $e');
        return;
      }
      if (mounted) setState(() => _vodLoading = false);
    }

    _log('load url play=$play start=$start');
    await _controller.load(
      url: url,
      externalSubtitles: widget.subtitles,
      play: play,
      startAt: start,
    );
    _loadedEpisodeId = _episodeId;
    _fetchThumbnails(generation);
  }

  Future<void> _fetchThumbnails(int generation) async {
    final url = _resolvedThumbnailsUrl;
    if (url == null) {
      if (mounted) setState(() => _thumbnailTrack = null);
      return;
    }
    final track = await ThumbnailTrack.fetch(url);
    if (mounted && generation == _loadGeneration) {
      setState(() => _thumbnailTrack = track.isEmpty ? null : track);
    }
  }

  // --------------------------------------------------------------------- ads

  _PositionedAdBreak? _nextPendingAd(bool Function(_PositionedAdBreak) test) {
    for (final b in _adBreaks) {
      if (!_playedAds.contains(b.id) && test(b)) return b;
    }
    return null;
  }

  Future<void> _playAd(_PositionedAdBreak ad) async {
    _tracker?.suspend();
    _watchReporter?.suspend();
    _analyticsClient
      ?..track(LogplexEventType.adRequest)
      ..track(LogplexEventType.adStart);
    setState(() => _activeAd = ad);
    _controller.adPlaying.value = true;
    await _controller.load(url: ad.brk.src, play: true);
  }

  Future<void> _endAd() async {
    final ad = _activeAd;
    if (ad == null) return;
    _playedAds.add(ad.id);
    _analyticsClient?.track(LogplexEventType.adComplete);
    setState(() => _activeAd = null);
    _controller.adPlaying.value = false;

    final resumeAt = _resumeAfterAd;
    _resumeAfterAd = null;
    if (resumeAt != null) {
      // Pre/mid-roll → restore the content position and keep playing.
      await _loadContent(play: true, startAt: resumeAt);
    } else {
      // Post-roll → the content stays ended (last frame, paused).
      await _loadContent(
        play: false,
        startAt: _contentEnd > Duration.zero ? _contentEnd : null,
      );
    }
    _tracker?.resumeTracking();
    _watchReporter?.resume();
  }

  void _checkMidRolls() {
    if (_activeAd != null || _adBreaks.isEmpty) return;
    if (!_controller.state.value.playing) return;
    final position = _controller.position.value;
    final mid = _nextPendingAd(
      (b) => b.brk.offset.isMid && position >= b.brk.offset.at!,
    );
    if (mid != null) {
      _resumeAfterAd = position;
      _controller.pause();
      _playAd(mid);
    }
  }

  void _onCompleted() {
    if (_activeAd != null) {
      // The ad creative ended naturally.
      _endAd();
      return;
    }
    final post = _nextPendingAd((b) => b.brk.offset.isPost);
    if (post != null) {
      _resumeAfterAd = null; // content stays ended after a post-roll
      _contentEnd = _controller.duration.value;
      _playAd(post);
      return;
    }
    // No (remaining) post-roll → auto-advance to the next episode.
    if (_hasNext) {
      _forcePlayNext = true;
      widget.onEpisodeChange?.call(_nextEpisode!.id);
    }
  }

  // ------------------------------------------------------------------- state

  void _onPlaybackState() {
    final state = _controller.state.value;
    if (_activeAd == null) _wasPlaying = state.playing;

    // A restriction blocks playback — keep it paused (guards autoplay).
    if (widget.restriction != null && state.playing) {
      _controller.pause();
    }

    if (widget.persistSettings) _schedulePersist(state);
  }

  void _schedulePersist(PlaybackValue state) {
    if (state.volume == _lastSavedVolume &&
        state.muted == _lastSavedMuted &&
        state.rate == _lastSavedRate) {
      return;
    }
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 400), () {
      final s = _controller.state.value;
      _lastSavedVolume = s.volume;
      _lastSavedMuted = s.muted;
      _lastSavedRate = s.rate;
      _prefsStore.save(
        PlayerPrefs(volume: s.volume, muted: s.muted, rate: s.rate),
      );
    });
  }

  /// The governor settled on a height — remember it so the next session can
  /// open there instead of probing up from the startup ceiling again.
  void _onAutoHeightChanged(int height) {
    if (!widget.persistSettings || height == _lastSavedAutoHeight) return;
    _autoHeightDebounce?.cancel();
    _autoHeightDebounce = Timer(const Duration(seconds: 5), () {
      _lastSavedAutoHeight = height;
      _prefsStore.save(PlayerPrefs(autoHeight: height));
    });
  }

  void _onLike(bool liked) {
    if (liked) _analyticsClient?.track(LogplexEventType.like);
    widget.onLike?.call(liked);
  }

  /// Resume-banner tap. mpv silently drops seeks issued between `open()` and
  /// the first frame (common on Android when the banner is tapped right
  /// away), so before playback has really started the source is reloaded
  /// with mpv's reliable `start:` — once playing, a plain seek.
  Future<void> _resumeFrom(Duration position) async {
    final state = _controller.state.value;
    _log(
      'resume tapped -> $position '
      '(started=${state.started} canPlay=${state.canPlay})',
    );
    if (state.started && state.canPlay) {
      await _controller.seek(position);
      await _controller.play();
    } else {
      await _loadContent(play: true, startAt: position);
    }
  }

  /// "Start over" from the auto-resume card.
  Future<void> _restartFromStart() async {
    _log('restart from zero');
    final state = _controller.state.value;
    if (state.started && state.canPlay) {
      await _controller.seek(Duration.zero);
      await _controller.play();
    } else {
      await _loadContent(play: true, startAt: Duration.zero);
    }
  }

  // -------------------------------------------------------------- fullscreen

  /// [fullscreenOnPlay] applied to self-starting playback (autoplay or a
  /// pre-roll) — the cover is never shown, so its onPlay hook never fires.
  void _maybeFullscreenOnAutoStart() {
    if (!widget.fullscreenOnPlay || _isFullscreen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isFullscreen) _toggleFullscreen();
    });
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      Navigator.of(context, rootNavigator: true).maybePop();
      return;
    }
    setState(() => _isFullscreen = true);
    await _enterSystemFullscreen();
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        settings: const RouteSettings(name: 'playora_fullscreen'),
        pageBuilder: (_, _, _) => _FullscreenPage(playerState: this),
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    // Route popped (button, back gesture, or system back).
    if (mounted) setState(() => _isFullscreen = false);
    await _exitSystemFullscreen();
  }

  bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _enterSystemFullscreen() async {
    if (!_mobile) return;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Force landscape only for landscape (or unknown-size) video.
    final state = _controller.state.value;
    final landscapeVideo =
        state.width == null ||
        state.height == null ||
        state.width! >= state.height!;
    if (landscapeVideo) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _exitSystemFullscreen() async {
    if (!_mobile) return;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(
      widget.orientationsAfterFullscreen,
    );
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_isFullscreen) {
      // The fullscreen route hosts the surface; keep the inline box black.
      if (widget.expand) return const ColoredBox(color: Colors.black);
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: const ColoredBox(color: Colors.black),
      );
    }
    if (widget.expand) return buildSurface(context, fullscreen: false);
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: buildSurface(context, fullscreen: false),
    );
  }

  /// The video texture. Cached and kept identical across rebuilds: the state
  /// notifier fires on every buffering flip and the fullscreen route rebuilds
  /// the whole surface off it, and re-creating the surface widget each time
  /// costs a texture re-attach on low-end devices. A [RepaintBoundary] keeps
  /// the video frames from repainting the control layers above them.
  Widget get _videoSurface {
    final cached = _cachedVideo;
    if (cached != null && _cachedVideoFit == widget.videoFit) return cached;
    _cachedVideoFit = widget.videoFit;
    // Both engines are laid out at full size, always. A warm quality switch
    // only moves the curtain between them: the engine taking over has been
    // rendering into a surface of the right size all along, so there is no
    // resize — and no black frame — at the moment it becomes the picture.
    return _cachedVideo = RepaintBoundary(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _controller.videoOutput,
          _controller.standbyOutput,
        ]),
        builder: (context, _) {
          final standby = _controller.standbyOutput.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (standby != null)
                Opacity(
                  opacity: 0,
                  child: IgnorePointer(child: _videoFor(standby)),
                ),
              _videoFor(_controller.videoOutput.value),
            ],
          );
        },
      ),
    );
  }

  Widget _videoFor(mkv.VideoController controller) => mkv.Video(
        // Keyed on the engine: media_kit's Video widget takes its controller
        // once, so a swap has to give it a new element to attach to — without
        // this the picture stays on the engine that just stepped back, which
        // is stopped, which is black.
        key: ValueKey<mkv.VideoController>(controller),
        controller: controller,
        controls: mkv.NoVideoControls,
        fit: widget.videoFit,
        fill: Colors.black,
        subtitleViewConfiguration: const mkv.SubtitleViewConfiguration(
          visible: false,
        ),
      );

  /// The full player surface (video + skin + overlays). Reused by the
  /// fullscreen route.
  Widget buildSurface(BuildContext context, {required bool fullscreen}) {
    final theme = widget.theme ?? PlayoraTheme.resolve(widget.appearance);
    final strings = widget.strings ?? PlayerStrings.of(widget.locale);
    final textDirection = dirFor(widget.locale, widget.textDirection);
    final showingAd = _activeAd != null;
    final restriction = widget.restriction;
    final state = _controller.state.value;
    final showCover = !showingAd && !_coverDismissed && !state.started;

    // Everything above the video: ad UI or the skin, plus blocking overlays.
    final overlays = Stack(
      fit: StackFit.expand,
      children: [
        if (showingAd)
          AdOverlay(
            controller: _controller,
            theme: theme,
            textDirection: textDirection,
            strings: strings,
            locale: widget.locale,
            skipAfter: _activeAd!.brk.skipAfter,
            skippable: _activeAd!.brk.skippable,
            clickThrough: _activeAd!.brk.clickThrough,
            onEnd: _endAd,
          )
        else
          Positioned.fill(
            child: PlayerSkin(
              key: ValueKey('skin-$fullscreen'),
              controller: _controller,
              theme: theme,
              strings: strings,
              locale: widget.locale,
              textDirection: textDirection,
              title: _effectiveTitle,
              episodeLabel: _effectiveEpisodeLabel,
              poster: showCover ? _effectivePoster : null,
              showCover: showCover,
              onCoverPlay: () {
                setState(() => _coverDismissed = true);
                _controller.play();
              },
              thumbnails: _thumbnailTrack,
              qualityValidate: widget.qualityValidate,
              hasPrev: _hasPrev,
              hasNext: _hasNext,
              onPrev: _hasPrev
                  ? () => widget.onEpisodeChange?.call(
                      widget.episodes![_episodeIndex - 1].id,
                    )
                  : null,
              onNext: _hasNext
                  ? () => widget.onEpisodeChange?.call(_nextEpisode!.id)
                  : null,
              onBack: widget.onBack,
              episodes: widget.episodes,
              currentEpisodeId: _episode?.id,
              onSelectEpisode: widget.onEpisodeChange,
              nextEpisode: _nextEpisode,
              onLike: widget.onLike != null ? _onLike : null,
              liked: widget.liked,
              isFullscreen: _isFullscreen,
              onToggleFullscreen: _toggleFullscreen,
              fullscreenOnPlay: widget.fullscreenOnPlay,
              resume: _resumePoint,
              resumeIsAuto: widget.resumeMode == PlayerResumeMode.auto,
              onDismissResume: () => setState(() => _resumePoint = null),
              onResumeTap: _resumeFrom,
              onRestart: _restartFromStart,
              liveScrubPreview: widget.liveScrubPreview,
              persistSettings: widget.persistSettings,
              prefsStore: _prefsStore,
              notice: restriction == null ? widget.notice : null,
              badge: restriction == null ? widget.badge : null,
              extraOverlays: widget.overlayBuilder?.call(context) ?? const [],
            ),
          ),
        if (restriction != null)
          RestrictionOverlay(
            theme: theme,
            textDirection: textDirection,
            restriction: restriction,
            strings: strings,
          ),
        // Host- or provider-driven loading (resolving the source, fetching
        // ads, etc.) — above the cover/skin so it's visible before playback.
        if ((widget.loading || _vodLoading) && !showingAd)
          LoadingSpinner(theme: theme, strings: strings, scrim: true),
      ],
    );

    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The governor has no business streaming a rung this box cannot show.
        if (constraints.hasBoundedHeight) {
          _controller.maxRenderHeight = (constraints.maxHeight * dpr).round();
        }
        return ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _videoSurface,
              // Fullscreen: the video stays full-bleed but the controls avoid
              // the display cutout / notch.
              if (fullscreen)
                Positioned.fill(child: SafeArea(child: overlays))
              else
                overlays,
            ],
          ),
        );
      },
    );
  }
}

/// Fullscreen route: rebuilds the same player surface from the live state.
class _FullscreenPage extends StatelessWidget {
  const _FullscreenPage({required this.playerState});

  final PlayoraPlayerState playerState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: Listenable.merge([
          playerState._controller.state,
          playerState._revision,
        ]),
        builder: (context, _) =>
            playerState.buildSurface(context, fullscreen: true),
      ),
    );
  }
}
