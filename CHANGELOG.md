# Changelog

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
