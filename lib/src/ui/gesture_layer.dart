import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/prefs.dart';
import '../i18n/strings.dart';
import '../theme/player_theme.dart';

const _moveThreshold = 8.0;
const _longPressMs = 450;
const _doubleTapMs = 300;

enum _Side { left, center, right }

enum _Axis { none, vertical, horizontal }

/// Touch-first gesture surface beneath the controls: double-tap edges to skip
/// ±10s, long-press for 2× speed, vertical swipe for brightness (left half)
/// and volume (right half). Desktop: single-click toggles play, double-click
/// toggles fullscreen, hover reveals controls. Brightness is a dim overlay.
class GestureLayer extends StatefulWidget {
  const GestureLayer({
    super.key,
    required this.controller,
    required this.theme,
    required this.strings,
    required this.onTapToggle,
    this.onActivity,
    this.onToggleFullscreen,
    this.persist = false,
    this.prefsStore,
  });

  final PlayoraController controller;
  final PlayoraTheme theme;
  final PlayerStrings strings;

  /// Toggle controls visibility (single tap on touch).
  final VoidCallback onTapToggle;

  /// Pointer activity — reveals controls + resets the idle timer.
  final VoidCallback? onActivity;

  /// Desktop double-click.
  final VoidCallback? onToggleFullscreen;

  /// Persist brightness across sessions.
  final bool persist;
  final PlayerPrefsStore? prefsStore;

  @override
  State<GestureLayer> createState() => GestureLayerState();
}

class GestureLayerState extends State<GestureLayer> {
  double _brightness = 1.0;
  bool _rate2x = false;
  ({_Side side, int seconds})? _skip;
  ({bool isBrightness, double value})? _indicator;

  // Gesture tracking (single pointer).
  bool _active = false;
  bool _touch = false;
  Offset _origin = Offset.zero;
  Size _surface = Size.zero;
  _Side _side = _Side.center;
  bool _leftHalf = false;
  bool _moved = false;
  _Axis _axis = _Axis.none;
  double _startVolume = 1;
  double _startBrightness = 1;
  bool _brightnessTouched = false;
  double _prevRate = 1;
  Timer? _longPress;
  Timer? _singleTap;
  Timer? _skipTimer;
  Timer? _indicatorTimer;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  _Side _lastTapSide = _Side.center;

  /// Current dim level (1 = full brightness). Exposed for tests.
  double get brightness => _brightness;

  @override
  void initState() {
    super.initState();
    if (widget.persist) {
      widget.prefsStore?.load().then((p) {
        if (mounted && p.brightness != null) {
          setState(() => _brightness = p.brightness!.clamp(0.2, 1.0));
        }
      });
    }
  }

  @override
  void dispose() {
    _longPress?.cancel();
    _singleTap?.cancel();
    _skipTimer?.cancel();
    _indicatorTimer?.cancel();
    super.dispose();
  }

  void _showSkip(_Side side, int seconds) {
    setState(() => _skip = (side: side, seconds: seconds));
    _skipTimer?.cancel();
    _skipTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _skip = null);
    });
  }

  void _hideIndicatorSoon() {
    _indicatorTimer?.cancel();
    _indicatorTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _indicator = null);
    });
  }

  void _onPointerDown(PointerDownEvent e, Size size) {
    _touch = e.kind == PointerDeviceKind.touch;
    // On touch, a tap is a toggle (handled on pointer-up) — don't reveal here
    // or it fights the toggle and the controls flash then hide.
    if (!_touch) widget.onActivity?.call();
    _indicatorTimer?.cancel();
    _active = true;
    _origin = e.localPosition;
    _surface = size;
    _side = e.localPosition.dx < size.width / 3
        ? _Side.left
        : e.localPosition.dx > size.width * 2 / 3
            ? _Side.right
            : _Side.center;
    _leftHalf = e.localPosition.dx < size.width / 2;
    _moved = false;
    _axis = _Axis.none;
    _startVolume = widget.controller.state.value.volume;
    _startBrightness = _brightness;
    _singleTap?.cancel();
    if (_touch) {
      _longPress = Timer(const Duration(milliseconds: _longPressMs), () {
        if (!_moved && _active) {
          _prevRate = widget.controller.state.value.rate;
          widget.controller.setRate(2.0);
          setState(() => _rate2x = true);
        }
      });
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_active) return;
    final delta = e.localPosition - _origin;
    if (!_moved && delta.distance > _moveThreshold) {
      _moved = true;
      _axis = delta.dy.abs() > delta.dx.abs() ? _Axis.vertical : _Axis.horizontal;
      _longPress?.cancel();
    }
    if (_touch && _axis == _Axis.vertical && !_rate2x && _surface.height > 0) {
      final frac = -delta.dy / _surface.height; // up increases
      if (_leftHalf) {
        final b = (_startBrightness + frac).clamp(0.2, 1.0);
        _brightnessTouched = true;
        setState(() {
          _brightness = b;
          _indicator = (isBrightness: true, value: b);
        });
      } else {
        final v = (_startVolume + frac).clamp(0.0, 1.0);
        widget.controller.setVolume(v);
        setState(() => _indicator = (isBrightness: false, value: v));
      }
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    if (!_active) return;
    _active = false;
    _longPress?.cancel();

    if (widget.persist && _brightnessTouched) {
      widget.prefsStore?.save(PlayerPrefs(brightness: _brightness));
      _brightnessTouched = false;
    }

    if (_rate2x) {
      widget.controller.setRate(_prevRate);
      setState(() => _rate2x = false);
      return;
    }
    if (_moved) {
      if (_axis == _Axis.vertical) _hideIndicatorSoon();
      return;
    }

    final now = DateTime.now();
    final sinceLast = now.difference(_lastTapAt).inMilliseconds;
    if (_touch) {
      // Mobile: double-tap edges seek ±10s; single tap toggles controls.
      final isDouble = sinceLast < _doubleTapMs && _lastTapSide == _side;
      if (isDouble && _side != _Side.center) {
        _singleTap?.cancel();
        final delta = _side == _Side.left
            ? const Duration(seconds: -10)
            : const Duration(seconds: 10);
        widget.controller.seekBy(delta);
        _showSkip(_side, 10);
        _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);
        return;
      }
      _lastTapAt = now;
      _lastTapSide = _side;
      _singleTap = Timer(const Duration(milliseconds: _doubleTapMs),
          () => widget.onTapToggle());
    } else {
      // Desktop, YouTube-style: click = play/pause, double-click = fullscreen.
      if (sinceLast < _doubleTapMs) {
        _singleTap?.cancel();
        widget.onToggleFullscreen?.call();
        _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);
        return;
      }
      _lastTapAt = now;
      _singleTap = Timer(const Duration(milliseconds: _doubleTapMs),
          () => widget.controller.togglePlay());
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _longPress?.cancel();
    _singleTap?.cancel();
    _active = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      return MouseRegion(
        onHover: (_) => widget.onActivity?.call(),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _onPointerDown(e, size),
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_brightness < 1)
                IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 1 - _brightness),
                  ),
                ),
              if (_skip != null)
                Align(
                  alignment: _skip!.side == _Side.left
                      ? const Alignment(-0.7, 0)
                      : const Alignment(0.7, 0),
                  child: IgnorePointer(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _skip!.side == _Side.left
                              ? Icons.replay_10
                              : Icons.forward_10,
                          color: Colors.white,
                          size: 44,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 8),
                          ],
                        ),
                        Text(
                          '${_skip!.seconds}s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 8),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_rate2x)
                Align(
                  alignment: const Alignment(0, -0.75),
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: theme.panel,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: theme.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fast_forward,
                              color: theme.accent, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            '2×',
                            style: TextStyle(
                              color: theme.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_indicator != null)
                Align(
                  alignment: _indicator!.isBrightness
                      ? const Alignment(-0.85, 0)
                      : const Alignment(0.85, 0),
                  child: IgnorePointer(
                    child: _VerticalIndicator(
                      theme: theme,
                      icon: _indicator!.isBrightness
                          ? Icons.brightness_6
                          : Icons.volume_up,
                      value: _indicator!.value,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _VerticalIndicator extends StatelessWidget {
  const _VerticalIndicator({
    required this.theme,
    required this.icon,
    required this.value,
  });

  final PlayoraTheme theme;
  final IconData icon;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: theme.panel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 6,
            height: 96,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: theme.text.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                FractionallySizedBox(
                  heightFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.accent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Icon(icon, color: theme.text, size: 18),
        ],
      ),
    );
  }
}
