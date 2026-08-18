import 'dart:io' show Directory, File, Platform;

import 'package:path_provider/path_provider.dart';

import 'buffering.dart';

/// Resolves (and verifies) the directory the disk-backed cache may use.
///
/// Returns null when there is no writable temp directory — the caller then
/// falls back to an in-memory cache with the smaller byte cap. mpv fails
/// silently on an unwritable `cache-dir` and quietly keeps the whole cache in
/// RAM, so writability is proven here before the big cap is applied.
Future<String?> resolveCacheDirectory(PlayoraBufferConfig config) async {
  if (!config.cacheOnDisk) return null;
  try {
    final base = config.cacheDirectory ??
        '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}'
            'playora_cache';
    final dir = Directory(base);
    if (!await dir.exists()) await dir.create(recursive: true);
    final probe = File('${dir.path}${Platform.pathSeparator}.playora_probe');
    await probe.writeAsString('1', flush: true);
    await probe.delete();
    return dir.path;
  } catch (_) {
    return null;
  }
}
