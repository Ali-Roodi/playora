import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playora/playora.dart';

LogplexAnalyticsConfig _cfg({int batchSize = 20}) => LogplexAnalyticsConfig(
      baseUrl: 'https://ingest.example.com',
      apiKey: 'key-1',
      userId: 'user-1',
      contentId: 'content-1',
      contentType: 'movie',
      batchSize: batchSize,
      appVersion: '1.0.0',
    );

void main() {
  group('LogplexAnalyticsClient', () {
    test('flush posts a snake_case batch with auth header', () async {
      final requests = <http.Request>[];
      final client = LogplexAnalyticsClient(
        _cfg(),
        httpClient: MockClient((req) async {
          requests.add(req);
          return http.Response('{}', 200);
        }),
      );

      client.track(
        LogplexEventType.play,
        const TrackFields(playerTimeMs: 1500, quality: '720p'),
      );
      client.track(
        LogplexEventType.seek,
        const TrackFields(seekFromMs: 1000, seekToMs: 9000),
      );
      await client.flush();

      expect(requests, hasLength(1));
      final req = requests.single;
      expect(req.url.path, '/v1/ingest/events/batch');
      expect(req.headers['X-API-Key'], 'key-1');
      final events =
          (jsonDecode(req.body) as Map<String, dynamic>)['events'] as List;
      expect(events, hasLength(2));
      final play = events[0] as Map<String, dynamic>;
      expect(play['event_type'], 'play');
      expect(play['player_time_ms'], 1500);
      expect(play['quality'], '720p');
      expect(play['content_id'], 'content-1');
      expect(play['user_id'], 'user-1');
      expect(play['app_version'], '1.0.0');
      expect(play['session_id'], client.sessionId);
      final seek = events[1] as Map<String, dynamic>;
      expect(seek['event_type'], 'seek');
      expect(seek['seek_from_ms'], 1000);
      expect(seek['seek_to_ms'], 9000);
    });

    test('auto-flushes when the batch size is reached', () async {
      final requests = <http.Request>[];
      final client = LogplexAnalyticsClient(
        _cfg(batchSize: 3),
        httpClient: MockClient((req) async {
          requests.add(req);
          return http.Response('{}', 200);
        }),
      );

      client.track(LogplexEventType.play);
      client.track(LogplexEventType.pause);
      expect(requests, isEmpty);
      client.track(LogplexEventType.resume);
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(1));
    });

    test('retries 5xx, gives up on 4xx', () async {
      var attempts = 0;
      final failing = LogplexAnalyticsClient(
        _cfg(),
        httpClient: MockClient((req) async {
          attempts++;
          return http.Response('oops', 500);
        }),
      );
      failing.track(LogplexEventType.play);
      await failing.flush();
      expect(attempts, 3); // initial + 2 retries

      attempts = 0;
      final rejected = LogplexAnalyticsClient(
        _cfg(),
        httpClient: MockClient((req) async {
          attempts++;
          return http.Response('bad', 400);
        }),
      );
      rejected.track(LogplexEventType.play);
      await rejected.flush();
      expect(attempts, 1); // 4xx won't succeed on retry
    });

    test('getResume parses the progress payload', () async {
      final client = LogplexAnalyticsClient(
        _cfg(),
        httpClient: MockClient((req) async {
          expect(req.url.path, '/v1/ingest/playback/content-1/progress');
          expect(req.url.queryParameters['user_id'], 'user-1');
          return http.Response(
            jsonEncode({
              'data': {
                'position_seconds': 125.5,
                'duration_seconds': 600,
                'percent_watched': 20.9,
                'completed': false,
              },
            }),
            200,
          );
        }),
      );
      final resume = await client.getResume();
      expect(resume, isNotNull);
      expect(resume!.position, const Duration(milliseconds: 125500));
      expect(resume.duration, const Duration(minutes: 10));
      expect(resume.completed, isFalse);
    });

    test('getResume returns null on missing data or errors', () async {
      final empty = LogplexAnalyticsClient(
        _cfg(),
        httpClient:
            MockClient((_) async => http.Response(jsonEncode({}), 200)),
      );
      expect(await empty.getResume(), isNull);

      final failing = LogplexAnalyticsClient(
        _cfg(),
        httpClient: MockClient((_) async => http.Response('nope', 404)),
      );
      expect(await failing.getResume(), isNull);
    });

    test('disabled config sends nothing', () async {
      var called = false;
      final client = LogplexAnalyticsClient(
        LogplexAnalyticsConfig(
          baseUrl: 'https://x',
          apiKey: 'k',
          userId: 'u',
          contentId: 'c',
          disabled: true,
        ),
        httpClient: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      client.track(LogplexEventType.play);
      await client.flush();
      expect(await client.getResume(), isNull);
      expect(called, isFalse);
    });

    test('reuses a provided session id', () {
      final client = LogplexAnalyticsClient(
        LogplexAnalyticsConfig(
          baseUrl: 'https://x',
          apiKey: 'k',
          userId: 'u',
          contentId: 'c',
          sessionId: 'session-abc',
        ),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(client.sessionId, 'session-abc');
    });
  });
}
