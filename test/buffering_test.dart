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
      expect(props['stream-lavf-o'], contains('reconnect_streamed=1'));
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
      expect(int.parse(props['network-timeout']!), greaterThanOrEqualTo(30));
    });
  });
}
