import 'package:flutter_test/flutter_test.dart';
import 'package:playora/src/analytics/watch_interval.dart';

void main() {
  const cdn = (host: 'cdn.example.com', bytesPerSecond: 100000.0);

  group('WatchIntervalAccumulator', () {
    test('counts only seconds that actually played', () {
      final totals = WatchIntervalAccumulator();
      totals
        ..sample(playing: true, position: 1, width: 1280, height: 720)
        ..sample(playing: false, position: 1, width: 1280, height: 720)
        ..sample(playing: true, position: 2, width: 1280, height: 720);
      expect(totals.playDuration, 2);
    });

    test('reports the time-weighted average resolution', () {
      final totals = WatchIntervalAccumulator();
      for (var i = 0; i < 3; i++) {
        totals.sample(
          playing: true,
          position: i + 1.0,
          width: 1920,
          height: 1080,
        );
      }
      totals.sample(playing: true, position: 4, width: 1280, height: 720);
      final info = totals.snapshot()!;
      final parts = info.quality!.split('*').map(int.parse).toList();
      final pixels = (3 * 1920 * 1080 + 1280 * 720) / 4;
      expect(parts[0] * parts[1], closeTo(pixels, pixels * 0.01));
      expect(parts[0] / parts[1], closeTo(16 / 9, 0.01));
    });

    test('falls back to the current size before anything was sized', () {
      final totals = WatchIntervalAccumulator()
        ..sample(playing: true, position: 2, width: null, height: null);
      expect(totals.quality((854, 480)), '854*480');
    });

    test('charges each stretch of timeline once, per host', () {
      final totals = WatchIntervalAccumulator()
        ..sample(
          playing: true,
          position: 2,
          width: 1280,
          height: 720,
          buffered: (0, 10),
          rate: cdn,
        )
        ..sample(
          playing: true,
          position: 3,
          width: 1280,
          height: 720,
          buffered: (3, 12),
          rate: cdn,
        )
        ..sample(
          playing: true,
          position: 50,
          width: 1280,
          height: 720,
          buffered: (50, 55),
          rate: (host: 'edge.example.com', bytesPerSecond: 200000.0),
        );
      final info = totals.snapshot()!;
      expect(info.bytesByHost, {
        'cdn.example.com': 1200000,
        'edge.example.com': 1000000,
      });
      expect(info.downloadedBytes, 2200000);
      expect(info.estimatedBytes, 2200000);
    });

    test('stays quiet until playback is past its first second', () {
      final totals = WatchIntervalAccumulator()
        ..sample(playing: true, position: 0.5, width: 1280, height: 720);
      expect(totals.snapshot(), isNull);
    });

    test('keeps the last counted position, not one from a stall', () {
      final totals = WatchIntervalAccumulator()
        ..sample(playing: true, position: 30, width: 1280, height: 720)
        ..sample(playing: false, position: 90, width: 1280, height: 720);
      expect(totals.snapshot()!.position, 30);
    });
  });
}
