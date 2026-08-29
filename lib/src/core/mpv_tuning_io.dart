import 'package:media_kit/media_kit.dart' as mk;

/// Whether low-level mpv properties can be tuned on this platform.
const bool mpvTuningSupported = true;

/// Applies mpv properties one by one, ignoring the ones an older libmpv
/// build doesn't know — an unsupported knob must never break playback.
Future<void> setMpvProperties(
  mk.Player player,
  Map<String, String> properties,
) async {
  final platform = player.platform;
  if (platform is! mk.NativePlayer) return;
  for (final entry in properties.entries) {
    try {
      await platform.setProperty(entry.key, entry.value);
    } catch (_) {
      // Unknown/read-only property on this libmpv — skip it.
    }
  }
}

/// Merges [entries] into an mpv key/value list option (`demuxer-lavf-o` and
/// friends) instead of assigning it.
///
/// media_kit sets `demuxer-lavf-o` itself — the protocol whitelist lives
/// there — so a plain assignment would silently drop what the backend needs.
Future<void> mergeMpvListProperty(
  mk.Player player,
  String name,
  Map<String, String> entries,
) async {
  if (entries.isEmpty) return;
  final merged = <String, String>{};
  final current = await getMpvProperty(player, name);
  if (current != null) {
    for (final item in _splitListValue(current)) {
      final eq = item.indexOf('=');
      if (eq <= 0) continue;
      merged[item.substring(0, eq)] = item.substring(eq + 1);
    }
  }
  merged.addAll(entries);
  await setMpvProperties(player, {
    name: [for (final e in merged.entries) '${e.key}=${e.value}'].join(','),
  });
}

/// Splits `a=1,b=[x,y]` on the separators that are not inside brackets — the
/// protocol whitelist is written as a bracketed list, commas and all.
List<String> _splitListValue(String value) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var depth = 0;
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (char == '[') depth++;
    if (char == ']') depth--;
    if (char == ',' && depth <= 0) {
      parts.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) parts.add(buffer.toString());
  return [for (final part in parts) part.trim()];
}

/// Reads an mpv property, or null when unavailable.
Future<String?> getMpvProperty(mk.Player player, String name) async {
  final platform = player.platform;
  if (platform is! mk.NativePlayer) return null;
  try {
    final value = await platform.getProperty(name);
    return value.isEmpty ? null : value;
  } catch (_) {
    return null;
  }
}
