import 'package:flutter/foundation.dart';

/// UI language. Drives strings + text direction.
enum PlayerLocale { fa, en }

/// Color scheme of the skin. The video itself always stays black.
enum PlayerAppearance { dark, light }

/// VOD source provider. [standard] plays the `src` URL directly; the others
/// exchange an opaque play token (passed as `src`) for the real stream URL via
/// the provider's API. Keeps pre-Logplex back-ends working.
enum VodProvider { standard, abrHamrahi, poyan }

/// A single progressive source. Pass a list as `src` to offer manual quality
/// switching for MP4s (HLS exposes its renditions automatically).
@immutable
class VideoSource {
  const VideoSource({required this.src, this.type, this.height, this.label});

  /// Media URL (MP4/HLS).
  final String src;

  /// MIME type, e.g. 'video/mp4'. Advisory metadata.
  final String? type;

  /// Vertical resolution — used as the quality label (e.g. 720 → "720p").
  final int? height;

  /// Explicit label, overrides the height-derived one.
  final String? label;

  String get qualityLabel => label ?? (height != null ? '${height}p' : src);

  @override
  bool operator ==(Object other) =>
      other is VideoSource &&
      other.src == src &&
      other.type == type &&
      other.height == height &&
      other.label == label;

  @override
  int get hashCode => Object.hash(src, type, height, label);
}

/// One playable item in a playlist (series episode, related content).
@immutable
class Episode {
  const Episode({
    required this.id,
    this.src,
    this.sources,
    this.type,
    this.title,
    this.subtitle,
    this.poster,
    this.thumbnails,
    this.duration,
    this.group,
    this.contentId,
  });

  final String id;

  /// HLS .m3u8 or a progressive MP4 URL. Leave [src] AND [sources] null for a
  /// host-resolved episode: when it's selected the player parks on a spinner
  /// and waits for the host to swap `PlayoraPlayer.src` (fetch the stream URL
  /// or token in `onEpisodeChange`, then rebuild with the new `src`).
  final String? src;

  /// MP4 renditions for a manual quality menu (alternative to [src]).
  final List<VideoSource>? sources;

  final String? type;
  final String? title;

  /// e.g. "قسمت سوم".
  final String? subtitle;
  final String? poster;

  /// WebVTT thumbnails track for scrub previews.
  final String? thumbnails;
  final Duration? duration;

  /// Optional group label (e.g. a season title like "فصل اول"). When episodes
  /// carry a `group`, the playlist panel renders them under section headers,
  /// in the order the groups first appear.
  final String? group;

  /// Analytics content id for this episode. When set, switching episodes
  /// re-keys analytics so each episode reports as its own content.
  final String? contentId;
}

/// An external subtitle/caption track (WebVTT/SRT). HLS-embedded subtitle and
/// audio tracks are picked up automatically; use this to add your own files.
@immutable
class ExternalSubtitle {
  const ExternalSubtitle({
    required this.src,
    required this.label,
    required this.language,
    this.isDefault = false,
  });

  final String src;

  /// Display label, e.g. "فارسی" / "English".
  final String label;

  /// BCP-47 language code, e.g. "fa", "en".
  final String language;

  /// Show this track by default.
  final bool isDefault;
}

/// A pre-roll ad. The host resolves the creative (e.g. from VAST) and passes
/// its media URL; the player handles playback + the ad UI + analytics.
@immutable
class AdConfig {
  const AdConfig({
    required this.src,
    this.skipAfter = const Duration(seconds: 5),
    this.skippable = true,
    this.clickThrough,
  });

  /// Ad creative source (HLS or MP4).
  final String src;

  /// Time before the skip button activates ([Duration.zero] = always skippable).
  final Duration skipAfter;

  /// When false, the skip button is hidden entirely — the ad always plays out.
  final bool skippable;

  /// Opened externally when the ad surface is tapped.
  final String? clickThrough;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is AdConfig &&
      other.src == src &&
      other.skipAfter == skipAfter &&
      other.skippable == skippable &&
      other.clickThrough == clickThrough;

  @override
  int get hashCode => Object.hash(src, skipAfter, skippable, clickThrough);
}

/// Position of an [AdBreak] in the timeline.
@immutable
class AdOffset {
  const AdOffset._(this._kind, [this.at]);

  /// Before the content starts.
  static const AdOffset pre = AdOffset._('pre');

  /// After the content ends.
  static const AdOffset post = AdOffset._('post');

  /// Mid-roll at a position into the content.
  factory AdOffset.at(Duration position) => AdOffset._('mid', position);

  final String _kind;
  final Duration? at;

  bool get isPre => _kind == 'pre';
  bool get isPost => _kind == 'post';
  bool get isMid => _kind == 'mid';

  @override
  bool operator ==(Object other) =>
      other is AdOffset && other._kind == _kind && other.at == at;

  @override
  int get hashCode => Object.hash(_kind, at);
}

/// An ad break at a position in the timeline. Use the `ads` parameter for
/// multiple breaks (pre-roll, mid-rolls, post-roll).
@immutable
class AdBreak extends AdConfig {
  const AdBreak({
    required super.src,
    super.skipAfter,
    super.skippable,
    super.clickThrough,
    this.offset = AdOffset.pre,
  });

  final AdOffset offset;

  @override
  bool operator ==(Object other) =>
      other is AdBreak &&
      other.src == src &&
      other.skipAfter == skipAfter &&
      other.skippable == skippable &&
      other.clickThrough == clickThrough &&
      other.offset == offset;

  @override
  int get hashCode =>
      Object.hash(src, skipAfter, skippable, clickThrough, offset);
}

/// A notice shown over the player — e.g. an operator/network message
/// ("playback is only free on operator X's network"). Host-controlled:
/// pass it to show, remove it (or let the user dismiss) to hide.
@immutable
class PlayerNotice {
  const PlayerNotice({
    required this.message,
    this.ctaLabel,
    this.onCta,
    this.dismissible = true,
  });

  final String message;

  /// Optional call-to-action button label.
  final String? ctaLabel;
  final VoidCallback? onCta;

  /// Whether the user can dismiss it.
  final bool dismissible;
}

/// A blocking restriction overlay — e.g. the viewer's IP/network isn't allowed.
/// Covers the whole player and pauses playback. Host-controlled: pass it to
/// block, remove it to resume.
@immutable
class PlayerRestriction {
  const PlayerRestriction({
    required this.title,
    required this.message,
    this.onRetry,
    this.onExit,
    this.retryLabel,
    this.exitLabel,
  });

  /// Heading, e.g. "شبکه نامعتبر" / "Network not allowed".
  final String title;

  /// Explanatory message.
  final String message;

  /// Retry/re-check handler. If omitted, the retry button is hidden.
  final VoidCallback? onRetry;

  /// Exit handler. If omitted, the exit button is hidden.
  final VoidCallback? onExit;

  /// Override the default retry button label.
  final String? retryLabel;

  /// Override the default exit button label.
  final String? exitLabel;
}
