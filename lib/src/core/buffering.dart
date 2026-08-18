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
  /// episode. This is Playora's default.
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
        reconnect = true;

  /// A few minutes of read-ahead.
  const PlayoraBufferConfig.balanced()
      : readahead = const Duration(minutes: 5),
        memoryMaxBytes = 48 * 1024 * 1024,
        diskMaxBytes = 192 * 1024 * 1024,
        backBytes = 24 * 1024 * 1024,
        cacheOnDisk = true,
        cacheDirectory = null,
        networkTimeout = const Duration(seconds: 30),
        streamBufferBytes = 512 * 1024,
        pauseUntilInitialBuffer = true,
        initialBufferWait = const Duration(seconds: 1),
        reconnect = true;

  /// Keep downloading for as long as the byte cap allows.
  const PlayoraBufferConfig.aggressive()
      : readahead = const Duration(hours: 2),
        memoryMaxBytes = 96 * 1024 * 1024,
        diskMaxBytes = 512 * 1024 * 1024,
        backBytes = 32 * 1024 * 1024,
        cacheOnDisk = true,
        cacheDirectory = null,
        networkTimeout = const Duration(seconds: 30),
        streamBufferBytes = 1024 * 1024,
        pauseUntilInitialBuffer = true,
        initialBufferWait = const Duration(seconds: 1),
        reconnect = true;

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

  /// mpv `network-timeout`. media_kit ships 5 s, which trips on slow links.
  final Duration networkTimeout;

  /// mpv `stream-buffer-size`.
  final int streamBufferBytes;

  /// Hold playback at the start until [initialBufferWait] of media is cached,
  /// instead of starting and stalling a second later.
  final bool pauseUntilInitialBuffer;
  final Duration initialBufferWait;

  /// Ask libavformat to transparently reconnect dropped HTTP connections.
  final bool reconnect;

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
      if (reconnect)
        'stream-lavf-o': [
          'reconnect=1',
          'reconnect_streamed=1',
          'reconnect_on_network_error=1',
          'reconnect_delay_max=30',
        ].join(','),
    };
  }
}
