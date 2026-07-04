import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/types.dart';

/// VOD provider resolution. Some operators don't serve a playable HLS URL
/// directly — they hand out an opaque play token that must be exchanged, via
/// the provider's API, for the real stream URL (plus scrub-thumbnail VTTs).
/// For [VodProvider.standard] the `src` is already playable and passes
/// through untouched.
///
/// Mirrors the hamrah-player provider flow so existing back-ends keep working.

const String poyanDefaultUrl = 'https://vodcore.iranlms.ir/client/';
const String abrHamrahiDefaultUrl =
    'https://hamrahi.cloud/live/api/v1/live/details/vod/{token}';

/// Result of exchanging a play token with a provider.
@immutable
class ResolvedVodSource {
  const ResolvedVodSource({required this.src, this.thumbnails});

  /// Resolved playable URL.
  final String src;

  /// Resolved scrub-thumbnail VTT, if the provider supplied one.
  final String? thumbnails;
}

/// Thrown when a provider exchange fails (bad token, network, bad payload).
class VodResolutionException implements Exception {
  VodResolutionException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'VodResolutionException: $message';
}

bool _isMobile() {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isIOS;
}

/// Exchange a provider `src` (an opaque play token) for a playable HLS URL
/// (+ VTT thumbnails). [VodProvider.standard] passes through unchanged.
/// [customUrl] overrides the provider endpoint; `{token}` is substituted
/// where the endpoint supports it.
Future<ResolvedVodSource> resolveVodSource(
  String src,
  VodProvider provider, {
  Map<VodProvider, String>? customUrl,
  http.Client? client,
  bool? mobile,
}) async {
  switch (provider) {
    case VodProvider.standard:
      return ResolvedVodSource(src: src);
    case VodProvider.poyan:
      return _resolvePoyan(src, customUrl?[provider], client);
    case VodProvider.abrHamrahi:
      return _resolveAbrHamrahi(
        src,
        customUrl?[provider],
        client,
        mobile ?? _isMobile(),
      );
  }
}

Future<ResolvedVodSource> _resolvePoyan(
  String token,
  String? serviceUrl,
  http.Client? client,
) async {
  final decoded = Uri.decodeComponent(token);
  if (decoded.isEmpty) throw VodResolutionException('tokenIsEmpty');
  final c = client ?? http.Client();
  try {
    final res = await c.post(
      Uri.parse(serviceUrl ?? poyanDefaultUrl),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'api_version': '1',
        'method': 'getPlayContentInfo',
        'data': {'play_token': decoded},
      }),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final playData =
        (body['data'] as Map<String, dynamic>?)?['play_data'] as Map<String, dynamic>?;
    final playUrl = playData?['play_url'] as String?;
    if (playUrl == null || playUrl.isEmpty) {
      throw VodResolutionException('poyan: missing play_url');
    }
    final thumbnails = (playData?['thumbnails'] as List<dynamic>?)
        ?.whereType<Map<String, dynamic>>()
        .map((t) => t['url'] as String?)
        .whereType<String>()
        .firstOrNull;
    return ResolvedVodSource(src: playUrl, thumbnails: thumbnails);
  } on VodResolutionException {
    rethrow;
  } catch (e) {
    throw VodResolutionException('poyan resolution failed', e);
  } finally {
    if (client == null) c.close();
  }
}

Future<ResolvedVodSource> _resolveAbrHamrahi(
  String token,
  String? serviceUrl,
  http.Client? client,
  bool mobile,
) async {
  if (token.isEmpty) throw VodResolutionException('tokenIsEmpty');
  final url =
      (serviceUrl ?? abrHamrahiDefaultUrl).replaceAll('{token}', token);
  final c = client ?? http.Client();
  try {
    final res = await c.get(Uri.parse(url));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final streamLink = body['stream_link'] as String?;
    if (streamLink == null || streamLink.isEmpty) {
      throw VodResolutionException('abr_hamrahi: missing stream_link');
    }
    final vtt = body['vtt'] as String?;
    final vttMobile = body['vtt_mobile'] as String?;
    final thumbnails =
        (mobile ? vttMobile : vtt) ?? vtt ?? vttMobile;
    return ResolvedVodSource(src: streamLink, thumbnails: thumbnails);
  } on VodResolutionException {
    rethrow;
  } catch (e) {
    throw VodResolutionException('abr_hamrahi resolution failed', e);
  } finally {
    if (client == null) c.close();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
