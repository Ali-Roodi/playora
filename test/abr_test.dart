import 'package:flutter_test/flutter_test.dart';
import 'package:playora/playora.dart';

/// Drives the governor by hand: the ladder, the playhead's buffer and the
/// stall flag are all fed from the harness, and `tick()` is called directly
/// instead of waiting on the real timer.
class _Harness {
  _Harness({
    List<int> heights = const [360, 480, 720, 1080],
    PlayoraAbrConfig config = const PlayoraAbrConfig(
      probeInterval: Duration(seconds: 2),
      upshiftCooldown: Duration.zero,
      downshiftCooldown: Duration.zero,
    ),
  }) : levels = [
          for (var i = 0; i < heights.length; i++)
            AbrLevel(index: i, height: heights[i]),
        ] {
    governor = PlayoraAbrGovernor(
      config: config,
      levels: () => levels,
      currentIndex: () => index,
      bufferAhead: () => buffered,
      playing: () => playing,
      stalled: () => stalled,
      onSwitch: (level, decision) {
        index = level.index;
        switches.add((height: level.height, decision: decision));
      },
    );
  }

  final List<AbrLevel> levels;
  late final PlayoraAbrGovernor governor;

  int index = 2;
  Duration buffered = Duration.zero;
  bool playing = true;
  bool stalled = false;
  final switches = <({int height, AbrDecision decision})>[];

  /// One probe interval of wall clock has to pass between samples for the
  /// fill-rate estimate to move, so ticks are spaced with a real delay.
  Future<void> tick({int times = 1}) async {
    for (var i = 0; i < times; i++) {
      governor.tick();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }
}

void main() {
  group('PlayoraAbrGovernor', () {
    test('steps down on a stall', () async {
      // Healthy buffer, so only the stall itself can trigger the step.
      final h = _Harness()..buffered = const Duration(seconds: 40);
      await h.tick();
      h.stalled = true;
      await h.tick();
      expect(h.switches.single.decision, AbrDecision.down);
      expect(h.switches.single.height, 480);
    });

    test('steps down when the buffer drains and the link cannot keep up',
        () async {
      final h = _Harness()..buffered = const Duration(seconds: 20);
      await h.tick();
      // Buffer collapsing: less media arrives than playback consumes.
      h.buffered = const Duration(seconds: 3);
      await h.tick();
      expect(h.switches.single.decision, AbrDecision.down);
    });

    test('never steps below the bottom rung', () async {
      final h = _Harness()
        ..index = 0
        ..buffered = Duration.zero
        ..stalled = true;
      await h.tick(times: 3);
      expect(h.switches, isEmpty);
      expect(h.index, 0);
    });

    test('holds while the buffer is healthy but the link has no headroom',
        () async {
      final h = _Harness()..buffered = const Duration(seconds: 40);
      // Buffer stays flat: the connection delivers exactly one second of
      // media per second, so 1080p (2.25x the bitrate of 720p) is out of
      // reach.
      await h.tick(times: 6);
      expect(h.switches, isEmpty);
    });

    test('steps up once the buffer is deep enough to prove headroom',
        () async {
      final h = _Harness()..buffered = const Duration(seconds: 200);
      await h.tick(times: 5);
      expect(h.switches, isNotEmpty);
      expect(h.switches.first.decision, AbrDecision.up);
      expect(h.switches.first.height, 1080);
    });


    test('climbs to the top in one switch instead of a staircase', () async {
      final h = _Harness()
        ..index = 0
        ..buffered = const Duration(seconds: 20);
      await h.tick();
      // ~17 s of media arriving per second of wall clock, on a buffer that
      // stays short of the runway rule so the fill rate is what decides.
      for (var i = 1; i <= 3; i++) {
        h.buffered = Duration(seconds: 20 + 5 * i);
        await h.tick();
      }
      expect(h.switches, hasLength(1));
      expect(h.switches.single.decision, AbrDecision.up);
      expect(h.switches.single.height, 1080);
    });

    test('drops straight onto a rung the collapsed link can carry', () async {
      final h = _Harness()
        ..index = 3
        ..buffered = const Duration(seconds: 14);
      await h.tick();
      // The buffer bleeds 2 s of media per tick: almost nothing is arriving.
      for (final seconds in [12, 10, 8, 6, 4]) {
        h.buffered = Duration(seconds: seconds);
        await h.tick();
      }
      expect(h.switches, hasLength(1));
      expect(h.switches.single.decision, AbrDecision.down);
      // A staircase would have stopped at 720 and needed two more switches to
      // get here.
      expect(h.switches.single.height, lessThan(720));
    });

    test('a stall inside the settle window is the switch, not a failure',
        () async {
      final h = _Harness()..buffered = const Duration(seconds: 200);
      await h.tick(times: 2);
      expect(h.switches, hasLength(1), reason: 'runway buffer earns the top');
      // The rung it just moved to is filling its cache — which mpv reports as
      // a stall. Panicking here would undo the switch on the spot.
      h.stalled = true;
      await h.tick(times: 2);
      expect(h.switches, hasLength(1));
    });

    test('a stall once the settle window has passed does step down', () async {
      final h = _Harness(
        config: const PlayoraAbrConfig(
          upshiftCooldown: Duration.zero,
          downshiftCooldown: Duration.zero,
          switchSettleTime: Duration(milliseconds: 100),
        ),
      )..buffered = const Duration(seconds: 200);
      await h.tick(times: 2);
      expect(h.switches, hasLength(1));
      h.stalled = true;
      await h.tick(times: 2);
      expect(h.switches.last.decision, AbrDecision.down);
    });
    test('does not act while paused', () async {
      final h = _Harness()
        ..playing = false
        ..stalled = true
        ..buffered = Duration.zero;
      await h.tick(times: 3);
      expect(h.switches, isEmpty);
    });

    test('a ladder with a single rung is left alone', () async {
      final h = _Harness(heights: const [720])
        ..index = 0
        ..stalled = true;
      await h.tick(times: 3);
      expect(h.switches, isEmpty);
    });

    test('startupLevel honours the ceiling and the remembered height', () {
      final h = _Harness(
        config: const PlayoraAbrConfig(startupHeightCeiling: 720),
      );
      expect(h.governor.startupLevel(h.levels)!.height, 720);
      expect(
        h.governor.startupLevel(h.levels, rememberedHeight: 480)!.height,
        480,
      );
      // A remembered height the manifest no longer offers falls back to the
      // best rung under it.
      expect(
        h.governor.startupLevel(h.levels, rememberedHeight: 1000)!.height,
        720,
      );
    });

    test('startupLevel defaults to the top rung', () {
      // Bandwidth is assumed cheap: open at the best rung and let the
      // governor walk down if the link cannot hold it.
      final h = _Harness();
      expect(h.governor.startupLevel(h.levels)!.height, 1080);
    });

    test('a disabled governor never starts its loop', () {
      final h = _Harness(config: const PlayoraAbrConfig(enabled: false))
        ..stalled = true;
      h.governor.start();
      h.governor.tick();
      expect(h.switches, isEmpty);
    });
  });

  group('AbrLevel', () {
    test('reported bitrate wins over the height estimate', () {
      expect(const AbrLevel(index: 0, height: 720, bitrate: 1234).weight, 1234);
    });

    test('the height estimate is monotonic', () {
      const low = AbrLevel(index: 0, height: 480);
      const high = AbrLevel(index: 1, height: 1080);
      expect(high.weight, greaterThan(low.weight));
    });
  });
}
