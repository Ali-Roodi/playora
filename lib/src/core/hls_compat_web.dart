import 'dart:js_interop';
import 'dart:js_interop_unsafe';

bool _patched = false;

/// The `Hls` class assigned by hls.js once media_kit injects its script.
JSObject? _hlsClass;

const _kInstanceKey = '__playora_hls_instance';

JSObject? get _hlsInstance =>
    globalContext.getProperty(_kInstanceKey.toJS) as JSObject?;

/// Makes media_kit's web backend usable with HLS on modern Chromium.
///
/// Two problems are fixed here, both by intervening before the first
/// `Player.open()`:
///
/// 1. Recent Chrome/Edge answer `'maybe'` to
///    `canPlayType('application/vnd.apple.mpegurl')` but then fail the actual
///    playback with MEDIA_ERR_SRC_NOT_SUPPORTED. media_kit trusts that answer
///    and assigns the .m3u8 URL directly to the `<video>` element instead of
///    attaching hls.js, so HLS never plays. `canPlayType` is overridden to
///    answer `''` for HLS mime types (Safari excluded — its native HLS is
///    real), which routes media_kit back onto the hls.js path.
///
/// 2. media_kit keeps its hls.js instance in a local variable, so quality
///    levels are unreachable ([Player.setVideoTrack] throws on web and the
///    track streams stay empty). `window.Hls` is intercepted so that when
///    media_kit's injected script assigns it, `attachMedia` is wrapped to
///    record the live instance — [webHlsLevels] / [setWebHlsLevel] then talk
///    to hls.js directly.
void ensureWebHlsPlayable() {
  if (_patched) return;
  _patched = true;

  final navigator = globalContext.getProperty('navigator'.toJS) as JSObject?;
  final ua =
      ((navigator?.getProperty('userAgent'.toJS) as JSString?)?.toDart ?? '')
          .toLowerCase();
  final isSafari = ua.contains('safari') &&
      !ua.contains('chrome') &&
      !ua.contains('chromium') &&
      !ua.contains('edg') &&
      !ua.contains('android');

  if (!isSafari) _patchCanPlayType();
  _interceptHlsGlobal();
}

void _patchCanPlayType() {
  final mediaElement =
      globalContext.getProperty('HTMLMediaElement'.toJS) as JSObject?;
  final proto = mediaElement?.getProperty('prototype'.toJS) as JSObject?;
  final original = proto?.getProperty('canPlayType'.toJS) as JSFunction?;
  if (proto == null || original == null) return;

  // Non-HLS queries are answered by invoking the original on a probe element
  // (the result doesn't depend on the receiving instance).
  final document = globalContext.getProperty('document'.toJS) as JSObject;
  final probe = document.callMethod('createElement'.toJS, 'video'.toJS);

  proto.setProperty(
    'canPlayType'.toJS,
    ((JSString type) {
      if (type.toDart.toLowerCase().contains('mpegurl')) return ''.toJS;
      return original.callAsFunction(probe, type);
    }).toJS,
  );
}

void _interceptHlsGlobal() {
  // Already loaded (another player instance ran first)? Patch in place.
  final existing = globalContext.getProperty('Hls'.toJS) as JSObject?;
  if (existing != null) {
    _hlsClass = existing;
    _wrapAttachMedia(existing);
    return;
  }

  final objectClass = globalContext.getProperty('Object'.toJS) as JSObject;
  final descriptor = JSObject()
    ..setProperty('configurable'.toJS, true.toJS)
    ..setProperty(
      'get'.toJS,
      (() => _hlsClass).toJS,
    )
    ..setProperty(
      'set'.toJS,
      ((JSAny? value) {
        _hlsClass = value as JSObject?;
        if (_hlsClass != null) _wrapAttachMedia(_hlsClass!);
      }).toJS,
    );
  objectClass.callMethod(
      'defineProperty'.toJS, globalContext, 'Hls'.toJS, descriptor);
}

void _wrapAttachMedia(JSObject hlsClass) {
  final proto = hlsClass.getProperty('prototype'.toJS) as JSObject?;
  final original = proto?.getProperty('attachMedia'.toJS) as JSFunction?;
  if (proto == null || original == null) return;
  proto.setProperty(
    'attachMedia'.toJS,
    ((JSAny thisArg, JSAny? element) {
      globalContext.setProperty(_kInstanceKey.toJS, thisArg);
      return original.callAsFunction(thisArg, element);
    }).toJSCaptureThis,
  );
}

/// Quality levels of the live hls.js instance (empty off-web / pre-attach).
List<({int index, int? height})> webHlsLevels() {
  final hls = _hlsInstance;
  final levels = hls?.getProperty('levels'.toJS) as JSArray?;
  if (levels == null) return const [];
  final length = (levels.getProperty('length'.toJS) as JSNumber).toDartInt;
  return [
    for (var i = 0; i < length; i++)
      (index: i, height: _levelHeight(levels, i)),
  ];
}

int? _levelHeight(JSArray levels, int i) {
  final height =
      (levels.getProperty(i.toJS) as JSObject?)?.getProperty('height'.toJS);
  return height.isA<JSNumber>() ? (height as JSNumber).toDartInt : null;
}

/// Index of the level currently being played, or -1 when unknown.
int webHlsCurrentLevel() {
  final level = _hlsInstance?.getProperty('currentLevel'.toJS);
  return level.isA<JSNumber>() ? (level as JSNumber).toDartInt : -1;
}

/// Whether hls.js is choosing the level adaptively.
bool webHlsAutoEnabled() {
  final auto = _hlsInstance?.getProperty('autoLevelEnabled'.toJS);
  return auto.isA<JSBoolean>() ? (auto as JSBoolean).toDart : true;
}

/// Locks playback to [index], or re-enables adaptive selection with -1.
void setWebHlsLevel(int index) {
  _hlsInstance?.setProperty('currentLevel'.toJS, index.toJS);
}
