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
