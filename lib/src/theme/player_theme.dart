import 'package:flutter/widgets.dart';

import '../models/types.dart';

/// Visual tokens of the skin — mirrors the CSS custom properties of the web
/// player (dark, gold accent by default; a light variant via
/// [PlayoraTheme.light]).
@immutable
class PlayoraTheme {
  const PlayoraTheme({
    this.accent = const Color(0xFFE8B84B),
    this.accentContrast = const Color(0xFF1A1A1A),
    this.surface = const Color(0xFF1C1C1E),
    this.scrim = const Color(0x8C000000),
    this.text = const Color(0xFFFFFFFF),
    this.textMuted = const Color(0xFFB8B8BD),
    this.panel = const Color(0xF2141417),
    this.border = const Color(0x1AFFFFFF),
    this.hover = const Color(0x14FFFFFF),
    this.radius = 12,
    this.controlSize = 44,
  });

  /// Light appearance — chrome, panels and text invert; the video stays black.
  const PlayoraTheme.light({
    Color accent = const Color(0xFFE8B84B),
  }) : this(
          accent: accent,
          accentContrast: const Color(0xFF1A1A1A),
          surface: const Color(0xFFF4F4F6),
          scrim: const Color(0x8CFFFFFF),
          text: const Color(0xFF16161A),
          textMuted: const Color(0xFF5B5B66),
          panel: const Color(0xF7F7F7F9),
          border: const Color(0x1F000000),
          hover: const Color(0x0F000000),
        );

  /// Gold accent used for fills, active states and the like button.
  final Color accent;

  /// Foreground drawn on top of [accent].
  final Color accentContrast;

  /// Base surface behind panels.
  final Color surface;

  /// Dimming layer behind modals.
  final Color scrim;
  final Color text;
  final Color textMuted;

  /// Overlay surfaces (panels, modals, cards).
  final Color panel;
  final Color border;
  final Color hover;

  /// Corner radius of cards/panels.
  final double radius;

  /// Hit size of the round control buttons.
  final double controlSize;

  /// Resolve the base theme for an appearance, then apply overrides.
  factory PlayoraTheme.resolve(
    PlayerAppearance appearance, {
    PlayoraTheme? overrides,
  }) {
    if (overrides != null) return overrides;
    return appearance == PlayerAppearance.light
        ? const PlayoraTheme.light()
        : const PlayoraTheme();
  }

  PlayoraTheme copyWith({
    Color? accent,
    Color? accentContrast,
    Color? surface,
    Color? scrim,
    Color? text,
    Color? textMuted,
    Color? panel,
    Color? border,
    Color? hover,
    double? radius,
    double? controlSize,
  }) {
    return PlayoraTheme(
      accent: accent ?? this.accent,
      accentContrast: accentContrast ?? this.accentContrast,
      surface: surface ?? this.surface,
      scrim: scrim ?? this.scrim,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      panel: panel ?? this.panel,
      border: border ?? this.border,
      hover: hover ?? this.hover,
      radius: radius ?? this.radius,
      controlSize: controlSize ?? this.controlSize,
    );
  }
}
