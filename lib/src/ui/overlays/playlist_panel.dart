import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../models/types.dart';
import '../../theme/player_theme.dart';

/// Slide-in episode list with poster thumbnails; highlights the current item.
/// When episodes carry a `group` (e.g. a season title), they're rendered
/// under section headers in first-seen order.
class PlaylistPanel extends StatelessWidget {
  const PlaylistPanel({
    super.key,
    required this.theme,
    required this.textDirection,
    required this.strings,
    required this.locale,
    required this.episodes,
    required this.onSelect,
    required this.onClose,
    this.currentId,
  });

  final PlayoraTheme theme;
  final TextDirection textDirection;
  final PlayerStrings strings;
  final PlayerLocale locale;
  final List<Episode> episodes;
  final String? currentId;
  final ValueChanged<String> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final grouped = episodes.any((e) => e.group != null);
    // Preserve first-seen group order.
    final groups = <({String? label, List<Episode> items})>[];
    if (grouped) {
      final index = <String, int>{};
      for (final e in episodes) {
        final key = e.group ?? '';
        final at = index.putIfAbsent(key, () {
          groups.add((label: e.group, items: <Episode>[]));
          return groups.length - 1;
        });
        groups[at].items.add(e);
      }
    } else {
      groups.add((label: null, items: episodes));
    }

    return Positioned.fill(
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.35)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: 300,
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.panel,
                borderRadius: BorderRadius.circular(theme.radius),
                border: Border.all(color: theme.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            strings.playlist,
                            textDirection: textDirection,
                            style: TextStyle(
                              color: theme.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: strings.dismiss,
                          onPressed: onClose,
                          icon: Icon(Icons.close,
                              color: theme.textMuted, size: 20),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: theme.border),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      children: [
                        for (final group in groups) ...[
                          if (group.label != null)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(14, 10, 14, 6),
                              child: Row(
                                textDirection: textDirection,
                                children: [
                                  Expanded(
                                    child: Text(
                                      group.label!,
                                      textDirection: textDirection,
                                      style: TextStyle(
                                        color: theme.accent,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          theme.accent.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      localeDigits(
                                          locale, group.items.length),
                                      style: TextStyle(
                                        color: theme.accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          for (final episode in group.items)
                            _EpisodeTile(
                              theme: theme,
                              textDirection: textDirection,
                              episode: episode,
                              active: episode.id == currentId,
                              onTap: () {
                                onSelect(episode.id);
                                onClose();
                              },
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.theme,
    required this.textDirection,
    required this.episode,
    required this.active,
    required this.onTap,
  });

  final PlayoraTheme theme;
  final TextDirection textDirection;
  final Episode episode;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = episode.subtitle ?? episode.title ?? episode.id;
    final secondary =
        (episode.subtitle != null && episode.title != null) ? episode.title : null;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        hoverColor: theme.hover,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: active ? theme.accent.withValues(alpha: 0.12) : null,
          child: Row(
            textDirection: textDirection,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 84,
                  height: 48,
                  child: episode.poster != null
                      ? Image.network(
                          episode.poster!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: theme.surface),
                        )
                      : ColoredBox(
                          color: theme.surface,
                          child: Icon(Icons.movie_outlined,
                              color: theme.textMuted, size: 20),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: textDirection == TextDirection.rtl
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      textDirection: textDirection,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? theme.accent : theme.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (secondary != null)
                      Text(
                        secondary,
                        textDirection: textDirection,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: theme.textMuted, fontSize: 11.5),
                      ),
                  ],
                ),
              ),
              if (active) ...[
                const SizedBox(width: 6),
                Icon(Icons.equalizer, color: theme.accent, size: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
