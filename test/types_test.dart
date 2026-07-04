import 'package:flutter_test/flutter_test.dart';
import 'package:playora/playora.dart';

void main() {
  group('VideoSource', () {
    test('quality label derives from height, explicit label wins', () {
      expect(const VideoSource(src: 'a.mp4', height: 720).qualityLabel, '720p');
      expect(
        const VideoSource(src: 'a.mp4', height: 720, label: 'HD').qualityLabel,
        'HD',
      );
      expect(const VideoSource(src: 'a.mp4').qualityLabel, 'a.mp4');
    });
  });

  group('AdOffset', () {
    test('pre/post/mid classification', () {
      expect(AdOffset.pre.isPre, isTrue);
      expect(AdOffset.post.isPost, isTrue);
      final mid = AdOffset.at(const Duration(seconds: 90));
      expect(mid.isMid, isTrue);
      expect(mid.at, const Duration(seconds: 90));
      expect(mid.isPre, isFalse);
    });
  });

  group('PlayerPrefs', () {
    test('merge keeps existing values and applies the patch', () {
      const base = PlayerPrefs(volume: 0.8, rate: 1.5);
      final merged = base.merge(const PlayerPrefs(muted: true, rate: 2.0));
      expect(merged.volume, 0.8);
      expect(merged.muted, isTrue);
      expect(merged.rate, 2.0);
      expect(merged.brightness, isNull);
    });

    test('json round-trip', () {
      const prefs =
          PlayerPrefs(volume: 0.5, muted: false, rate: 1.25, brightness: 0.7);
      final restored = PlayerPrefs.fromJson(
        Map<String, dynamic>.from(prefs.toJson()),
      );
      expect(restored.volume, 0.5);
      expect(restored.muted, isFalse);
      expect(restored.rate, 1.25);
      expect(restored.brightness, 0.7);
    });
  });

  group('LogplexEventType', () {
    test('wire names are snake_case canonical strings', () {
      expect(LogplexEventType.playStartSuccess.wire, 'play_start_success');
      expect(LogplexEventType.bufferStart.wire, 'buffer_start');
      expect(LogplexEventType.progress25.wire, 'progress_25');
      expect(LogplexEventType.adComplete.wire, 'ad_complete');
    });
  });

  group('LogplexAnalyticsConfig.copyWith', () {
    test('re-keys per-episode fields, keeps the rest', () {
      const base = LogplexAnalyticsConfig(
        baseUrl: 'https://x',
        apiKey: 'k',
        userId: 'u',
        contentId: 'movie-1',
        contentType: 'series',
      );
      final episode = base.copyWith(
        contentId: 'ep-2',
        contentTitle: 'Episode 2',
      );
      expect(episode.contentId, 'ep-2');
      expect(episode.contentTitle, 'Episode 2');
      expect(episode.apiKey, 'k');
      expect(episode.contentType, 'series');
    });
  });
}
