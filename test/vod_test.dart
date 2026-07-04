import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:playora/playora.dart';

void main() {
  group('resolveVodSource', () {
    test('standard passes through untouched', () async {
      final r = await resolveVodSource(
        'https://cdn.example.com/master.m3u8',
        VodProvider.standard,
      );
      expect(r.src, 'https://cdn.example.com/master.m3u8');
      expect(r.thumbnails, isNull);
    });

    test('poyan exchanges the token via POST', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'status': 'ok',
            'data': {
              'play_data': {
                'play_url': 'https://poyan.example/stream.m3u8',
                'thumbnails': [
                  {'url': 'https://poyan.example/thumbs.vtt'},
                ],
              },
            },
          }),
          200,
        );
      });

      final r = await resolveVodSource(
        'tok%3D123',
        VodProvider.poyan,
        client: client,
      );
      expect(r.src, 'https://poyan.example/stream.m3u8');
      expect(r.thumbnails, 'https://poyan.example/thumbs.vtt');
      expect(captured.method, 'POST');
      expect(captured.url.toString(), poyanDefaultUrl);
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['method'], 'getPlayContentInfo');
      // The token is URL-decoded before the exchange.
      expect((body['data'] as Map)['play_token'], 'tok=123');
    });

    test('abr_hamrahi substitutes {token} and prefers vtt_mobile on mobile',
        () async {
      late Uri captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response(
          jsonEncode({
            'stream_link': 'https://hamrahi.example/stream.m3u8',
            'vtt': 'https://hamrahi.example/desktop.vtt',
            'vtt_mobile': 'https://hamrahi.example/mobile.vtt',
          }),
          200,
        );
      });

      final mobile = await resolveVodSource(
        'abc',
        VodProvider.abrHamrahi,
        client: client,
        mobile: true,
        customUrl: {
          VodProvider.abrHamrahi: 'https://api.example.com/vod/{token}',
        },
      );
      expect(captured.toString(), 'https://api.example.com/vod/abc');
      expect(mobile.src, 'https://hamrahi.example/stream.m3u8');
      expect(mobile.thumbnails, 'https://hamrahi.example/mobile.vtt');

      final desktop = await resolveVodSource(
        'abc',
        VodProvider.abrHamrahi,
        client: client,
        mobile: false,
      );
      expect(desktop.thumbnails, 'https://hamrahi.example/desktop.vtt');
    });

    test('abr_hamrahi falls back to whichever vtt exists', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'stream_link': 's.m3u8',
              'vtt_mobile': 'm.vtt',
            }),
            200,
          ));
      final r = await resolveVodSource(
        'abc',
        VodProvider.abrHamrahi,
        client: client,
        mobile: false,
      );
      expect(r.thumbnails, 'm.vtt');
    });

    test('empty token throws', () async {
      expect(
        () => resolveVodSource('', VodProvider.abrHamrahi,
            client: MockClient((_) async => http.Response('{}', 200))),
        throwsA(isA<VodResolutionException>()),
      );
    });

    test('missing stream_link throws', () async {
      final client =
          MockClient((_) async => http.Response(jsonEncode({}), 200));
      expect(
        () =>
            resolveVodSource('abc', VodProvider.abrHamrahi, client: client),
        throwsA(isA<VodResolutionException>()),
      );
    });
  });
}
