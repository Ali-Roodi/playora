import 'package:flutter/foundation.dart';

/// How far ahead of the playhead the player is allowed to pre-load.
///
/// media_kit's stock settings cap the read-ahead at ~10 s of media and 32 MB —
/// enough to stall on every dip of a weak connection. Playora raises both and
/// (when the platform allows it) backs the cache with a file on disk, so the
/// stream keeps downloading — up to the whole video — while the viewer
/// watches.
enum PlayoraBufferProfile {
  /// media_kit's stock behaviour. Lowest memory/disk footprint.
  minimal,

  /// A few minutes of read-ahead. Good default for metered connections.
  balanced,

  /// Buffer as far ahead as the byte cap allows — typically the rest of an
  /// episode. Bandwidth is spent freely here: a deep cache is what lets the
  /// adaptive governor climb early and retreat invisibly. Playora's default.
  aggressive,
}

/// Tuning for the demuxer cache, the network stack and the initial buffer.
///
/// Byte caps come in pairs: [diskMaxBytes] is used when a writable cache
/// directory is available (the cache lives in a file, so it costs storage and
/// not RAM), [memoryMaxBytes] when it isn't.
@immutable
class PlayoraBufferConfig {
  const PlayoraBufferConfig({
    required this.readahead,
    required this.memoryMaxBytes,
    required this.diskMaxBytes,
    required this.backBytes,
    this.cacheOnDisk = true,
    this.cacheDirectory,
    this.networkTimeout = const Duration(seconds: 30),
    this.streamBufferBytes = 1024 * 1024,
    this.pauseUntilInitialBuffer = true,
    this.initialBufferWait = const Duration(seconds: 1),
    this.reconnect = true,
    this.httpKeepAlive = true,
    this.probeDuration = const Duration(seconds: 1),
    this.probeBytes = 512 * 1024,
  });

  /// Stock media_kit behaviour — no extra memory or storage pressure.
  const PlayoraBufferConfig.minimal()
      : readahead = const Duration(seconds: 20),
        memoryMaxBytes = 32 * 1024 * 1024,
        diskMaxBytes = 32 * 1024 * 1024,
        backBytes = 16 * 1024 * 1024,
        cacheOnDisk = false,
        cacheDirectory = null,
        networkTimeout = const Duration(seconds: 15),
        streamBufferBytes = 256 * 1024,
        pauseUntilInitialBuffer = false,
        initialBufferWait = const Duration(seconds: 1),
        reconnect = true,
        httpKeepAlive = true,
        probeDuration = const Duration(seconds: 1),
        probeBytes = 512 * 1024;

  /// A few minutes of read-ahead.
  const PlayoraBufferConfig.balanced()
      : readahead = const Duration(minutes: 5),
        memoryMaxBytes = 48 * 1024 * 1024,
        diskMaxBytes = 192 * 1024 * 1024,
        backBytes = 24 * 1024 * 1024,
        cacheOnDisk = true,
        cacheDirectory = null,
        networkTimeout = const Duration(seconds: 15),
        streamBufferBytes = 512 * 1024,
        pauseUntilInitialBuffer = true,
        initialBufferWait = const Duration(seconds: 1),
        reconnect = true,
        httpKeepAlive = true,
        probeDuration = const Duration(seconds: 1),
        probeBytes = 512 * 1024;

  /// Keep downloading for as long as the byte cap allows.
  const PlayoraBufferConfig.aggressive()
      : readahead = const Duration(hours: 2),
        memoryMaxBytes = 96 * 1024 * 1024,
        diskMaxBytes = 1024 * 1024 * 1024,
        backBytes = 64 * 1024 * 1024,
        cacheOnDisk = true,
        cacheDirectory = null,
        networkTimeout = const Duration(seconds: 15),
        streamBufferBytes = 4 * 1024 * 1024,
        pauseUntilInitialBuffer = true,
        initialBufferWait = const Duration(seconds: 1),
        reconnect = true,
        httpKeepAlive = true,
        probeDuration = const Duration(seconds: 1),
        probeBytes = 512 * 1024;

  factory PlayoraBufferConfig.of(PlayoraBufferProfile profile) =>
      switch (profile) {
        PlayoraBufferProfile.minimal => const PlayoraBufferConfig.minimal(),
        PlayoraBufferProfile.balanced => const PlayoraBufferConfig.balanced(),
        PlayoraBufferProfile.aggressive =>
          const PlayoraBufferConfig.aggressive(),
      };

  /// Upper bound on how much media time is pre-loaded. The byte caps usually
  /// bind first; this mostly exists to keep tiny/low-bitrate streams sane.
  final Duration readahead;

  /// Cache cap when the cache has to live in RAM.
  final int memoryMaxBytes;

  /// Cache cap when the cache is backed by a file on disk.
  final int diskMaxBytes;

  /// How much already-played media is kept for instant backward seeks.
  final int backBytes;

  /// Whether to back the cache with a file (keeps a large cache off the heap).
  final bool cacheOnDisk;

  /// Where that file goes. Defaults to a `playora_cache` folder inside the
  /// app's temporary directory.
  final String? cacheDirectory;

  /// mpv `network-timeout`. media_kit ships 5 s, which trips on slow links —
  /// but a long one is its own stall: a socket that has silently died holds
  /// the picture for the whole timeout before anything retries it.
  final Duration networkTimeout;

  /// mpv `stream-buffer-size`.
  final int streamBufferBytes;

  /// Hold playback at the start until [initialBufferWait] of media is cached,
  /// instead of starting and stalling a second later.
  final bool pauseUntilInitialBuffer;
  final Duration initialBufferWait;

  /// Ask libavformat to transparently reconnect dropped HTTP connections.
  final bool reconnect;

  /// Reuse one HTTP connection across segment requests.
  ///
  /// Applied at the protocol level (`stream-lavf-o`), not through mpv's
  /// `demuxer-lavf-o`: media_kit owns that option — the protocol whitelist
  /// lives there — and mpv has no way to add to a key/value list without
  /// rewriting the whole of it, which loses the whitelist.
  ///
  /// An HLS stream is a few hundred small files. Opening a fresh TCP + TLS
  /// connection for each of them costs a round trip pair per segment, which
  /// on a high-latency mobile link is most of the wait — browsers keep the
  /// connection alive, which is much of why the web player feels quicker off
  /// the mark than the same stream in the app.
  final bool httpKeepAlive;

  /// How long libavformat may analyse the stream before playback starts.
  ///
  /// ffmpeg's default probes several seconds of media before it reports the
  /// streams, and every one of those seconds is black screen. A short probe
  /// is enough for the H.264/AAC segments an HLS ladder is made of. Null
  /// leaves the default alone.
  final Duration? probeDuration;

  /// How much of the stream libavformat may read while analysing it.
  ///
  /// ffmpeg's default is 5 MB, which on an HLS ladder is several segments —
  /// and on a phone link several seconds of black screen before the first
  /// frame. The pair of AAC and H.264 streams an HLS segment carries is
  /// identified in a fraction of that. Null leaves the default alone.
  final int? probeBytes;

  /// The cap that applies before a disk-backed cache is confirmed. Passed to
  /// `PlayerConfiguration.bufferSize`, so it must stay RAM-safe.
  int get initialMaxBytes => memoryMaxBytes;

  /// mpv properties for this config. [diskCachePath] is the verified cache
  /// directory, or null when the cache has to stay in memory.
  Map<String, String> mpvProperties({String? diskCachePath}) {
    final onDisk = cacheOnDisk && diskCachePath != null;
    final maxBytes = onDisk ? diskMaxBytes : memoryMaxBytes;
    final readaheadSecs = readahead.inSeconds.clamp(1, 24 * 3600);
    return {
      'cache': 'yes',
      'cache-secs': '$readaheadSecs',
      'demuxer-readahead-secs': '$readaheadSecs',
      'demuxer-max-bytes': '$maxBytes',
      'demuxer-max-back-bytes': '$backBytes',
      'cache-on-disk': onDisk ? 'yes' : 'no',
      if (onDisk) 'cache-dir': diskCachePath,
      'cache-pause': 'yes',
      'cache-pause-initial': pauseUntilInitialBuffer ? 'yes' : 'no',
      'cache-pause-wait': '${initialBufferWait.inMilliseconds / 1000}',
      'network-timeout': '${networkTimeout.inSeconds}',
      'stream-buffer-size': '$streamBufferBytes',
      if (probeDuration != null)
        'demuxer-lavf-analyzeduration':
            '${probeDuration!.inMilliseconds / 1000}',
      if (probeBytes != null) 'demuxer-lavf-probesize': '$probeBytes',
      if (reconnect || httpKeepAlive)
        'stream-lavf-o': [
          if (reconnect) ...[
            // Only a connection that drops *before* the end of the response.
            // 'reconnect_streamed' looks like the thorough choice and is the
            // opposite: an HLS segment is a finite file, so every single one
            // of them ends in 'End of file', which that option reads as a
            // dropped connection and answers with a 0/1/3 s backoff — seconds
            // of stall on every segment boundary, all the way through the
            // episode.
            'reconnect=1',
            // A retry that takes half a minute reads as a frozen picture.
            'reconnect_delay_max=5',
          ],
          if (httpKeepAlive) 'multiple_requests=1',
        ].join(','),
    };
  }

}
