import 'buffering.dart';

/// The web backend has no mpv cache to place on disk.
Future<String?> resolveCacheDirectory(PlayoraBufferConfig config) async => null;

Future<String?> writeCacheFile(
  String directory,
  String name,
  String contents,
) async =>
    null;
