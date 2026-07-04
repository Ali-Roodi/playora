import 'package:flutter_test/flutter_test.dart';
import 'package:playora/src/ui/widgets/time_slider.dart';

void main() {
  group('formatDuration', () {
    test('mm:ss under an hour', () {
      expect(formatDuration(Duration.zero), '00:00');
      expect(formatDuration(const Duration(seconds: 7)), '00:07');
      expect(formatDuration(const Duration(minutes: 12, seconds: 34)), '12:34');
      expect(
          formatDuration(const Duration(minutes: 59, seconds: 59)), '59:59');
    });

    test('h:mm:ss above an hour', () {
      expect(formatDuration(const Duration(hours: 1)), '1:00:00');
      expect(
        formatDuration(const Duration(hours: 2, minutes: 3, seconds: 4)),
        '2:03:04',
      );
    });
  });
}
