# Changelog

## 0.7.0

Adaptive quality that actually adapts on mobile, a pause button that stays
pressed, and a video that stops when the screen locks.

### Adaptive quality

- **The ladder now comes from the HLS manifest.** mpv exposes no tracks for a
  master playlist — it opens one variant (in practice the first one listed)
  and stays there no matter how badly that goes, which is why "Auto" was the
  only entry in the quality menu and the governor had nothing to steer.
  Playora now reads the master itself, so the menu lists real rungs and the
  governor can move between them by re-opening the chosen variant playlist at
  the same position. The fetch is bounded (1.5 s): a slow manifest costs the
  ladder, never the playback.
- **A master that keeps audio in its own rendition keeps its audio.** Playing
  such a variant on its own would come up silent, so Playora writes a
  one-variant master that still carries the `EXT-X-MEDIA` renditions, with
  absolute URIs, and plays that.
- **A fresh session opens at 720p instead of the top rung.** Opening at 1080p
  means downloading its first segments before a single frame appears — the
  slow start on a phone, and on a weak link a stall followed by the downshift
  the measurement was always going to force. `startupHeightCeiling: null`
  restores the old behaviour. A remembered height from a previous session
  still wins, and mpv's own `hls-bitrate` is capped the same way for the case
  where the manifest never arrives.
- **A deep buffer earns one rung, not the top one.** A full cache stops
  growing, so the fill rate reads ~1 even on a fast link; that is room to
  probe, not evidence 1080p will hold. On a weak link the leap bought a stall,
  a downshift, and the same leap again.
- **A rung that just failed stays out of reach for a while.** A downshift caps
  the ladder at what the link demonstrably carries, and the cap lifts one rung
  per `ceilingRelaxTime` (45 s). Without it the deep cache made a loop: refill
  at the low rung, climb, fail, drop, refill.
- **A switch is no longer read as a failing link.** Re-opening a source starts
  from an empty cache with the picture held — every network signal says
  "collapse" for a few seconds. The whole down branch now sits out the settle
  window (raised to 5 s), which is what stopped a single switch from walking
  the ladder to the bottom one reload at a time. Switches are also serialised:
  a second one cannot start while the first is still opening.

- **Nothing is judged while a source is still opening.** media_kit reports
  `playing` the moment it is asked to, seconds before the first frame of an
  HLS stream on a phone. The governor read that window — empty cache, no
  throughput — as a collapsing link and "rescued" the viewer by re-opening at
  a lower rung, which started the window again: five spinners in the first
  twenty seconds on a real device. Every decision now waits for the playhead
  to actually move, with one exception: a rung that produces no playback at
  all within `openRescueTime` (12 s) steps down once.
- **The climb is one rung at a time.** The fill rate is measured against the
  rung that is playing, and a cache filling in bursts — which is what a
  segmented stream does — reads far above what the link sustains: enough to
  make 360p look like proof that 1080p will hold. With `headroom` at 1.4, a
  20 s cooldown and four good samples, a climb has to be earned.
- **A rung that keeps failing is asked about less and less.** The cap a
  downshift leaves behind now doubles its hold each time the ladder fails at
  the same place, up to five minutes, instead of paying for the same failed
  climb every 45 s.
- **The governor will not climb past what the surface can show.** 1080p into a
  640-pixel-tall box costs bandwidth, decode and a visible re-open, and shows
  the viewer nothing. `PlayoraPlayer` measures the video box and sets
  `PlayoraController.maxRenderHeight` from it; the quality menu still offers
  every rung.

### Switching without the viewer noticing

- **A quality change is prepared behind the picture.** mpv cannot change the
  rendition of a running HLS stream — a switch re-opens it, which on a phone
  measured 4.7–5.5 s of black screen, every time. Playora now opens the new
  rung on a second engine a few seconds ahead of the playhead, lets it fill
  its cache while the first one keeps playing, and hands over at the moment
  the playhead arrives. The picture changes quality; nothing stops, and the
  clock never jumps back to zero.
- **The head start scales with the buffer**, from `warmSwitchLead` (6 s) up to
  `warmSwitchMaxLead` (25 s): filling a couple of seconds of a much heavier
  rung takes a while on the link that made the rung a question in the first
  place.
- **A climb that cannot be prepared is simply not taken.** The rung that is
  playing is fine; re-opening the stream to improve on it costs the viewer
  seconds of black screen to fix nothing. A retreat still re-opens, because
  there the rung that is playing is the problem.
- **The standby engine keeps a mounted, full-size surface.** On Android
  media_kit hands mpv a surface that exists only while a video widget is
  attached, and `open()` waits for it — a standby nobody renders never loads
  anything. Both engines are laid out at full size and only the curtain
  between them moves, so the one taking over has been rendering into a
  correctly sized surface all along.
- **The video widget is keyed to its engine.** media_kit's `Video` takes its
  controller once; without a new key the picture stays on the engine that just
  stepped back — which is stopped, which is black until something else forces
  a rebuild.
- **Back to Auto picks up immediately.** Handing quality back to the governor
  keeps what it has measured about the link (the stream never stopped), so it
  acts in seconds instead of looking inert for the best part of a minute.
  `PlayoraController.currentVariantIndex` also lets the quality menu mark the
  rung that is playing.

### Weak devices

- **Sustained dropped frames now cost a rung.** A phone that cannot decode
  1080p in real time drops frames while the buffer stays full and every
  network-side signal reads healthy, so the governor happily held the rung the
  viewer was watching as a slideshow. Playora samples mpv's decoder and output
  drop counters and steps down one rung when they exceed
  `decoderDropTolerance` (4 frames/s) for two samples running.
- **`videoConfiguration`** is exposed on `PlayoraPlayer`, so an Android player
  aimed at low-end hardware can hand mpv the decoder's own surface
  (`vo: 'mediacodec_embed'`, `hwdec: 'mediacodec'`) and skip a full-frame GPU
  copy per frame.

### Playback control

- **Pause stays paused.** media_kit's `playOrPause` sends mpv a blind
  `cycle pause`, so once its own flag and mpv's had drifted apart the pause
  button played and the play button paused. Playora now tracks what the viewer
  asked for and plays or pauses explicitly, and reconciles mpv whenever it
  reports playing — or the playhead simply moves — while the intent is paused.
- **The video stops when the screen locks.** `PlayoraPlayer` pauses on
  `hidden`/`paused`/`detached` and never resumes by itself: coming back to
  find the episode ran on without its viewer is worse than one tap. Turn it
  off with `pauseOnBackground: false`.

### Startup and network

- **Segment boundaries are no longer treated as dropped connections.** Playora
  asked libavformat for `reconnect_streamed=1`, which sounds like the thorough
  choice and is the opposite: every HLS segment is a finite file, so every one
  of them ends in `End of file`, and that option answered each with a 0/1/3 s
  reconnect backoff. Measured on a phone against a real ladder, dropping it
  took the first frame from 16.2 s to 4.4 s and removed the stall at every
  segment boundary. What is left is `reconnect=1` — a connection that drops
  *before* the end of a response — with a 5 s cap on the retry delay.
- **A shorter probe before the first frame.** ffmpeg analysed several seconds
  and up to 5 MB of media before reporting the streams, and on a phone link
  that is seconds of black screen. `demuxer-lavf-analyzeduration` is now 1 s
  and `demuxer-lavf-probesize` 512 KB.
- **Connections are reused between segment requests** (`multiple_requests=1`).
- **`network-timeout` is 15 s, not 30.** A socket that has silently died holds
  the picture for the whole timeout before anything retries it.
- **mpv's own log is forwarded** to `debugPrint` when `debugLogging` is on,
  together with how long the manifest, the `open()` and the first frame took.
  That is how the reconnect storm above was found.

## 0.6.0

Quality switching you don't notice, and a much faster climb to the top rung.

### Adaptive quality

- **The governor now moves to the right rung in one switch instead of
  climbing a staircase.** Up- and down-shifts both resolve an absolute target
  from the measured fill rate, so 360p → 1080p is a single switch rather than
  four, and a collapsed link drops straight to what it can carry rather than
  losing a rung at a time. Every switch costs the viewer a beat of
  re-buffering, so the cheapest switch is the one that isn't needed.
- **A switch no longer shows the buffering spinner.** Re-buffering is what a
  switch *is*; painting the full-screen spinner over it read as the stream
  dropping out. `PlaybackValue.switchingQuality` marks the window and the skin
  holds the last frame through it, with a timeout so a genuine stall still
  surfaces.
- **A stall inside `switchSettleTime` (3 s) of a switch is read as the new
  rung filling its cache, not as the link failing.** Without this the switch
  looked like trouble and the governor chased its own tail downwards.
- **The stall that opens a source no longer costs a rung.** mpv holds the
  picture until `cache-pause-initial` is satisfied, on an empty cache with no
  throughput history — indistinguishable from a failing link, and the governor
  duly dropped a rung or two before the first frame had settled. The new
  `startupGrace` (5 s, measured from playback actually running) turns the down
  branch off until the stream has had a chance to open.
- A viewer-driven quality pick hides its re-buffer the same way a
  governor-driven one does.
- **Defaults are retuned for quality first**, on the assumption that bandwidth
  is cheaper than a viewer watching 360p:
  - `startupHeightCeiling` now defaults to null — sessions open at the top
    rung and walk down only if the link can't hold it (was: capped at 720p).
  - `upshiftBufferAhead` 30 s → 12 s, `upshiftCooldown` 20 s → 5 s,
    `probeInterval` 2 s → 1 s, `headroom` 1.3 → 1.15. The climb starts sooner
    and reacts twice as fast.
  - New `runwayBufferAhead` (60 s): past a minute of banked media an
    over-optimistic jump costs nothing — there is a full minute to retreat
    through before the viewer could see a stall — so the governor takes the
    top rung outright instead of asking the fill rate for permission.
  - `minBufferAhead` 8 s → 6 s and `downshiftCooldown` 8 s → 4 s: act before
    mpv's `cache-pause` freezes the picture, not after.
  - New `upshiftGoodTicks` (2) replaces the hard-coded 3.

### Buffering

- `PlayoraBufferConfig.aggressive()` spends more freely: the disk-backed cache
  cap goes 512 MB → 1 GB, the back-buffer 32 MB → 64 MB (instant backward
  seeks), and `stream-buffer-size` 1 MB → 4 MB. The RAM cap is unchanged — a
  deep cache is what lets the governor climb early and retreat invisibly.


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
