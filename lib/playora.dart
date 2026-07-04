/// Playora — a production-grade Flutter video player with a custom
/// RTL-aware gold-on-dark skin: HLS/MP4, quality/speed/subtitle/audio menus,
/// pre/mid/post-roll ads, touch gestures, playlist + up-next, optional
/// Logplex analytics + resume, VOD provider token exchange, and settings
/// persistence.
///
/// Call `MediaKit.ensureInitialized()` in `main()` (the player also does it
/// lazily on first mount), then drop a [PlayoraPlayer] into your tree.
library;

export 'src/analytics/client.dart' show LogplexAnalyticsClient;
export 'src/analytics/watch_interval.dart' show WatchIntervalReporter;
export 'src/core/controller.dart'
    show
        AudioOption,
        PlaybackValue,
        QualityOption,
        SeekEvent,
        PlayoraController,
        SubtitleOption;
export 'src/core/prefs.dart' show PlayerPrefs, PlayerPrefsStore, defaultPrefsKey;
export 'src/core/vod.dart'
    show
        ResolvedVodSource,
        VodResolutionException,
        abrHamrahiDefaultUrl,
        poyanDefaultUrl,
        resolveVodSource;
export 'src/core/vtt_thumbnails.dart' show ThumbnailCue, ThumbnailTrack;
export 'src/i18n/strings.dart' show PlayerStrings, dirFor, localeDigits;
export 'src/models/analytics_types.dart'
    show
        LogplexAnalyticsConfig,
        LogplexEventType,
        PlayerErrorInfo,
        ResumePoint,
        ResumeResolver,
        TrackFields,
        WatchIntervalHandler,
        WatchIntervalInfo;
export 'src/models/types.dart'
    show
        AdBreak,
        AdConfig,
        AdOffset,
        Episode,
        ExternalSubtitle,
        PlayerAppearance,
        PlayerLocale,
        PlayerNotice,
        PlayerRestriction,
        VideoSource,
        VodProvider;
export 'src/theme/player_theme.dart' show PlayoraTheme;
export 'src/ui/playora_player.dart' show PlayoraPlayer, PlayoraPlayerState;
