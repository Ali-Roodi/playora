import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/controller.dart';
import '../../i18n/strings.dart';
import '../../models/types.dart';
import '../../theme/player_theme.dart';

/// Ad UI drawn over the video while an ad break plays: "Ad" label, mute
/// toggle, skip-after-countdown button, progress bar and click-through.
class AdOverlay extends StatelessWidget {
  const AdOverlay({
    super.key,
    required this.controller,
    required this.theme,
    required this.textDirection,
    required this.strings,
    required this.locale,
    required this.skipAfter,
    required this.onEnd,
    this.skippable = true,
    this.clickThrough,
  });

  final PlayoraController controller;
  final PlayoraTheme theme;
  final TextDirection textDirection;
  final PlayerStrings strings;
  final PlayerLocale locale;
  final Duration skipAfter;

  /// When false, no skip button is rendered — the ad always plays out.
  final bool skippable;
  final String? clickThrough;

  /// Fired on skip (the natural ad end is handled by the orchestrator).
  final VoidCallback onEnd;

  Future<void> _openClickThrough() async {
    final target = clickThrough;
    if (target == null) return;
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Click-through failed to open — non-fatal.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        children: [
          if (clickThrough != null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openClickThrough,
              ),
            ),
          // Top: Ad label + mute.
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.accent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    strings.adLabel,
                    textDirection: textDirection,
                    style: TextStyle(
                      color: theme.accentContrast,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Spacer(),
                ValueListenableBuilder<PlaybackValue>(
                  valueListenable: controller.state,
                  builder: (context, state, _) => IconButton(
                    tooltip: state.muted ? strings.unmute : strings.mute,
                    onPressed: controller.toggleMute,
                    icon: Icon(
                      state.muted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Bottom: skip + progress.
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (skippable)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: AnimatedBuilder(
                      animation: controller.position,
                      builder: (context, _) {
                        final elapsed = controller.position.value;
                        final remaining = skipAfter - elapsed;
                        final canSkip = remaining <= Duration.zero;
                        final seconds = (remaining.inMilliseconds / 1000)
                            .ceil()
                            .clamp(0, 999);
                        return FilledButton(
                          onPressed: canSkip ? onEnd : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: canSkip
                                ? theme.accent
                                : Colors.black.withValues(alpha: 0.6),
                            foregroundColor: canSkip
                                ? theme.accentContrast
                                : Colors.white70,
                            disabledBackgroundColor: Colors.black.withValues(
                              alpha: 0.6,
                            ),
                            disabledForegroundColor: Colors.white70,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          child: Text(
                            canSkip
                                ? strings.skipAd
                                : '${strings.skipAd} · ${localeDigits(locale, seconds)}',
                            textDirection: textDirection,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 10),
                AnimatedBuilder(
                  animation: Listenable.merge([
                    controller.position,
                    controller.duration,
                  ]),
                  builder: (context, _) {
                    final total = controller.duration.value.inMilliseconds;
                    final progress = total <= 0
                        ? 0.0
                        : (controller.position.value.inMilliseconds / total)
                              .clamp(0.0, 1.0);
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 4,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation(theme.accent),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
