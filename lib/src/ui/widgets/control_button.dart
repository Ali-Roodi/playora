import 'package:flutter/material.dart';

import '../../theme/player_theme.dart';

/// Round icon control button (44px hit target, hover/press feedback).
class ControlButton extends StatelessWidget {
  const ControlButton({
    super.key,
    required this.theme,
    required this.tooltip,
    this.icon,
    this.child,
    this.onPressed,
    this.active = false,
    this.size,
    this.iconSize,
  }) : assert(icon != null || child != null);

  final PlayoraTheme theme;
  final String tooltip;
  final IconData? icon;

  /// Custom content (e.g. a text label) instead of [icon].
  final Widget? child;
  final VoidCallback? onPressed;

  /// Tinted with the accent color (e.g. captions on).
  final bool active;
  final double? size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final s = size ?? theme.controlSize;
    final disabled = onPressed == null;
    final color = active
        ? theme.accent
        : disabled
            ? theme.text.withValues(alpha: 0.35)
            : theme.text;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 700),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          hoverColor: theme.hover,
          child: SizedBox(
            width: s,
            height: s,
            child: Center(
              child: child ??
                  Icon(icon, color: color, size: iconSize ?? s * 0.55),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill-shaped labelled button (quality "720p", speed "1X").
class LabelButton extends StatelessWidget {
  const LabelButton({
    super.key,
    required this.theme,
    required this.label,
    required this.tooltip,
    this.onPressed,
  });

  final PlayoraTheme theme;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 700),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          hoverColor: theme.hover,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: theme.border),
              color: theme.text.withValues(alpha: 0.06),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: theme.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
