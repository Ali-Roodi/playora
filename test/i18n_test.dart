import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playora/playora.dart';

void main() {
  group('PlayerStrings', () {
    test('fa table is complete Persian', () {
      final s = PlayerStrings.of(PlayerLocale.fa);
      expect(s.play, 'پخش');
      expect(s.qualityAuto, 'اتوماتیک');
      expect(s.resumeCta, 'مشاهده از دقیقه');
      expect(s.skipAd, 'رد کردن آگهی');
    });

    test('en table is complete English', () {
      final s = PlayerStrings.of(PlayerLocale.en);
      expect(s.play, 'Play');
      expect(s.nextUpTitle, 'Up next');
      expect(s.off, 'Off');
    });
  });

  group('dirFor', () {
    test('fa defaults to RTL, en to LTR', () {
      expect(dirFor(PlayerLocale.fa, null), TextDirection.rtl);
      expect(dirFor(PlayerLocale.en, null), TextDirection.ltr);
    });

    test('explicit override wins', () {
      expect(dirFor(PlayerLocale.fa, TextDirection.ltr), TextDirection.ltr);
      expect(dirFor(PlayerLocale.en, TextDirection.rtl), TextDirection.rtl);
    });
  });

  group('localeDigits', () {
    test('fa uses Persian digits', () {
      expect(localeDigits(PlayerLocale.fa, 1402), '۱۴۰۲');
      expect(localeDigits(PlayerLocale.fa, 0), '۰');
    });

    test('en keeps Western digits', () {
      expect(localeDigits(PlayerLocale.en, 32), '32');
    });
  });
}
