# Changelog

## 0.5.0

Playback on weak connections, and the "continue watching" position.

### Buffering

- The demuxer cache is now sized by Playora instead of media_kit's stock
  10 s / 32 MB. `PlayoraBufferConfig.aggressive()` (the new default) reads
  ahead for as long as the byte cap allows — typically the rest of the
  episode — so a dip in the connection no longer stalls playback.
- When a writable temp directory is available the cache is backed by a file
  on disk, which is what lets the cap be large; writability is verified up
  front, because mpv silently keeps the whole cache in RAM when `cache-dir`
  is not writable. Without one, the cap falls back to a RAM-safe value.
- `network-timeout` goes from 5 s to 30 s and libavformat is asked to
  transparently reconnect dropped HTTP connections — a brief loss of signal
  resumes instead of erroring.
- Playback holds at the start until a second of media is cached
  (`cache-pause-initial`) instead of starting and stalling immediately.
- Pick a different trade-off with `PlayoraPlayer.buffering`:
  `PlayoraBufferConfig.balanced()` or `.minimal()` (the old behaviour).
- The buffering spinner shows the refill percentage.

### Adaptive quality

- **"Auto" now actually adapts on the native backends.** mpv has no ABR of
  its own — for an HLS master playlist it pins the highest variant
  (`--hls-bitrate=max`) and buffers forever on a slow link. A new governor
  measures how many seconds of media arrive per second of wall clock and
  steps the quality down when the buffer drains or playback stalls, and back
  up once the connection has proven headroom. Tune (or disable) it with
  `PlayoraPlayer.abr`.
- A fresh session opens at 720p or below and ramps up, so playback starts
  fast; with `persistSettings: true` the height the governor settled on is
  remembered for the next session.
- Manual MP4 rendition lists get an "Auto" entry too, opt in with
  `PlayoraAbrConfig(allowRenditionSwitching: true)` — off by default because
  swapping files reloads the media.

### Continue watching

- New `resumeMode: PlayerResumeMode.auto` opens the media *at* the saved
  position instead of starting at zero and waiting for a banner tap. In
  `prompt` mode (still the default) an ignored banner lets the watch
  heartbeat overwrite the stored position with the new near-zero one — which
  is why a half-watched title could come back playing from the start.
  In auto mode the card becomes a "start over" offer.
- The resume CTA shows `m:ss` rather than a bare minute count (a resume at
  45 s used to read "from minute 0").
- `PlayoraController.adPlaying` tells a host whether the playhead currently
  belongs to an ad break. Reporting a watch position without checking it
  stores the ad's playhead as the content one, and the title then resumes a
  few seconds in.
- `PlayoraPlayer.debugLogging` prints `[playora]` diagnostics for the resume,
  load and adaptive-quality paths.

### Performance

- mpv reports the playhead once per frame; those updates are now coalesced to
  ~5/s, so the scrubber and clock no longer rebuild 25–60 times a second.
- The video surface widget is cached and wrapped in a `RepaintBoundary`, and
  the control layer has one of its own — the scrubber's repaint no longer
  reaches the video texture, and state changes no longer re-create the
  texture widget.

## 0.4.1

- Fullscreen controls (skin, ad UI, overlays) now sit inside a SafeArea so
  they clear display cutouts / punch-hole cameras in landscape; the video
  itself stays full-bleed.

## 0.4.0

- `AdConfig.skippable: false` hides the skip button entirely (previously the
  only way to make an ad unskippable was an absurd `skipAfter`, which showed
  a huge countdown).
- Ad types (`AdConfig`, `AdBreak`, `AdOffset`) now have value equality, and a
  *changed* ad list resets the played state — hosts can refetch the schedule
  per episode. If the new schedule has a pre-roll and the content is still
  near the start, it plays.
- Per-episode resume: switching episodes re-runs `resolveResume`, so each
  episode gets its own continue-watching offer. A pre-roll no longer
  suppresses the resume banner (it simply appears after the ad).
- Fullscreen always shows a top-left back button that exits fullscreen.

## 0.3.0

- Live scrub preview: without a WebVTT thumbnail track, dragging the scrubber
  now pauses and seeks (throttled, keyframe-fast) so the video surface itself
  previews the target frame — playback resumes on release. Opt out with
  `liveScrubPreview: false`. With a thumbnail track the sprite bubble is used
  as before.

## 0.2.2

- Fix: the fullscreen route now re-renders when host props change (liked,
  title, notice, …) — previously only the player's own state updates reached
  it, so e.g. a controlled like button never visually toggled in fullscreen.
- Fix: the resume banner restarts the source at the saved position (mpv
  `start:`) when playback hasn't begun yet — early seeks are silently dropped
  by mpv on some platforms, which restarted playback at 0:00. Once playback
  has started it seeks as before.

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
