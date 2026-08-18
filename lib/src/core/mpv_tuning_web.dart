import 'package:media_kit/media_kit.dart' as mk;

/// Web plays through `<video>`/hls.js — there is no mpv to tune.
const bool mpvTuningSupported = false;

Future<void> setMpvProperties(
  mk.Player player,
  Map<String, String> properties,
) async {}

Future<String?> getMpvProperty(mk.Player player, String name) async => null;
