import 'package:flutter_test/flutter_test.dart';
import 'package:playora/playora.dart';

void main() {
  group('ad type equality', () {
    test('AdOffset compares by kind and position', () {
      expect(AdOffset.pre, AdOffset.pre);
      expect(AdOffset.post, AdOffset.post);
      expect(
        AdOffset.at(const Duration(minutes: 5)),
        AdOffset.at(const Duration(minutes: 5)),
      );
      expect(
        AdOffset.at(const Duration(minutes: 5)),
        isNot(AdOffset.at(const Duration(minutes: 6))),
      );
      expect(AdOffset.pre, isNot(AdOffset.post));
    });

    test('AdConfig compares by value', () {
      const a = AdConfig(src: 'x.m3u8', skipAfter: Duration(seconds: 5));
      const b = AdConfig(src: 'x.m3u8', skipAfter: Duration(seconds: 5));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const AdConfig(src: 'y.m3u8')));
      expect(a, isNot(const AdConfig(src: 'x.m3u8', skippable: false)));
    });

    test('AdBreak compares by value including offset', () {
      final a = AdBreak(
        src: 'x.m3u8',
        offset: AdOffset.at(const Duration(minutes: 1)),
      );
      final b = AdBreak(
        src: 'x.m3u8',
        offset: AdOffset.at(const Duration(minutes: 1)),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(AdBreak(src: 'x.m3u8', offset: AdOffset.post)));
    });

    test('a rebuilt identical list is equal element-wise', () {
      List<AdBreak> build() => [
        const AdBreak(src: 'pre.m3u8'),
        AdBreak(
          src: 'mid.m3u8',
          offset: AdOffset.at(const Duration(minutes: 10)),
          skippable: false,
          clickThrough: 'https://sponsor.example.com',
        ),
      ];
      // What the player's didUpdateWidget relies on: a host getter that
      // rebuilds the list every build must NOT count as a schedule change.
      expect(build(), orderedEquals(build()));
    });
  });
}
