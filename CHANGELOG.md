# Changelog

## 0.2.1

- Fix: a playlist handed to the player after mount (hosts fetching episodes
  async) was treated as an episode switch — with src-less episodes the player
  paused on an infinite spinner. It is now adopted in place.
- Fix: seeks issued before the media reports a duration (e.g. tapping the
  resume banner right after open) were silently dropped by mpv and playback
  restarted at 0. They are now parked and applied once the duration is known.
- Re-selecting the episode whose media is already loaded (a host revert after
  a failed resolve) cancels the wait instead of reloading.

## 0.2.0

- `expand`: fill the parent box instead of sizing to `aspectRatio` — for
  full-height portrait player pages; control bars pin to the box edges.
- `videoFit`: control how the video scales inside the surface (default
  `BoxFit.contain`, now passed explicitly to the render layer).
- Host-resolved episodes: an `Episode` may omit `src`/`sources`; selecting it
  parks the player on a spinner until the host swaps `PlayoraPlayer.src`
  (per-episode token/URL exchange in `onEpisodeChange`).
- Resume card: the CTA button is centered.

## 0.1.1

- `orientationsAfterFullscreen`: orientations restored when leaving fullscreen
  (pass the portrait pair in a portrait-locked app). Defaults to all
  orientations, matching the previous behavior.
- `fullscreenOnPlay` now also applies when playback starts by itself —
  `autoPlay: true` or a pre-roll — not just on the cover's play tap.

## 0.1.0

Initial release — feature-parity Flutter port of logplex-player-react:

- HLS + MP4 playback on Android/iOS/desktop/web (media_kit engine; hls.js on web).
- Custom gold-on-dark skin with light mode, fa (RTL) / en locales, responsive layout.
- Quality (auto + embedded tracks + manual MP4 renditions), speed, subtitle and audio menus.
- WebVTT scrub thumbnails (individual images and `#xywh` sprite sheets).
- Touch gestures: double-tap ±10s, long-press 2×, brightness/volume swipes; desktop click/double-click/hover behavior.
- Pre/mid/post-roll ads with skip countdown, click-through and ad analytics events.
- Playlist with season groups, prev/next, auto-advance and the up-next card.
- Like button, transient info badge, operator notice banner, blocking restriction overlay.
- Route-based fullscreen with landscape + immersive mode on mobile.
- VOD provider token exchange (ABR Hamrahi, Poyan) with endpoint overrides.
- Optional Logplex analytics client (batching, retries, heartbeats, progress milestones) + "continue watching" resume, host-driven `resolveResume`, and the external `onWatchInterval` heartbeat with `W*H` quality reporting.
- Settings persistence (volume/mute/speed/brightness) via `persistSettings`.
