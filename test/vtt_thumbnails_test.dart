import 'package:flutter_test/flutter_test.dart';
import 'package:playora/playora.dart';

const _sprite = '''
WEBVTT

00:00:00.000 --> 00:00:05.000
sprite.jpg#xywh=0,0,160,90

00:00:05.000 --> 00:00:10.000
sprite.jpg#xywh=160,0,160,90

00:00:10.000 --> 00:00:15.000
sprite.jpg#xywh=0,90,160,90
''';

const _individual = '''
WEBVTT

1
00:00.000 --> 00:04.000
thumbs/thumb-1.png

2
00:04.000 --> 01:04.000
https://cdn.example.com/thumb-2.png
''';

void main() {
  group('ThumbnailTrack.parse', () {
    test('parses sprite cues with #xywh regions', () {
      final track = ThumbnailTrack.parse(
        _sprite,
        baseUrl: 'https://cdn.example.com/v/thumbnails.vtt',
      );
      expect(track.cues, hasLength(3));
      final first = track.cues.first;
      expect(first.start, Duration.zero);
      expect(first.end, const Duration(seconds: 5));
      expect(first.imageUrl, 'https://cdn.example.com/v/sprite.jpg');
      expect(first.region, (x: 0, y: 0, w: 160, h: 90));
      expect(track.cues[2].region, (x: 0, y: 90, w: 160, h: 90));
    });

    test('parses MM:SS timestamps, cue identifiers and absolute URLs', () {
      final track = ThumbnailTrack.parse(
        _individual,
        baseUrl: 'https://cdn.example.com/v/thumbnails.vtt',
      );
      expect(track.cues, hasLength(2));
      expect(track.cues[0].imageUrl,
          'https://cdn.example.com/v/thumbs/thumb-1.png');
      expect(track.cues[0].region, isNull);
      expect(track.cues[1].imageUrl, 'https://cdn.example.com/thumb-2.png');
      expect(track.cues[1].end, const Duration(minutes: 1, seconds: 4));
    });

    test('handles CRLF and hour-long timestamps', () {
      final track = ThumbnailTrack.parse(
        'WEBVTT\r\n\r\n01:02:03.500 --> 01:02:08.000\r\na.jpg\r\n',
      );
      expect(track.cues.single.start,
          const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500));
    });
  });

  group('ThumbnailTrack.cueAt', () {
    final track = ThumbnailTrack.parse(_sprite);

    test('exact range lookup', () {
      expect(track.cueAt(const Duration(seconds: 6))!.region!.x, 160);
    });

    test('falls back to the nearest earlier cue past the end', () {
      expect(track.cueAt(const Duration(seconds: 99))!.region!.y, 90);
    });

    test('null before the first cue when nothing covers it', () {
      final t = ThumbnailTrack.parse('''
WEBVTT

00:00:10.000 --> 00:00:15.000
a.jpg
''');
      expect(t.cueAt(Duration.zero), isNull);
    });
  });
}
