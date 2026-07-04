import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../models/types.dart';
import '../../theme/player_theme.dart';

const Duration nextUpWindow = Duration(seconds: 30);

/// "Up next" card shown in the last [nextUpWindow] of an episode that has a
/// next one: the next episode's cover + a bar that fills toward the end.
/// Ignoring it lets the player auto-advance on completion; tapping jumps now.
///
/// Self-contained so the high-frequency position subscription lives here —
/// only this small card rebuilds each tick, not the whole skin. Mount it with
/// a `key` per episode so the dismissed state resets on episode change.
class NextUpCard extends StatefulWidget {
  const NextUpCard({
    super.key,
    required this.theme,
    required this.textDirection,
    required this.strings,
    required this.episode,
    required this.position,
    required this.duration,
    required this.started,
    this.onNext,
    this.bottomInset = 0,
  });

  final PlayoraTheme theme;
  final TextDirection textDirection;
  final PlayerStrings strings;

  /// The NEXT episode (the one the card advertises).
  final Episode episode;
  final ValueNotifier<Duration> position;
  final ValueNotifier<Duration> duration;
  final bool started;
  final VoidCallback? onNext;

  /// Extra bottom offset so the card sits above the control bar when visible.
  final double bottomInset;

  @override
  State<NextUpCard> createState() => _NextUpCardState();
}

class _NextUpCardState extends State<NextUpCard> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.position, widget.duration]),
      builder: (context, _) {
        final duration = widget.duration.value;
        final remaining = duration - widget.position.value;
        final visible = !_dismissed &&
            widget.started &&
            duration > Duration.zero &&
            remaining <= nextUpWindow &&
            remaining.inMilliseconds > 300;
        if (!visible) return const SizedBox.shrink();

        final progress = ((nextUpWindow - remaining).inMilliseconds /
                nextUpWindow.inMilliseconds)
            .clamp(0.0, 1.0);
        final theme = widget.theme;
        final name = widget.episode.title ?? widget.episode.subtitle;

        return Positioned(
          right: 12,
          bottom: 12 + widget.bottomInset,
          child: Container(
            width: 264,
            decoration: BoxDecoration(
              color: theme.panel,
              borderRadius: BorderRadius.circular(theme.radius),
              border: Border.all(color: theme.border),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 18),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: widget.onNext,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: SizedBox(
                              width: 96,
                              height: 54,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (widget.episode.poster != null)
                                    Image.network(
                                      widget.episode.poster!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          ColoredBox(color: theme.surface),
                                    )
                                  else
                                    ColoredBox(color: theme.surface),
                                  Center(
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: theme.accent,
                                      ),
                                      child: Icon(
                                        Icons.play_arrow,
                                        size: 18,
                                        color: theme.accentContrast,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  widget.textDirection == TextDirection.rtl
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.strings.nextUpTitle,
                                  textDirection: widget.textDirection,
                                  style: TextStyle(
                                    color: theme.textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (name != null)
                                  Text(
                                    name,
                                    textDirection: widget.textDirection,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: theme.text,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                const SizedBox(height: 7),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: SizedBox(
                                    height: 3,
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      backgroundColor:
                                          theme.text.withValues(alpha: 0.15),
                                      valueColor: AlwaysStoppedAnimation(
                                          theme.accent),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    tooltip: widget.strings.dismiss,
                    onPressed: () => setState(() => _dismissed = true),
                    icon:
                        Icon(Icons.close, color: theme.textMuted, size: 16),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
