import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One `#EXT-X-STREAM-INF` entry of a master playlist: the same content at its
/// own bitrate.
@immutable
class HlsVariant {
  const HlsVariant({
    required this.url,
    required this.bandwidth,
    this.averageBandwidth,
    this.width,
    this.height,
    this.codecs,
    this.attributes = '',
  });

  /// Absolute URL of the media playlist.
  final String url;

  /// Peak bandwidth the manifest advertises, in bits per second.
  final int bandwidth;

  /// Average bandwidth, when the manifest reports one. It is the better number
  /// to plan with — the peak is a worst case.
  final int? averageBandwidth;

  final int? width;
  final int? height;
  final String? codecs;

  /// The raw attribute list, so a rewritten playlist can carry it verbatim.
  final String attributes;

  /// What the governor budgets for this rung.
  int get plannedBitrate => averageBandwidth ?? bandwidth;

  String get label => height != null ? '${height}p' : '${bandwidth ~/ 1000}k';
}

/// One `#EXT-X-MEDIA` entry — an alternate audio or subtitle rendition that
/// lives outside the variant playlists.
@immutable
class HlsRendition {
  const HlsRendition({
    required this.type,
    required this.attributes,
    this.url,
  });

  /// `AUDIO`, `SUBTITLES`, `CLOSED-CAPTIONS`, …
  final String type;

  /// The raw attribute list, with the URI removed.
  final String attributes;

  /// Absolute URL, when the rendition has one.
  final String? url;
}

/// A parsed HLS master playlist.
@immutable
class HlsMaster {
  const HlsMaster({
    required this.url,
    required this.variants,
    this.renditions = const [],
  });

  /// URL the master itself was fetched from.
  final String url;

  /// Variants, ascending by planned bitrate.
  final List<HlsVariant> variants;

  /// Alternate audio/subtitle renditions.
  final List<HlsRendition> renditions;

  /// Whether audio lives outside the variant playlists. Such a variant cannot
  /// be played on its own — it would come up silent.
  bool get hasSeparateAudio =>
      renditions.any((r) => r.type == 'AUDIO' && r.url != null);
}

/// Parses [body] as a master playlist, or returns null when it isn't one — a
/// media playlist, an MP4, an error page, a ladder with a single rung.
HlsMaster? parseHlsMaster(String body, String url) {
  if (!body.contains('#EXTM3U')) return null;
  if (!body.contains('#EXT-X-STREAM-INF')) return null;
  final base = Uri.tryParse(url);
  String resolve(String reference) {
    if (base == null) return reference;
    try {
      return base.resolve(reference).toString();
    } catch (_) {
      return reference;
    }
  }

  final variants = <HlsVariant>[];
  final renditions = <HlsRendition>[];
  final lines = body.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('#EXT-X-MEDIA:')) {
      final raw = line.substring('#EXT-X-MEDIA:'.length);
      final attributes = _parseAttributes(raw);
      final uri = attributes['URI'];
      renditions.add(HlsRendition(
        type: attributes['TYPE'] ?? '',
        attributes: _stripUri(raw),
        url: uri == null ? null : resolve(uri),
      ));
      continue;
    }
    if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
    // The URI is the next line that is neither blank nor a tag.
    String? reference;
    for (var j = i + 1; j < lines.length; j++) {
      final candidate = lines[j].trim();
      if (candidate.isEmpty || candidate.startsWith('#')) continue;
      reference = candidate;
      break;
    }
    if (reference == null) continue;
    final raw = line.substring('#EXT-X-STREAM-INF:'.length);
    final attributes = _parseAttributes(raw);
    final resolution = attributes['RESOLUTION']?.split('x');
    variants.add(HlsVariant(
      url: resolve(reference),
      bandwidth: int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0,
      averageBandwidth: int.tryParse(attributes['AVERAGE-BANDWIDTH'] ?? ''),
      width: resolution == null ? null : int.tryParse(resolution.first),
      height: resolution == null || resolution.length < 2
          ? null
          : int.tryParse(resolution[1]),
      codecs: attributes['CODECS'],
      attributes: raw,
    ));
  }
  if (variants.length < 2) return null;
  variants.sort((a, b) => a.plannedBitrate.compareTo(b.plannedBitrate));
  return HlsMaster(url: url, variants: variants, renditions: renditions);
}

/// Fetches and parses the master playlist at [url].
///
/// Returns null for anything that isn't a usable master — a media playlist, a
/// non-HLS source, a slow or failing request. Callers read that as "open the
/// URL as it came", so a timeout costs the ladder, never the playback.
Future<HlsMaster?> fetchHlsMaster(
  String url, {
  http.Client? client,
  Duration timeout = const Duration(milliseconds: 1500),
}) async {
  final owned = client == null;
  final active = client ?? http.Client();
  try {
    final response =
        await active.get(Uri.parse(url)).timeout(timeout);
    if (response.statusCode != 200) return null;
    return parseHlsMaster(response.body, url);
  } catch (_) {
    return null;
  } finally {
    if (owned) active.close();
  }
}

/// Builds a one-variant master playlist that keeps [master]'s alternate audio
/// and subtitle renditions.
///
/// Handing mpv a bare variant playlist is enough when the variants are muxed,
/// but a stream whose audio lives in its own rendition would come up silent.
/// Every URI is written absolute, so the result can live anywhere on disk.
String buildVariantPlaylist(HlsMaster master, HlsVariant variant) {
  final buffer = StringBuffer()
    ..writeln('#EXTM3U')
    ..writeln('#EXT-X-VERSION:3');
  for (final rendition in master.renditions) {
    buffer.write('#EXT-X-MEDIA:${rendition.attributes}');
    if (rendition.url != null) buffer.write(',URI="${rendition.url}"');
    buffer.writeln();
  }
  buffer
    ..writeln('#EXT-X-STREAM-INF:${variant.attributes}')
    ..writeln(variant.url);
  return buffer.toString();
}

/// `A=1,B="two,three"` → `{A: 1, B: two,three}`.
Map<String, String> _parseAttributes(String raw) {
  final result = <String, String>{};
  for (final item in _splitOutsideQuotes(raw)) {
    final eq = item.indexOf('=');
    if (eq <= 0) continue;
    final key = item.substring(0, eq).trim();
    var value = item.substring(eq + 1).trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    result[key] = value;
  }
  return result;
}

/// Drops the `URI="…"` attribute — it is re-emitted absolute.
String _stripUri(String raw) => [
      for (final part in _splitOutsideQuotes(raw))
        if (!part.trimLeft().toUpperCase().startsWith('URI=')) part,
    ].join(',');

List<String> _splitOutsideQuotes(String raw) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (final rune in raw.runes) {
    final char = String.fromCharCode(rune);
    if (char == '"') quoted = !quoted;
    if (char == ',' && !quoted) {
      parts.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) parts.add(buffer.toString());
  return parts;
}
