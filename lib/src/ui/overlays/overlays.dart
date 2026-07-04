import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../models/types.dart';
import '../../theme/player_theme.dart';

/// Buffering / loading spinner with the "please wait" caption.
class LoadingSpinner extends StatelessWidget {
  const LoadingSpinner({
    super.key,
    required this.theme,
    required this.strings,
    this.scrim = false,
  });

  final PlayoraTheme theme;
  final PlayerStrings strings;

  /// Draw over a dimming layer (host/provider loading above the cover).
  final bool scrim;

  @override
  Widget build(BuildContext context) {
    final spinner = Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(theme.accent),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            strings.loading,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
            ),
          ),
        ],
      ),
    );
    if (!scrim) return IgnorePointer(child: spinner);
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: spinner,
      ),
    );
  }
}

/// Pre-play cover: poster + a single gold play button.
class CoverOverlay extends StatelessWidget {
  const CoverOverlay({
    super.key,
    required this.theme,
    required this.strings,
    required this.onPlay,
    this.poster,
  });

  final PlayoraTheme theme;
  final PlayerStrings strings;
  final VoidCallback onPlay;
  final String? poster;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Semantics(
        button: true,
        label: strings.play,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPlay,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (poster != null)
                Image.network(
                  poster!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Colors.black),
                )
              else
                const ColoredBox(color: Colors.black),
              const ColoredBox(color: Color(0x33000000)),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.accent,
                    boxShadow: const [
                      BoxShadow(color: Color(0x59000000), blurRadius: 24),
                    ],
                  ),
                  child: Icon(Icons.play_arrow,
                      size: 40, color: theme.accentContrast),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Persistent mute badge shown while controls are hidden.
class MuteBadge extends StatelessWidget {
  const MuteBadge({super.key, required this.theme});

  final PlayoraTheme theme;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 10,
      right: 10,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.volume_off, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

/// A transient info pill (top area) — e.g. "ترافیک شما به صورت تمام‌بها حساب
/// می‌شود". Animates in, holds a few seconds, then animates out.
class BadgeOverlay extends StatefulWidget {
  const BadgeOverlay({
    super.key,
    required this.theme,
    required this.textDirection,
    required this.text,
    this.hold = const Duration(seconds: 4),
    this.onDone,
  });

  final PlayoraTheme theme;
  final TextDirection textDirection;
  final String text;
  final Duration hold;
  final VoidCallback? onDone;

  @override
  State<BadgeOverlay> createState() => _BadgeOverlayState();
}

class _BadgeOverlayState extends State<BadgeOverlay> {
  bool _visible = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
    Future.delayed(widget.hold, () {
      if (mounted) setState(() => _visible = false);
    });
    Future.delayed(widget.hold + const Duration(milliseconds: 450), () {
      if (mounted) {
        setState(() => _gone = true);
        widget.onDone?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return const SizedBox.shrink();
    final theme = widget.theme;
    return Positioned(
      top: 12,
      right: 12,
      child: IgnorePointer(
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          offset: _visible ? Offset.zero : const Offset(0, -1.2),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 420),
            opacity: _visible ? 1 : 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.panel,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: theme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, color: theme.accent, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    widget.text,
                    textDirection: widget.textDirection,
                    style: TextStyle(color: theme.text, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Top notice banner (operator/network message). Host-controlled and shown
/// independent of controls auto-hide. Re-appears if a new (different)
/// message is supplied after being dismissed.
class NoticeBanner extends StatefulWidget {
  const NoticeBanner({
    super.key,
    required this.theme,
    required this.textDirection,
    required this.notice,
    required this.strings,
  });

  final PlayoraTheme theme;
  final TextDirection textDirection;
  final PlayerNotice notice;
  final PlayerStrings strings;

  @override
  State<NoticeBanner> createState() => _NoticeBannerState();
}

class _NoticeBannerState extends State<NoticeBanner> {
  bool _dismissed = false;

  @override
  void didUpdateWidget(NoticeBanner old) {
    super.didUpdateWidget(old);
    if (old.notice.message != widget.notice.message) _dismissed = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final theme = widget.theme;
    final dismissible = widget.notice.dismissible;
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(
            color: theme.panel,
            borderRadius: BorderRadius.circular(theme.radius),
            border: Border.all(color: theme.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.notice.message,
                  textDirection: widget.textDirection,
                  style: TextStyle(color: theme.text, fontSize: 13),
                ),
              ),
              if (widget.notice.ctaLabel != null) ...[
                const SizedBox(width: 10),
                TextButton(
                  onPressed: widget.notice.onCta,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.accentContrast,
                    backgroundColor: theme.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 32),
                  ),
                  child: Text(widget.notice.ctaLabel!,
                      style: const TextStyle(fontSize: 12.5)),
                ),
              ],
              if (dismissible) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: widget.strings.dismiss,
                  onPressed: () => setState(() => _dismissed = true),
                  icon: Icon(Icons.close, color: theme.textMuted, size: 18),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-cover blocking overlay — e.g. the viewer's IP/network isn't allowed.
/// Sits above the skin, blocks interaction, and offers retry / exit actions.
class RestrictionOverlay extends StatelessWidget {
  const RestrictionOverlay({
    super.key,
    required this.theme,
    required this.textDirection,
    required this.restriction,
    required this.strings,
  });

  final PlayoraTheme theme;
  final TextDirection textDirection;
  final PlayerRestriction restriction;
  final PlayerStrings strings;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.82),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(22),
            constraints: const BoxConstraints(maxWidth: 380),
            decoration: BoxDecoration(
              color: theme.panel,
              borderRadius: BorderRadius.circular(theme.radius + 4),
              border: Border.all(color: theme.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.accent.withValues(alpha: 0.15),
                  ),
                  child:
                      Icon(Icons.wifi_tethering_off, color: theme.accent, size: 26),
                ),
                const SizedBox(height: 14),
                Text(
                  restriction.title,
                  textDirection: textDirection,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  restriction.message,
                  textDirection: textDirection,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: theme.textMuted, fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (restriction.onRetry != null)
                      FilledButton.icon(
                        onPressed: restriction.onRetry,
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.accent,
                          foregroundColor: theme.accentContrast,
                        ),
                        icon: const Icon(Icons.refresh, size: 18),
                        label:
                            Text(restriction.retryLabel ?? strings.retry),
                      ),
                    if (restriction.onRetry != null &&
                        restriction.onExit != null)
                      const SizedBox(width: 10),
                    if (restriction.onExit != null)
                      OutlinedButton(
                        onPressed: restriction.onExit,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: theme.text,
                          side: BorderSide(color: theme.border),
                        ),
                        child: Text(restriction.exitLabel ?? strings.exit),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
