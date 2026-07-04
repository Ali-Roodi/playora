import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/prefs.dart';
import '../core/vtt_thumbnails.dart';
import '../i18n/strings.dart';
import '../models/analytics_types.dart';
import '../models/types.dart';
import '../theme/player_theme.dart';
import 'gesture_layer.dart';
import 'overlays/next_up_card.dart';
import 'overlays/overlays.dart';
import 'overlays/playlist_panel.dart';
import 'widgets/control_button.dart';
import 'widgets/player_modal.dart';
import 'widgets/time_slider.dart';

const Duration _idleHide = Duration(seconds: 8);
const List<double> _speeds = [0.5, 0.75, 1, 1.25, 1.5, 2];

/// The custom skin: cover, gesture surface, top/bottom control bars, quality/
/// speed/captions/audio modals, playlist panel, resume card, next-up card and
/// the lock mode. Layout is physical LTR (like the web player); RTL locales
/// only right-align text.
class PlayerSkin extends StatefulWidget {
  const PlayerSkin({
    super.key,
    required this.controller,
    required this.theme,
    required this.strings,
    required this.locale,
    required this.textDirection,
    this.title,
    this.episodeLabel,
    this.poster,
    this.showCover = false,
    this.onCoverPlay,
    this.thumbnails,
    this.qualityValidate,
    this.hasPrev = false,
    this.hasNext = false,
    this.onPrev,
    this.onNext,
    this.onBack,
    this.episodes,
    this.currentEpisodeId,
    this.onSelectEpisode,
    this.nextEpisode,
    this.onLike,
    this.liked,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    this.fullscreenOnPlay = false,
    this.resume,
    this.onDismissResume,
    this.persistSettings = false,
    this.prefsStore,
    this.notice,
    this.badge,
    this.extraOverlays = const [],
  });

  final PlayoraController controller;
  final PlayoraTheme theme;
  final PlayerStrings strings;
  final PlayerLocale locale;
  final TextDirection textDirection;
  final String? title;
  final String? episodeLabel;
  final String? poster;

  /// Show the pre-play cover (poster + play button). Owned by the
  /// orchestrator so it survives fullscreen transitions and episode switches.
  final bool showCover;

  /// Tapping the cover's play button.
  final VoidCallback? onCoverPlay;
  final ThumbnailTrack? thumbnails;

  /// Hide embedded (HLS) qualities whose height fails this predicate.
  final bool Function(int height)? qualityValidate;
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final List<Episode>? episodes;
  final String? currentEpisodeId;
  final ValueChanged<String>? onSelectEpisode;

  /// The next episode, for the end-of-episode "up next" card.
  final Episode? nextEpisode;
  final ValueChanged<bool>? onLike;

  /// Controlled like state (the button reflects it when provided).
  final bool? liked;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  /// Enter fullscreen when playback starts from the cover.
  final bool fullscreenOnPlay;
  final ResumePoint? resume;
  final VoidCallback? onDismissResume;
  final bool persistSettings;
  final PlayerPrefsStore? prefsStore;

  /// Shown only after playback starts (not over the cover).
  final PlayerNotice? notice;
  final String? badge;

  /// Extra overlays rendered inside the player surface.
  final List<Widget> extraOverlays;

  @override
  State<PlayerSkin> createState() => _PlayerSkinState();
}

class _PlayerSkinState extends State<PlayerSkin> {
  bool _locked = false;
  bool _active = true;
  bool _internalLiked = false;
  bool _playlistOpen = false;
  bool _settingsOpen = false;
  bool _speedOpen = false;
  bool _captionsOpen = false;
  bool _audioOpen = false;
  String? _doneBadge;
  Timer? _idleTimer;
  Timer? _resumeTimer;

  PlayoraController get controller => widget.controller;
  PlayoraTheme get theme => widget.theme;
  PlayerStrings get strings => widget.strings;

  bool get _likeControlled => widget.liked != null;
  bool get _liked => _likeControlled ? widget.liked! : _internalLiked;
  bool get _anyPanelOpen =>
      _playlistOpen || _settingsOpen || _speedOpen || _captionsOpen || _audioOpen;
  bool get _hasPlaylist => (widget.episodes?.length ?? 0) > 1;

  @override
  void initState() {
    super.initState();
    controller.state.addListener(_onPlaybackState);
    _armIdle();
    _armResumeAutoDismiss();
  }

  @override
  void didUpdateWidget(PlayerSkin old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.state.removeListener(_onPlaybackState);
      controller.state.addListener(_onPlaybackState);
    }
    if (old.resume != widget.resume) _armResumeAutoDismiss();
  }

  @override
  void dispose() {
    controller.state.removeListener(_onPlaybackState);
    _idleTimer?.cancel();
    _resumeTimer?.cancel();
    super.dispose();
  }

  void _onPlaybackState() {
    // Keep controls pinned while paused; re-arm the countdown when playing.
    if (mounted) setState(_armIdle);
  }

  /// Reveal controls and re-arm the idle timer.
  void _ping() {
    if (!_active) setState(() => _active = true);
    _armIdle();
  }

  void _armIdle() {
    _idleTimer?.cancel();
    final paused = !controller.state.value.playing;
    if (!_active || paused || _anyPanelOpen) return;
    _idleTimer = Timer(_idleHide, () {
      if (mounted && !_anyPanelOpen && controller.state.value.playing) {
        setState(() => _active = false);
      }
    });
  }

  /// Auto-dismiss the resume card if no choice is made (keep playing from
  /// the start).
  void _armResumeAutoDismiss() {
    _resumeTimer?.cancel();
    if (widget.resume == null) return;
    _resumeTimer = Timer(const Duration(seconds: 30), () {
      widget.onDismissResume?.call();
    });
  }

  void _toggleControls() {
    setState(() => _active = !_active);
    _armIdle();
  }

  void _toggleLike() {
    final next = !_liked;
    if (!_likeControlled) setState(() => _internalLiked = next);
    widget.onLike?.call(next);
  }

  void _openPanel(void Function() open) {
    setState(open);
    _armIdle();
  }

  @override
  Widget build(BuildContext context) {
    // The skin is always physically LTR; RTL only affects text runs.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ValueListenableBuilder<PlaybackValue>(
        valueListenable: controller.state,
        builder: (context, state, _) => _buildLayers(context, state),
      ),
    );
  }

  Widget _buildLayers(BuildContext context, PlaybackValue state) {
    // Locked: a single unlock button; controls hidden.
    if (_locked) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
            ),
          ),
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: _pillButton(
                icon: Icons.lock,
                onTap: () => setState(() => _locked = false),
              ),
            ),
          ),
          ...widget.extraOverlays,
        ],
      );
    }

    // Cover (pre-play): poster + a single play button. Tapping play starts
    // playback (and optionally fullscreen). The cover is dismissed on tap
    // rather than waiting for playback, so it can't get stuck on a stall.
    if (widget.showCover) {
      return Stack(
        children: [
          CoverOverlay(
            theme: theme,
            strings: strings,
            poster: widget.poster,
            onPlay: () {
              widget.onCoverPlay?.call();
              if (widget.fullscreenOnPlay && !widget.isFullscreen) {
                widget.onToggleFullscreen?.call();
              }
            },
          ),
          ...widget.extraOverlays,
        ],
      );
    }

    final visible =
        !state.playing || _active || !state.canPlay || _anyPanelOpen;
    final isMuted = state.muted || state.volume == 0;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureLayer(
            controller: controller,
            theme: theme,
            strings: strings,
            onTapToggle: _toggleControls,
            onActivity: _ping,
            onToggleFullscreen: widget.onToggleFullscreen,
            persist: widget.persistSettings,
            prefsStore: widget.prefsStore,
          ),
        ),

        // Subtitle cues — lifted above the bar when controls show.
        _captions(visible),

        // Buffering — outside the fading controls so it always shows.
        if (state.buffering || !state.canPlay)
          Positioned.fill(
            child: LoadingSpinner(theme: theme, strings: strings),
          ),

        // Persistent mute badge while controls are hidden.
        if (!visible && isMuted) MuteBadge(theme: theme),

        // Operator notice + transient badge — after playback starts. The
        // badge shows once (not again on every rebuild).
        if (widget.notice != null)
          NoticeBanner(
            theme: theme,
            textDirection: widget.textDirection,
            notice: widget.notice!,
            strings: strings,
          ),
        if (widget.badge != null && _doneBadge != widget.badge)
          BadgeOverlay(
            key: ValueKey(widget.badge),
            theme: theme,
            textDirection: widget.textDirection,
            text: widget.badge!,
            onDone: () => setState(() => _doneBadge = widget.badge),
          ),

        // Fading controls layer.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !visible,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: visible ? 1 : 0,
              child: _controls(state, isMuted),
            ),
          ),
        ),

        // Up-next card — outside the fading controls so it stays put near
        // the end. Keyed by episode so its dismissed state resets.
        if (widget.nextEpisode != null)
          NextUpCard(
            key: ValueKey('nextup-${widget.currentEpisodeId}'),
            theme: theme,
            textDirection: widget.textDirection,
            strings: strings,
            episode: widget.nextEpisode!,
            position: controller.position,
            duration: controller.duration,
            started: state.started,
            onNext: widget.onNext,
            bottomInset: visible ? 96 : 0,
          ),

        if (_playlistOpen && widget.episodes != null)
          PlaylistPanel(
            theme: theme,
            textDirection: widget.textDirection,
            strings: strings,
            locale: widget.locale,
            episodes: widget.episodes!,
            currentId: widget.currentEpisodeId,
            onSelect: (id) => widget.onSelectEpisode?.call(id),
            onClose: () => _openPanel(() => _playlistOpen = false),
          ),

        ...widget.extraOverlays,

        if (_settingsOpen) _qualityModal(state),
        if (_speedOpen) _speedModal(state),
        if (_captionsOpen) _captionsModal(state),
        if (_audioOpen) _audioModal(state),
      ],
    );
  }

  Widget _pillButton({
    required IconData icon,
    String? label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: theme.panel,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: label != null ? 16 : 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: theme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: theme.text, size: 18),
              if (label != null) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  textDirection: widget.textDirection,
                  style: TextStyle(color: theme.text, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _captions(bool controlsVisible) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: controller.subtitleCues,
      builder: (context, cues, _) {
        if (cues.isEmpty) return const SizedBox.shrink();
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          left: 16,
          right: 16,
          bottom: controlsVisible ? 108 : 24,
          child: IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final cue in cues)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      cue,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _controls(PlaybackValue state, bool isMuted) {
    final audioOptions = controller.audioOptions;
    final subtitleOptions = controller.subtitleOptions;
    final subtitlesOn = controller.subtitlesOn;

    // The gradient scrim must not absorb taps: empty areas fall through to
    // the GestureLayer beneath, so tapping the video again re-hides the
    // controls. Buttons/sliders still hit-test normally.
    return MouseRegion(
      hitTestBehavior: HitTestBehavior.translucent,
      onHover: (_) => _ping(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x99000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0xCC000000),
                  ],
                  stops: [0, 0.25, 0.6, 1],
                ),
              ),
            ),
          ),
          Column(
            children: [
              _topBar(state, audioOptions, subtitleOptions, subtitlesOn),
              const Spacer(),
              if (widget.resume != null) _resumeCard(),
              _bottomBar(state, isMuted),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topBar(
    PlaybackValue state,
    List<AudioOption> audioOptions,
    List<SubtitleOption> subtitleOptions,
    bool subtitlesOn,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Row(
        children: [
          if (widget.onBack != null)
            ControlButton(
              theme: theme,
              tooltip: strings.back,
              icon: Icons.arrow_back,
              onPressed: widget.onBack,
            ),
          const Spacer(),
          if (audioOptions.isNotEmpty)
            ControlButton(
              theme: theme,
              tooltip: strings.audioTrack,
              icon: Icons.translate,
              onPressed: () => _openPanel(() => _audioOpen = true),
            ),
          if (subtitleOptions.isNotEmpty)
            ControlButton(
              theme: theme,
              tooltip: strings.captions,
              icon: subtitlesOn
                  ? Icons.closed_caption
                  : Icons.closed_caption_off_outlined,
              active: subtitlesOn,
              onPressed: () => _openPanel(() => _captionsOpen = true),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: LabelButton(
              theme: theme,
              label: controller.qualityLabel,
              tooltip: strings.quality,
              onPressed: () => _openPanel(() => _settingsOpen = true),
            ),
          ),
          if (widget.onLike != null)
            ControlButton(
              theme: theme,
              tooltip: 'like',
              onPressed: _toggleLike,
              child: AnimatedScale(
                scale: _liked ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: Icon(
                  _liked ? Icons.favorite : Icons.favorite_border,
                  color: _liked ? theme.accent : theme.text,
                  size: 22,
                ),
              ),
            ),
          if (_hasPlaylist)
            ControlButton(
              theme: theme,
              tooltip: strings.playlist,
              icon: Icons.playlist_play,
              onPressed: () =>
                  _openPanel(() => _playlistOpen = !_playlistOpen),
            ),
        ],
      ),
    );
  }

  Widget _resumeCard() {
    final resume = widget.resume!;
    final minute = resume.position.inMinutes;
    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: theme.panel,
          borderRadius: BorderRadius.circular(theme.radius),
          border: Border.all(color: theme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: widget.textDirection == TextDirection.rtl
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Row(
              textDirection: widget.textDirection,
              children: [
                Expanded(
                  child: Text(
                    strings.resumeTitle,
                    textDirection: widget.textDirection,
                    style: TextStyle(
                      color: theme.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: strings.dismiss,
                  onPressed: widget.onDismissResume,
                  icon: Icon(Icons.close, color: theme.textMuted, size: 18),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
            Text(
              strings.resumeMessage,
              textDirection: widget.textDirection,
              style: TextStyle(color: theme.textMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () {
                controller.seek(resume.position);
                controller.play();
                widget.onDismissResume?.call();
              },
              style: FilledButton.styleFrom(
                backgroundColor: theme.accent,
                foregroundColor: theme.accentContrast,
              ),
              child: Text(
                '${strings.resumeCta} ${localeDigits(widget.locale, minute)}',
                textDirection: widget.textDirection,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(PlaybackValue state, bool isMuted) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Above the scrubber: time (left) + title/episode (right).
          Row(
            children: [
              AnimatedBuilder(
                animation: Listenable.merge(
                    [controller.position, controller.duration]),
                builder: (context, _) => Text(
                  '${formatDuration(controller.position.value)} / '
                  '${formatDuration(controller.duration.value)}',
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 12.5,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 4),
                    ],
                  ),
                ),
              ),
              if (widget.title != null || widget.episodeLabel != null)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (widget.title != null)
                          Text(
                            widget.title!,
                            textDirection: widget.textDirection,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              shadows: const [
                                Shadow(color: Colors.black54, blurRadius: 4),
                              ],
                            ),
                          ),
                        if (widget.episodeLabel != null)
                          Text(
                            widget.episodeLabel!,
                            textDirection: widget.textDirection,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.textMuted,
                              fontSize: 11.5,
                              shadows: const [
                                Shadow(color: Colors.black54, blurRadius: 4),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          PlayerTimeSlider(
            theme: theme,
            position: controller.position,
            duration: controller.duration,
            buffer: controller.buffer,
            onSeek: controller.seek,
            thumbnails: widget.thumbnails,
            onInteraction: _ping,
          ),
          LayoutBuilder(builder: (context, constraints) {
            // Narrow (portrait) widths: shed the least essential transport
            // buttons instead of overflowing — prev/next stay reachable from
            // the playlist panel, ±10s via double-tap gestures.
            final w = constraints.maxWidth;
            final showPrevNext = _hasPlaylist && w >= 480;
            final showSeekButtons = w >= 380;
            return Row(
              children: [
                // Left: lock + speed.
                ControlButton(
                  theme: theme,
                  tooltip: strings.lock,
                  icon: Icons.lock_outline,
                  onPressed: () => setState(() {
                    _locked = true;
                    _active = false;
                  }),
                ),
                LabelButton(
                  theme: theme,
                  label:
                      '${state.rate == state.rate.roundToDouble() ? state.rate.toInt() : state.rate}X',
                  tooltip: strings.speed,
                  onPressed: () => _openPanel(() => _speedOpen = true),
                ),
                const Spacer(),
                // Center transport.
                if (showPrevNext)
                  ControlButton(
                    theme: theme,
                    tooltip: strings.prevEpisode,
                    icon: Icons.skip_previous,
                    onPressed: widget.hasPrev ? widget.onPrev : null,
                  ),
                if (showSeekButtons)
                  ControlButton(
                    theme: theme,
                    tooltip: strings.rewind10,
                    icon: Icons.replay_10,
                    onPressed: () =>
                        controller.seekBy(const Duration(seconds: -10)),
                  ),
                ControlButton(
                  theme: theme,
                  tooltip: state.playing ? strings.pause : strings.play,
                  icon: state.playing ? Icons.pause : Icons.play_arrow,
                  size: 56,
                  iconSize: 38,
                  onPressed: controller.togglePlay,
                ),
                if (showSeekButtons)
                  ControlButton(
                    theme: theme,
                    tooltip: strings.forward10,
                    icon: Icons.forward_10,
                    onPressed: () =>
                        controller.seekBy(const Duration(seconds: 10)),
                  ),
                if (showPrevNext)
                  ControlButton(
                    theme: theme,
                    tooltip: strings.nextEpisode,
                    icon: Icons.skip_next,
                    onPressed: widget.hasNext ? widget.onNext : null,
                  ),
                const Spacer(),
                // Right: fullscreen + volume.
                ControlButton(
                  theme: theme,
                  tooltip: widget.isFullscreen
                      ? strings.fullscreenExit
                      : strings.fullscreenEnter,
                  icon: widget.isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  onPressed: widget.onToggleFullscreen,
                ),
                _VolumeControl(
                  theme: theme,
                  strings: strings,
                  isMuted: isMuted,
                  volume: state.volume,
                  onToggleMute: controller.toggleMute,
                  onVolume: controller.setVolume,
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ modals

  Widget _qualityModal(PlaybackValue state) {
    final options = controller.qualityOptions(validate: widget.qualityValidate);
    final isAuto = controller.isAutoQuality;
    final current = state.selected.video;
    return PlayerModal(
      theme: theme,
      textDirection: widget.textDirection,
      icon: Icons.tune,
      title: strings.qualityTitle,
      dismissLabel: strings.dismiss,
      onClose: () => _openPanel(() => _settingsOpen = false),
      options: [
        for (final option in options)
          RadioOptionData(
            label: option.isAuto
                ? '${strings.qualityAuto} (AUTO)'
                : option.label,
            // While on Auto, show the resolution currently playing.
            hint: option.isAuto && isAuto && state.height != null
                ? '${state.height}p'
                : null,
            selected: option.isAuto
                ? isAuto
                : option.renditionIndex != null
                    ? option.renditionIndex == state.renditionIndex
                    : option.hlsLevelIndex != null
                        ? !isAuto &&
                            option.hlsLevelIndex == controller.activeHlsLevel
                        : !isAuto && option.track?.id == current.id,
            onSelect: () {
              controller.selectQuality(option);
              _openPanel(() => _settingsOpen = false);
            },
          ),
      ],
    );
  }

  Widget _speedModal(PlaybackValue state) {
    return PlayerModal(
      theme: theme,
      textDirection: widget.textDirection,
      icon: Icons.speed,
      title: strings.speed,
      dismissLabel: strings.dismiss,
      onClose: () => _openPanel(() => _speedOpen = false),
      options: [
        for (final speed in _speeds)
          RadioOptionData(
            label: speed == 1
                ? '${strings.speedNormal} (1×)'
                : '${speed == speed.roundToDouble() ? speed.toInt() : speed}×',
            selected: state.rate == speed,
            onSelect: () {
              controller.setRate(speed);
              _openPanel(() => _speedOpen = false);
            },
          ),
      ],
    );
  }

  Widget _captionsModal(PlaybackValue state) {
    final options = controller.subtitleOptions;
    final activeId = controller.activeSubtitleId;
    return PlayerModal(
      theme: theme,
      textDirection: widget.textDirection,
      icon: Icons.subtitles_outlined,
      title: strings.captionsTitle,
      dismissLabel: strings.dismiss,
      onClose: () => _openPanel(() => _captionsOpen = false),
      options: [
        RadioOptionData(
          label: strings.off,
          selected: activeId == null,
          onSelect: () {
            controller.disableSubtitles();
            _openPanel(() => _captionsOpen = false);
          },
        ),
        for (final option in options)
          RadioOptionData(
            label: option.label,
            selected: option.id == activeId,
            onSelect: () {
              controller.selectSubtitle(option);
              _openPanel(() => _captionsOpen = false);
            },
          ),
      ],
    );
  }

  Widget _audioModal(PlaybackValue state) {
    final options = controller.audioOptions;
    final current = state.selected.audio;
    return PlayerModal(
      theme: theme,
      textDirection: widget.textDirection,
      icon: Icons.translate,
      title: strings.audioTitle,
      dismissLabel: strings.dismiss,
      onClose: () => _openPanel(() => _audioOpen = false),
      options: [
        for (final option in options)
          RadioOptionData(
            label: option.label,
            selected: option.track.id == current.id ||
                (current.id == 'auto' && option.track.isDefault == true),
            onSelect: () {
              controller.selectAudio(option);
              _openPanel(() => _audioOpen = false);
            },
          ),
      ],
    );
  }
}

/// Mute button + hover-expanding horizontal volume bar (desktop). Mobile
/// uses the swipe gesture instead.
class _VolumeControl extends StatefulWidget {
  const _VolumeControl({
    required this.theme,
    required this.strings,
    required this.isMuted,
    required this.volume,
    required this.onToggleMute,
    required this.onVolume,
  });

  final PlayoraTheme theme;
  final PlayerStrings strings;
  final bool isMuted;
  final double volume;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolume;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ControlButton(
            theme: theme,
            tooltip: widget.isMuted ? widget.strings.unmute : widget.strings.mute,
            icon: widget.isMuted ? Icons.volume_off : Icons.volume_up,
            onPressed: widget.onToggleMute,
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: _hovered ? 72 : 0,
            height: 28,
            child: _hovered
                ? GestureDetector(
                    onTapDown: (d) => _set(d.localPosition.dx),
                    onHorizontalDragUpdate: (d) => _set(d.localPosition.dx),
                    child: CustomPaint(
                      size: const Size(72, 28),
                      painter: _VolumePainter(
                        theme: theme,
                        value: widget.isMuted ? 0 : widget.volume,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  void _set(double dx) => widget.onVolume((dx / 72).clamp(0.0, 1.0));
}

class _VolumePainter extends CustomPainter {
  _VolumePainter({required this.theme, required this.value});

  final PlayoraTheme theme;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const h = 4.0;
    RRect r(double to) => RRect.fromRectAndRadius(
          Rect.fromLTRB(0, cy - h / 2, to, cy + h / 2),
          const Radius.circular(2),
        );
    canvas.drawRRect(
        r(size.width), Paint()..color = theme.text.withValues(alpha: 0.25));
    canvas.drawRRect(r(size.width * value), Paint()..color = theme.accent);
    canvas.drawCircle(
        Offset(size.width * value, cy), 6, Paint()..color = theme.accent);
  }

  @override
  bool shouldRepaint(_VolumePainter old) =>
      old.value != value || old.theme != theme;
}
