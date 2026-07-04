<div align="center">

# 🎬 Playora

**A production-grade Flutter video player with a custom RTL-aware, gold-on-dark skin.**

HLS/MP4 · quality/speed/subtitle/audio menus · pre/mid/post-roll ads · touch gestures ·
playlists & seasons · optional analytics + resume · Persian (RTL) & English out of the box

[![CI](https://github.com/Ali-Roodi/playora/actions/workflows/ci.yml/badge.svg)](https://github.com/Ali-Roodi/playora/actions/workflows/ci.yml)
[![Demo](https://img.shields.io/badge/demo-live-e8b84b)](https://ali-roodi.github.io/playora/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

**[🕹 Live demo](https://ali-roodi.github.io/playora/)** — the same example app, built for the web.

</div>

---

پلیر ویدیوی اختصاصی فلاتر با اسکین سفارشی راست‌چین: کیفیت/سرعت/زیرنویس/صدا، تبلیغات، ژست‌های لمسی، لیست پخش و فصل‌ها، «ادامه پخش» و آنالیتیکس اختیاری.

## Features

- **HLS + MP4** — adaptive HLS (auto quality from the manifest) or progressive MP4. Pass a list of MP4 renditions for a manual quality menu.
- **Custom skin** — dark, gold-accented, light mode, RTL/LTR, responsive. Layout stays physical; RTL only right-aligns text (like YouTube).
- **Quality / speed / subtitles / audio menus** — embedded HLS subtitle and multi-language audio tracks are detected automatically; add external WebVTT/SRT subtitles on top. `qualityValidate` hides unwanted renditions.
- **Scrub previews** — WebVTT thumbnail tracks (individual images or `#xywh` sprite sheets).
- **Ads** — pre-roll, mid-rolls (at content positions) and post-roll, with skip countdown and click-through. Ad playback is never counted in content analytics.
- **Playlist & seasons** — episode panel with sticky season headers (`Episode.group`), prev/next, auto-advance, and an **up-next card** near the end of an episode.
- **Gestures** — double-tap edges ±10s, long-press 2×, brightness/volume vertical swipes; desktop gets click-to-pause, double-click fullscreen and hover-reveal.
- **Fullscreen** — route-based fullscreen with automatic landscape orientation + immersive mode on mobile.
- **Overlays** — like button (controllable), transient info badge, operator notice banner, blocking IP/network restriction with retry/exit.
- **VOD providers** — `vodType` exchanges an opaque play token for the real stream URL via a provider API (ABR Hamrahi, Poyan), so existing back-ends keep working.
- **Optional analytics + resume** — canonical events to your ingest endpoint (batched, retried, heartbeats) and a "continue watching" banner. Or drive resume from your own back-end with `resolveResume`, and report a watch heartbeat to your current tracker with `onWatchInterval`.
- **Persistence** — remember volume/mute/speed/brightness across sessions (`persistSettings`).
- **fa / en built in** — Persian digits, RTL text, overridable strings.

Runs on **Android, iOS, Windows, macOS, Linux and Web** (web uses hls.js under the hood, via [media_kit](https://pub.dev/packages/media_kit)).

## Install

```yaml
# pubspec.yaml
dependencies:
  playora:
    git:
      url: https://github.com/Ali-Roodi/playora.git
```

Initialize media_kit once in `main()`:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MyApp());
}
```

## Quick start

```dart
import 'package:playora/playora.dart';

PlayoraPlayer(
  src: 'https://cdn.example.com/movie/master.m3u8',
  poster: 'https://cdn.example.com/poster.jpg',
  title: 'Sample Movie',
  locale: PlayerLocale.fa, // fa (RTL) | en (LTR)
)
```

That's it — a self-contained player with zero network calls beyond the stream itself.

## Playlist, seasons & up-next

```dart
final episodes = [
  Episode(id: 'e1', src: '.../e1.m3u8', title: 'سریال', subtitle: 'قسمت اول', group: 'فصل اول', poster: '...'),
  Episode(id: 'e2', src: '.../e2.m3u8', title: 'سریال', subtitle: 'قسمت دوم', group: 'فصل اول', poster: '...'),
];

PlayoraPlayer(
  episodes: episodes,
  currentEpisodeId: current,
  onEpisodeChange: (id) => setState(() => current = id),
)
```

`Episode.group` renders season headers in the playlist panel. Near the end of an episode
that has a next one, an **up-next card** (cover + filling progress bar) appears; ignoring it
auto-advances on end, tapping it jumps straight to the next episode.

## Ads

```dart
PlayoraPlayer(
  src: src,
  // Pre-roll shorthand:
  ad: const AdConfig(src: 'https://ads.example.com/creative.m3u8', clickThrough: 'https://sponsor.example.com'),
  // …or multiple breaks:
  ads: [
    const AdBreak(src: '...', offset: AdOffset.pre),
    AdBreak(src: '...', offset: AdOffset.at(const Duration(minutes: 10))),
    const AdBreak(src: '...', offset: AdOffset.post),
  ],
)
```

## Optional analytics + resume

```dart
PlayoraPlayer(
  src: src,
  analytics: const LogplexAnalyticsConfig(
    baseUrl: 'https://ingest.example.com',
    apiKey: '…',
    userId: 'viewer-1',
    contentId: 'movie-42',
    contentType: 'movie',
  ),
  resume: true, // continue-watching banner
)
```

Omit `analytics` entirely to run the player standalone — no requests, nothing backend-specific.

## Your own back-end (no analytics needed)

```dart
PlayoraPlayer(
  src: playToken,                             // opaque token for the provider
  vodType: VodProvider.abrHamrahi,            // standard | abrHamrahi | poyan
  vodCustomUrl: {VodProvider.abrHamrahi: 'https://api.example.com/vod/{token}'},
  qualityValidate: (height) => height > 400,  // hide tiny renditions

  // periodic "user watch" report to your current tracker
  onWatchInterval: (info) async {
    // info.quality is "W*H" (e.g. "1920*1080"), info.playDuration in seconds
    final id = await reportWatch(info);
    return id; // chained into the next call
  },

  // "continue watching" banner sourced from your back-end
  resolveResume: () async {
    final w = await getWatch(contentId);
    return w == null ? null : ResumePoint(position: Duration(seconds: w.seconds));
  },
)
```

## Theming & i18n

```dart
PlayoraPlayer(
  appearance: PlayerAppearance.dark,                 // dark | light
  theme: const PlayoraTheme(accent: Color(0xFFE8B84B)), // full token overrides
  locale: PlayerLocale.fa,                           // RTL text; layout stays physical
  strings: myCustomStrings,                          // override any label
)
```

## API overview

| Parameter | Type | Description |
| --- | --- | --- |
| `src` / `sources` | `String` / `List<VideoSource>` | HLS/MP4 URL, or MP4 renditions for a manual quality menu. For a non-standard `vodType`, an opaque play token. |
| `vodType` / `vodCustomUrl` | `VodProvider` / `Map` | Provider token exchange (ABR Hamrahi, Poyan). `{token}` is substituted. |
| `qualityValidate` | `bool Function(int height)` | Hide embedded renditions whose height fails the predicate. Auto stays. |
| `poster` / `title` / `episodeLabel` | `String` | Cover image and titles above the scrubber. |
| `thumbnails` | `String` | WebVTT thumbnails track for scrub previews. |
| `subtitles` | `List<ExternalSubtitle>` | External subtitle files (embedded tracks are auto-detected). |
| `locale` / `textDirection` | `PlayerLocale` / `TextDirection?` | UI language and direction. fa → RTL. |
| `theme` / `appearance` | `PlayoraTheme` / `PlayerAppearance` | Design token overrides and color scheme. |
| `episodes` / `currentEpisodeId` / `onEpisodeChange` | — | Controlled playlist. |
| `ad` / `ads` | `AdConfig` / `List<AdBreak>` | Pre-roll shorthand, or breaks at pre/post/`AdOffset.at(...)`. |
| `notice` / `restriction` / `badge` | — | Operator notice, blocking overlay, transient info pill. |
| `analytics` / `resume` / `resolveResume` | — | Built-in analytics, resume banner, host-driven resume. |
| `onWatchInterval` / `watchInterval` | — | External watch heartbeat + cadence (default 5s). |
| `onPlayerReady` | `ValueChanged<PlayoraController?>` | Imperative control (seek, pause, tracks, …). |
| `persistSettings` / `settingsKey` | `bool` / `String` | Remember volume/mute/speed/brightness. |
| `fullscreenOnPlay` / `onBack` / `onLike` / `liked` / `loading` | — | Behavior toggles & host hooks. |
| `overlayBuilder` | `List<Widget> Function(BuildContext)` | Extra overlays inside the player surface. |

## Development

```bash
flutter pub get
flutter analyze
flutter test
cd example && flutter run        # demo app (any platform)
flutter build web --base-href /playora/   # the GitHub Pages demo
```

## License

[MIT](./LICENSE) © Ali Roodi

Built on [media_kit](https://github.com/media-kit/media-kit). Inspired by
[logplex-player-react](https://github.com/safarishahim/logplex-player-react); the demo uses the
Sprite Fight sample assets from [Vidstack](https://vidstack.io).
