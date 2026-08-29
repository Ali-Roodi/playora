import 'package:flutter_test/flutter_test.dart';
import 'package:playora/playora.dart';

const _master = '''
#EXTM3U
#EXT-X-VERSION:4
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="فارسی",DEFAULT=YES,URI="audio/fa.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=8000000,AVERAGE-BANDWIDTH=6000000,RESOLUTION=1920x1080,CODECS="avc1.4d4028,mp4a.40.2"
1080p/stream.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360
360p/stream.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=854x480
https://cdn.example.com/other/480p/stream.m3u8
''';

void main() {
  group('parseHlsMaster', () {
    test('reads the ladder and sorts it by what it costs', () {
      final master =
          parseHlsMaster(_master, 'https://example.com/video/master.m3u8')!;
      expect(
        [for (final v in master.variants) v.height],
        [360, 480, 1080],
      );
      // The average is what a rung really costs; the peak is a worst case.
      expect(master.variants.last.plannedBitrate, 6000000);
      expect(master.variants.first.plannedBitrate, 1000000);
      expect(master.variants.first.label, '360p');
    });

    test('resolves relative URIs against the master, absolute ones untouched',
        () {
      final master =
          parseHlsMaster(_master, 'https://example.com/video/master.m3u8')!;
      expect(
        master.variants.first.url,
        'https://example.com/video/360p/stream.m3u8',
      );
      expect(
        master.variants[1].url,
        'https://cdn.example.com/other/480p/stream.m3u8',
      );
    });

    test('a media playlist is not a ladder', () {
      const media = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXTINF:5.760000,
segment-000.ts
#EXT-X-ENDLIST
''';
      expect(parseHlsMaster(media, 'https://example.com/stream.m3u8'), isNull);
    });

    test('a single-rung master offers nothing to switch to', () {
      const single = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360
360p/stream.m3u8
''';
      expect(parseHlsMaster(single, 'https://example.com/master.m3u8'), isNull);
    });

    test('separate audio is detected', () {
      final master =
          parseHlsMaster(_master, 'https://example.com/video/master.m3u8')!;
      expect(master.hasSeparateAudio, isTrue);
      expect(master.renditions.single.url,
          'https://example.com/video/audio/fa.m3u8');
    });
  });

  group('buildVariantPlaylist', () {
    test('keeps the alternate audio a bare variant would have dropped', () {
      final master =
          parseHlsMaster(_master, 'https://example.com/video/master.m3u8')!;
      final playlist = buildVariantPlaylist(master, master.variants.first);
      expect(playlist, contains('#EXTM3U'));
      // One rung, so there is nothing left for ffmpeg to choose between.
      expect('#EXT-X-STREAM-INF'.allMatches(playlist).length, 1);
      expect(playlist, contains('https://example.com/video/360p/stream.m3u8'));
      // Absolute, so the playlist can be played from anywhere on disk.
      expect(
        playlist,
        contains('URI="https://example.com/video/audio/fa.m3u8"'),
      );
      expect(playlist, isNot(contains('URI="audio/fa.m3u8"')));
      expect(playlist, contains('NAME="فارسی"'));
    });
  });
}
