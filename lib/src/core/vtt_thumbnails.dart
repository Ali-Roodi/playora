import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One scrub-preview cue from a WebVTT thumbnails track: a time range mapped
/// to an image URL, optionally cropped to a sprite region (`#xywh=`).
@immutable
class ThumbnailCue {
  const ThumbnailCue({
    required this.start,
    required this.end,
    required this.imageUrl,
    this.region,
  });

  final Duration start;
  final Duration end;

  /// Absolute image URL (resolved against the VTT's own URL).
  final String imageUrl;

  /// Sprite crop (x, y, w, h) from a `#xywh=` media fragment, if present.
  final ({int x, int y, int w, int h})? region;
}

/// Parsed WebVTT thumbnails track for scrub previews.
@immutable
class ThumbnailTrack {
  const ThumbnailTrack(this.cues);

  final List<ThumbnailCue> cues;

  bool get isEmpty => cues.isEmpty;

  /// The cue covering [position], or the nearest earlier one.
  ThumbnailCue? cueAt(Duration position) {
    ThumbnailCue? best;
    for (final cue in cues) {
      if (cue.start <= position) {
        best = cue;
        if (position < cue.end) return cue;
      } else {
        break;
      }
    }
    return best;
  }

  /// Fetch and parse a thumbnails VTT from [url].
  static Future<ThumbnailTrack> fetch(String url, {http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final res = await c.get(Uri.parse(url));
      if (res.statusCode != 200) return const ThumbnailTrack([]);
      return parse(res.body, baseUrl: url);
    } catch (_) {
      return const ThumbnailTrack([]);
    } finally {
      if (client == null) c.close();
    }
  }

  /// Parse WebVTT [content]. Relative image URLs resolve against [baseUrl].
  static ThumbnailTrack parse(String content, {String? baseUrl}) {
    final cues = <ThumbnailCue>[];
    final lines = content.replaceAll('\r\n', '\n').split('\n');
    final base = baseUrl != null ? Uri.tryParse(baseUrl) : null;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.contains('-->')) continue;
      final parts = line.split('-->');
      if (parts.length != 2) continue;
      final start = _parseTimestamp(parts[0].trim());
      // Cue timing can carry settings after the end timestamp.
      final end = _parseTimestamp(parts[1].trim().split(RegExp(r'\s+')).first);
      if (start == null || end == null) continue;

      // The payload is the next non-empty line.
      String? payload;
      if (i + 1 < lines.length) {
        final candidate = lines[i + 1].trim();
        if (candidate.isNotEmpty) {
          payload = candidate;
          i++;
        }
      }
      if (payload == null) continue;

      ({int x, int y, int w, int h})? region;
      var target = payload;
      final hash = payload.indexOf('#');
      if (hash >= 0) {
        final fragment = payload.substring(hash + 1);
        target = payload.substring(0, hash);
        final match = RegExp(r'xywh=(\d+),(\d+),(\d+),(\d+)').firstMatch(fragment);
        if (match != null) {
          region = (
            x: int.parse(match.group(1)!),
            y: int.parse(match.group(2)!),
            w: int.parse(match.group(3)!),
            h: int.parse(match.group(4)!),
          );
        }
      }

      var imageUrl = target;
      if (base != null) {
        imageUrl = base.resolve(target).toString();
      }
      cues.add(ThumbnailCue(
        start: start,
        end: end,
        imageUrl: imageUrl,
        region: region,
      ));
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    return ThumbnailTrack(cues);
  }

  /// `HH:MM:SS.mmm`, `MM:SS.mmm` or `SS.mmm`.
  static Duration? _parseTimestamp(String raw) {
    final match =
        RegExp(r'^(?:(\d+):)?(\d{1,2}):(\d{2})(?:[.,](\d{1,3}))?$').firstMatch(raw) ??
            RegExp(r'^(\d+)(?:[.,](\d{1,3}))?$').firstMatch(raw);
    if (match == null) return null;
    if (match.groupCount == 2) {
      final seconds = int.parse(match.group(1)!);
      final ms = int.parse((match.group(2) ?? '0').padRight(3, '0'));
      return Duration(seconds: seconds, milliseconds: ms);
    }
    final hours = match.group(1) != null ? int.parse(match.group(1)!) : 0;
    final minutes = int.parse(match.group(2)!);
    final seconds = int.parse(match.group(3)!);
    final ms = int.parse((match.group(4) ?? '0').padRight(3, '0'));
    return Duration(
        hours: hours, minutes: minutes, seconds: seconds, milliseconds: ms);
  }
}
