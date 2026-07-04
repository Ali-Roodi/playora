import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/player_theme.dart';

/// One row of a radio list inside a [PlayerModal].
class RadioOptionData {
  const RadioOptionData({
    required this.label,
    required this.selected,
    required this.onSelect,
    this.hint,
  });

  final String label;

  /// Secondary hint on the trailing side (e.g. the resolution ABR is playing
  /// while on Auto).
  final String? hint;
  final bool selected;
  final VoidCallback onSelect;
}

/// Centered frosted modal with an icon + title header and a radio list — the
/// quality / speed / captions / audio pickers. Tapping the scrim closes it.
class PlayerModal extends StatelessWidget {
  const PlayerModal({
    super.key,
    required this.theme,
    required this.textDirection,
    required this.icon,
    required this.title,
    required this.dismissLabel,
    required this.options,
    required this.onClose,
  });

  final PlayoraTheme theme;
  final TextDirection textDirection;
  final IconData icon;
  final String title;
  final String dismissLabel;
  final List<RadioOptionData> options;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: ColoredBox(
          color: theme.scrim,
          child: Center(
            child: GestureDetector(
              onTap: () {}, // absorb taps inside the panel
              child: ClipRRect(
                borderRadius: BorderRadius.circular(theme.radius + 4),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    width: 320,
                    constraints: const BoxConstraints(maxHeight: 340),
                    decoration: BoxDecoration(
                      color: theme.panel,
                      borderRadius: BorderRadius.circular(theme.radius + 4),
                      border: Border.all(color: theme.border),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                          child: Row(
                            children: [
                              Icon(icon, color: theme.accent, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  title,
                                  textDirection: textDirection,
                                  style: TextStyle(
                                    color: theme.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: dismissLabel,
                                onPressed: onClose,
                                icon: Icon(Icons.close,
                                    color: theme.textMuted, size: 20),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, color: theme.border),
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            children: [
                              for (final option in options)
                                _RadioRow(
                                  theme: theme,
                                  textDirection: textDirection,
                                  data: option,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.theme,
    required this.textDirection,
    required this.data,
  });

  final PlayoraTheme theme;
  final TextDirection textDirection;
  final RadioOptionData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: data.onSelect,
        hoverColor: theme.hover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: data.selected ? theme.accent : theme.textMuted,
                    width: 2,
                  ),
                ),
                child: data.selected
                    ? Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.accent,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  data.label,
                  textDirection: textDirection,
                  style: TextStyle(
                    color: data.selected ? theme.accent : theme.text,
                    fontSize: 14,
                    fontWeight:
                        data.selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (data.hint != null)
                Text(
                  data.hint!,
                  style: TextStyle(color: theme.textMuted, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
