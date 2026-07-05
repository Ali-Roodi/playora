import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/vtt_thumbnails.dart';
import '../../theme/player_theme.dart';

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// Custom scrubber: buffered range + played fill + thumb, with a drag/hover
/// preview bubble showing the target time and (when a [ThumbnailTrack] is
/// available) the scrub thumbnail. Layout is always physical LTR — matching
/// the web player, RTL only affects text.
class PlayerTimeSlider extends StatefulWidget {
  const PlayerTimeSlider({
    super.key,
    required this.theme,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.onSeek,
    this.thumbnails,
    this.onInteraction,
    this.onScrubStart,
    this.onScrubUpdate,
    this.onScrubCancel,
  });

  final PlayoraTheme theme;
  final ValueNotifier<Duration> position;
  final ValueNotifier<Duration> duration;
  final ValueNotifier<Duration> buffer;
  final ValueChanged<Duration> onSeek;
  final ThumbnailTrack? thumbnails;

  /// Called on any pointer activity (keeps the controls revealed).
  final VoidCallback? onInteraction;

  /// Drag-scrub lifecycle (used by the skin for the live scrub preview).
  /// A completed drag ends with [onSeek]; an aborted one with
  /// [onScrubCancel].
  final VoidCallback? onScrubStart;
  final ValueChanged<Duration>? onScrubUpdate;
  final VoidCallback? onScrubCancel;

  @override
  State<PlayerTimeSlider> createState() => _PlayerTimeSliderState();
}

class _PlayerTimeSliderState extends State<PlayerTimeSlider> {
  /// 0..1 while scrubbing/hovering, null otherwise.
  double? _previewFraction;
  bool _dragging = false;

  Duration get _duration => widget.duration.value;

  double _fractionAt(Offset local, double width) =>
      width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0);

  Duration _timeAt(double fraction) => Duration(
      milliseconds: (_duration.inMilliseconds * fraction).round());

  void _commit(double fraction) {
    if (_duration <= Duration.zero) return;
    widget.onSeek(_timeAt(fraction));
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return MouseRegion(
        onHover: (e) {
          widget.onInteraction?.call();
          if (!_dragging) {
            setState(() => _previewFraction = _fractionAt(e.localPosition, width));
          }
        },
        onExit: (_) {
          if (!_dragging) setState(() => _previewFraction = null);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            widget.onInteraction?.call();
            _commit(_fractionAt(d.localPosition, width));
          },
          onHorizontalDragStart: (d) {
            widget.onInteraction?.call();
            widget.onScrubStart?.call();
            setState(() {
              _dragging = true;
              _previewFraction = _fractionAt(d.localPosition, width);
            });
          },
          onHorizontalDragUpdate: (d) {
            widget.onInteraction?.call();
            final fraction = _fractionAt(d.localPosition, width);
            setState(() => _previewFraction = fraction);
            if (_duration > Duration.zero) {
              widget.onScrubUpdate?.call(_timeAt(fraction));
            }
          },
          onHorizontalDragEnd: (_) {
            final f = _previewFraction;
            setState(() {
              _dragging = false;
              _previewFraction = null;
            });
            if (f != null) {
              _commit(f);
            } else {
              widget.onScrubCancel?.call();
            }
          },
          onHorizontalDragCancel: () {
            widget.onScrubCancel?.call();
            setState(() {
              _dragging = false;
              _previewFraction = null;
            });
          },
          child: SizedBox(
            height: 36,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                AnimatedBuilder(
                  animation: Listenable.merge(
                      [widget.position, widget.duration, widget.buffer]),
                  builder: (context, _) {
                    final total = _duration.inMilliseconds;
                    final played = total <= 0
                        ? 0.0
                        : (widget.position.value.inMilliseconds / total)
                            .clamp(0.0, 1.0);
                    final buffered = total <= 0
                        ? 0.0
                        : (widget.buffer.value.inMilliseconds / total)
                            .clamp(0.0, 1.0);
                    final shown = _previewFraction ?? played;
                    return CustomPaint(
                      size: Size(width, 36),
                      painter: _SliderPainter(
                        theme: theme,
                        played: shown,
                        buffered: buffered,
                        emphasized: _dragging || _previewFraction != null,
                      ),
                    );
                  },
                ),
                if (_previewFraction != null && _duration > Duration.zero)
                  _PreviewBubble(
                    theme: theme,
                    fraction: _previewFraction!,
                    width: width,
                    time: _timeAt(_previewFraction!),
                    thumbnails: widget.thumbnails,
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter({
    required this.theme,
    required this.played,
    required this.buffered,
    required this.emphasized,
  });

  final PlayoraTheme theme;
  final double played;
  final double buffered;
  final bool emphasized;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final trackHeight = emphasized ? 6.0 : 4.0;
    final radius = Radius.circular(trackHeight / 2);
    RRect r(double from, double to) => RRect.fromRectAndRadius(
          Rect.fromLTRB(from, cy - trackHeight / 2, to, cy + trackHeight / 2),
          radius,
        );

    canvas.drawRRect(
        r(0, size.width), Paint()..color = theme.text.withValues(alpha: 0.22));
    if (buffered > 0) {
      canvas.drawRRect(r(0, size.width * buffered),
          Paint()..color = theme.text.withValues(alpha: 0.28));
    }
    if (played > 0) {
      canvas.drawRRect(
          r(0, size.width * played), Paint()..color = theme.accent);
    }

    final thumbX = size.width * played;
    canvas.drawCircle(
      Offset(thumbX, cy),
      emphasized ? 9 : 6.5,
      Paint()..color = theme.accent,
    );
    canvas.drawCircle(
      Offset(thumbX, cy),
      emphasized ? 4 : 2.5,
      Paint()..color = theme.accentContrast.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_SliderPainter old) =>
      old.played != played ||
      old.buffered != buffered ||
      old.emphasized != emphasized ||
      old.theme != theme;
}

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({
    required this.theme,
    required this.fraction,
    required this.width,
    required this.time,
    this.thumbnails,
  });

  final PlayoraTheme theme;
  final double fraction;
  final double width;
  final Duration time;
  final ThumbnailTrack? thumbnails;

  @override
  Widget build(BuildContext context) {
    final cue = thumbnails?.cueAt(time);
    const bubbleWidth = 148.0;
    final maxLeft = width - bubbleWidth;
    final left = maxLeft <= 0
        ? 0.0
        : (width * fraction - bubbleWidth / 2).clamp(0.0, maxLeft);
    return Positioned(
      left: left,
      bottom: 40,
      child: IgnorePointer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cue != null)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.border),
                  boxShadow: const [
                    BoxShadow(color: Color(0x66000000), blurRadius: 12),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: SpriteThumbnail(cue: cue, width: bubbleWidth),
              ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.panel,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.border),
              ),
              child: Text(
                formatDuration(time),
                style: TextStyle(
                  color: theme.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws a [ThumbnailCue] — the whole image, or the `#xywh` sprite region
/// cropped out of the sheet.
class SpriteThumbnail extends StatefulWidget {
  const SpriteThumbnail({super.key, required this.cue, required this.width});

  final ThumbnailCue cue;
  final double width;

  @override
  State<SpriteThumbnail> createState() => _SpriteThumbnailState();
}

class _SpriteThumbnailState extends State<SpriteThumbnail> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(SpriteThumbnail old) {
    super.didUpdateWidget(old);
    if (old.cue.imageUrl != widget.cue.imageUrl) _resolve();
  }

  void _resolve() {
    _detach();
    final stream =
        NetworkImage(widget.cue.imageUrl).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (info, _) {
        if (mounted) setState(() => _image = info.image);
      },
      onError: (_, _) {},
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _detach() {
    final l = _listener;
    if (l != null) _stream?.removeListener(l);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    final region = widget.cue.region;
    final srcW = region?.w ?? image?.width ?? 160;
    final srcH = region?.h ?? image?.height ?? 90;
    final height = widget.width * (srcH / srcW);
    if (image == null) {
      return SizedBox(
        width: widget.width,
        height: height,
        child: const ColoredBox(color: Color(0xFF000000)),
      );
    }
    return CustomPaint(
      size: Size(widget.width, height),
      painter: _SpritePainter(image: image, region: region),
    );
  }
}

class _SpritePainter extends CustomPainter {
  _SpritePainter({required this.image, required this.region});

  final ui.Image image;
  final ({int x, int y, int w, int h})? region;

  @override
  void paint(Canvas canvas, Size size) {
    final r = region;
    final src = r != null
        ? Rect.fromLTWH(
            r.x.toDouble(), r.y.toDouble(), r.w.toDouble(), r.h.toDouble())
        : Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(
      image,
      src,
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.image != image || old.region != region;
}
