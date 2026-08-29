import 'package:flutter_test/flutter_test.dart';
import 'package:playora/playora.dart';

void main() {
  group('PlayoraBufferConfig', () {
    test('the aggressive profile reads far ahead of media_kit\'s 10 s', () {
      const config = PlayoraBufferConfig.aggressive();
      final props = config.mpvProperties(diskCachePath: r'C:\tmp\playora');
      expect(int.parse(props['cache-secs']!), greaterThan(600));
      expect(props['demuxer-readahead-secs'], props['cache-secs']);
      expect(props['cache'], 'yes');
    });

    test('a writable cache directory unlocks the large byte cap', () {
      const config = PlayoraBufferConfig.aggressive();
      final onDisk = config.mpvProperties(diskCachePath: '/tmp/playora');
      final inMemory = config.mpvProperties();
      expect(int.parse(onDisk['demuxer-max-bytes']!), config.diskMaxBytes);
      expect(onDisk['cache-on-disk'], 'yes');
      expect(onDisk['cache-dir'], '/tmp/playora');
      // Without one the cache lives on the heap, so it stays RAM-safe.
      expect(int.parse(inMemory['demuxer-max-bytes']!), config.memoryMaxBytes);
      expect(inMemory['cache-on-disk'], 'no');
      expect(inMemory.containsKey('cache-dir'), isFalse);
      expect(config.memoryMaxBytes, lessThan(config.diskMaxBytes));
    });

    test('PlayerConfiguration is seeded with the RAM-safe cap', () {
      const config = PlayoraBufferConfig.aggressive();
      expect(config.initialMaxBytes, config.memoryMaxBytes);
    });

    test('back-buffer is capped independently of the read-ahead', () {
      const config = PlayoraBufferConfig.aggressive();
      final props = config.mpvProperties(diskCachePath: '/tmp/playora');
      // media_kit sets both to bufferSize; a big forward cache must not drag
      // an equally big backward one along.
      expect(int.parse(props['demuxer-max-back-bytes']!), config.backBytes);
      expect(config.backBytes, lessThan(config.diskMaxBytes));
    });

    test('reconnect options are passed to the stream layer', () {
      final props =
          const PlayoraBufferConfig.aggressive().mpvProperties();
      expect(props['stream-lavf-o'], contains('reconnect=1'));
      // Never reconnect_streamed: an HLS segment ends in EOF by design, and
      // that option answers every one of them with a backoff.
      expect(props['stream-lavf-o'], isNot(contains('reconnect_streamed')));
    });

    test('the minimal profile keeps media_kit behaviour and no disk cache',
        () {
      const config = PlayoraBufferConfig.minimal();
      final props = config.mpvProperties(diskCachePath: '/tmp/playora');
      expect(config.cacheOnDisk, isFalse);
      expect(props['cache-on-disk'], 'no');
      expect(props['cache-pause-initial'], 'no');
      expect(int.parse(props['demuxer-max-bytes']!), 32 * 1024 * 1024);
    });

    test('profiles are ordered by how far ahead they read', () {
      final minimal = PlayoraBufferConfig.of(PlayoraBufferProfile.minimal);
      final balanced = PlayoraBufferConfig.of(PlayoraBufferProfile.balanced);
      final aggressive =
          PlayoraBufferConfig.of(PlayoraBufferProfile.aggressive);
      expect(minimal.readahead, lessThan(balanced.readahead));
      expect(balanced.readahead, lessThan(aggressive.readahead));
      expect(minimal.diskMaxBytes, lessThan(balanced.diskMaxBytes));
      expect(balanced.diskMaxBytes, lessThan(aggressive.diskMaxBytes));
    });

    test('network timeout is well past media_kit\'s 5 s', () {
      final props =
          const PlayoraBufferConfig.aggressive().mpvProperties();
      final timeout = int.parse(props['network-timeout']!);
      expect(timeout, greaterThan(5));
      // A dead socket holds the picture for the whole timeout before anything
      // retries it, so it cannot be long either.
      expect(timeout, lessThanOrEqualTo(20));
    });

    test('segment connections are kept alive', () {
      const config = PlayoraBufferConfig.aggressive();
      expect(config.mpvProperties()['stream-lavf-o'],
          contains('multiple_requests=1'));
    });

    test('the stream is probed briefly, not for the ffmpeg default', () {
      final props = const PlayoraBufferConfig.aggressive().mpvProperties();
      expect(
        double.parse(props['demuxer-lavf-analyzeduration']!),
        lessThanOrEqualTo(1.0),
      );
    });

    test('the demuxer option media_kit owns is left alone', () {
      // media_kit writes the protocol whitelist into demuxer-lavf-o, and mpv
      // has no way to add one entry to a key/value list — assigning it would
      // drop the whitelist and break playback.
      final props = const PlayoraBufferConfig.aggressive().mpvProperties();
      expect(props.containsKey('demuxer-lavf-o'), isFalse);
    });
  });
}
