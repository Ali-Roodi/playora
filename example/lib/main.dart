import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:playora/playora.dart';

// "Sprite Fight" — a free animated short. All assets (HLS, poster,
// thumbnails, subtitles) are the public Vidstack sample files.
const _stream = 'https://files.vidstack.io/sprite-fight/hls/stream.m3u8';
const _poster = 'https://files.vidstack.io/sprite-fight/poster.webp';
const _thumbnails = 'https://files.vidstack.io/sprite-fight/thumbnails.vtt';
const _adSrc = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

const _subtitles = [
  ExternalSubtitle(
    src: 'https://files.vidstack.io/sprite-fight/subs/english.vtt',
    label: 'English',
    language: 'en',
  ),
  ExternalSubtitle(
    src: 'https://files.vidstack.io/sprite-fight/subs/spanish.vtt',
    label: 'Español',
    language: 'es',
  ),
];

List<Episode> _episodesFor(PlayerLocale locale) {
  final fa = locale == PlayerLocale.fa;
  String season(int n) => fa ? 'فصل ${n == 1 ? 'اول' : 'دوم'}' : 'Season $n';
  String episode(int n) =>
      fa ? 'قسمت ${const ['اول', 'دوم', 'سوم'][n - 1]}' : 'Episode $n';
  final title = fa ? 'سریال نمونه' : 'Sample Series';
  return [
    Episode(
      id: 'e1',
      src: _stream,
      poster: 'https://picsum.photos/seed/lp1/1280/720',
      title: title,
      subtitle: episode(1),
      group: season(1),
      thumbnails: _thumbnails,
    ),
    Episode(
      id: 'e2',
      src: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      poster: 'https://picsum.photos/seed/lp2/1280/720',
      title: title,
      subtitle: episode(2),
      group: season(1),
    ),
    Episode(
      id: 'e3',
      src:
          'https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8',
      poster: 'https://picsum.photos/seed/lp3/1280/720',
      title: title,
      subtitle: episode(3),
      group: season(2),
    ),
  ];
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Playora',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE8B84B),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF101014),
      ),
      home: const PlaygroundPage(),
    );
  }
}

class PlaygroundPage extends StatefulWidget {
  const PlaygroundPage({super.key});

  @override
  State<PlaygroundPage> createState() => _PlaygroundPageState();
}

class _PlaygroundPageState extends State<PlaygroundPage> {
  PlayerLocale _locale = PlayerLocale.fa;
  PlayerAppearance _appearance = PlayerAppearance.dark;
  bool _playlist = true;
  bool _withAd = false;
  bool _withBadge = false;
  bool _withNotice = false;
  bool _withRestriction = false;
  bool _withBack = false;
  bool _persist = true;
  bool _liked = false;
  String _currentEpisode = 'e1';
  int _playerKey = 0;

  bool get _fa => _locale == PlayerLocale.fa;

  String _t(String fa, String en) => _fa ? fa : en;

  void _rebuildPlayer(VoidCallback change) {
    setState(() {
      change();
      _playerKey++; // re-mount so structural options apply cleanly
    });
  }

  @override
  Widget build(BuildContext context) {
    final episodes = _playlist ? _episodesFor(_locale) : null;

    final player = PlayoraPlayer(
      key: ValueKey(_playerKey),
      src: _stream,
      poster: _poster,
      thumbnails: _thumbnails,
      subtitles: _subtitles,
      title: _t('نبرد اسپرایت‌ها', 'Sprite Fight'),
      locale: _locale,
      appearance: _appearance,
      episodes: episodes,
      currentEpisodeId: _playlist ? _currentEpisode : null,
      onEpisodeChange: (id) => setState(() => _currentEpisode = id),
      ad: _withAd ? const AdConfig(src: _adSrc) : null,
      badge: _withBadge
          ? _t('ترافیک شما به صورت تمام‌بها محاسبه می‌شود', 'Full-price traffic')
          : null,
      notice: _withNotice
          ? PlayerNotice(
              message: _t(
                'پخش رایگان فقط در شبکه اپراتور X',
                'Free playback only on operator X',
              ),
              ctaLabel: _t('بیشتر', 'More'),
              onCta: () {},
            )
          : null,
      restriction: _withRestriction
          ? PlayerRestriction(
              title: _t('شبکه نامعتبر', 'Network not allowed'),
              message: _t(
                'پخش فقط در شبکه اپراتورهای X و Y امکان‌پذیر است.',
                'Playback only works on operator X or Y\'s network.',
              ),
              onRetry: () => setState(() => _withRestriction = false),
              onExit: () => setState(() => _withRestriction = false),
            )
          : null,
      onBack: _withBack ? () {} : null,
      persistSettings: _persist,
      onLike: (liked) => setState(() => _liked = liked),
      liked: _liked,
      onWatchInterval: (info) async {
        debugPrint(
          'watch-interval: play=${info.playDuration}s '
          'pos=${info.position.toStringAsFixed(1)}s q=${info.quality}',
        );
        return null;
      },
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(fa: _fa),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: player,
                  ),
                  const SizedBox(height: 18),
                  _ControlsCard(
                    fa: _fa,
                    children: [
                      _seg<PlayerLocale>(
                        label: _t('زبان', 'Language'),
                        value: _locale,
                        items: {
                          PlayerLocale.fa: 'فارسی',
                          PlayerLocale.en: 'English',
                        },
                        onChanged: (v) => _rebuildPlayer(() => _locale = v),
                      ),
                      _seg<PlayerAppearance>(
                        label: _t('پوسته', 'Appearance'),
                        value: _appearance,
                        items: {
                          PlayerAppearance.dark: _t('تیره', 'Dark'),
                          PlayerAppearance.light: _t('روشن', 'Light'),
                        },
                        onChanged: (v) => _rebuildPlayer(() => _appearance = v),
                      ),
                      _toggle(_t('لیست پخش و فصل‌ها', 'Playlist & seasons'),
                          _playlist, (v) => _rebuildPlayer(() => _playlist = v)),
                      _toggle(_t('تبلیغ پیش از پخش', 'Pre-roll ad'), _withAd,
                          (v) => _rebuildPlayer(() => _withAd = v)),
                      _toggle(_t('بج اطلاع‌رسانی', 'Info badge'), _withBadge,
                          (v) => _rebuildPlayer(() => _withBadge = v)),
                      _toggle(_t('اعلان اپراتور', 'Operator notice'),
                          _withNotice, (v) => setState(() => _withNotice = v)),
                      _toggle(
                          _t('محدودیت شبکه', 'Network restriction'),
                          _withRestriction,
                          (v) => setState(() => _withRestriction = v)),
                      _toggle(_t('دکمه بازگشت', 'Back button'), _withBack,
                          (v) => _rebuildPlayer(() => _withBack = v)),
                      _toggle(_t('ذخیره تنظیمات', 'Persist settings'), _persist,
                          (v) => _rebuildPlayer(() => _persist = v)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _FeatureList(fa: _fa),
                  const SizedBox(height: 28),
                  Text(
                    'playora · MIT · github.com/Ali-Roodi/playora',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return _ControlChip(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFFE8B84B),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _seg<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    return _ControlChip(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: Colors.white.withValues(alpha: 0.7))),
          const SizedBox(width: 10),
          SegmentedButton<T>(
            segments: [
              for (final entry in items.entries)
                ButtonSegment(
                  value: entry.key,
                  label:
                      Text(entry.value, style: const TextStyle(fontSize: 12)),
                ),
            ],
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              side: WidgetStatePropertyAll(
                BorderSide(color: Colors.white.withValues(alpha: 0.15)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.fa});

  final bool fa;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFE8B84B),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Color(0xFF1A1A1A), size: 26),
            ),
            const SizedBox(width: 12),
            const Text(
              'Playora',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          fa
              ? 'ویدیو پلیر اختصاصی فلاتر — HLS/MP4، اسکین سفارشی راست‌چین، کیفیت/سرعت/زیرنویس/صدا، تبلیغات، ژست‌های لمسی و آنالیتیکس اختیاری'
              : 'A production-grade Flutter video player — HLS/MP4, custom RTL-aware skin, quality/speed/subtitle/audio menus, ads, touch gestures and optional analytics',
          textAlign: TextAlign.center,
          textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13.5,
            height: 1.7,
          ),
        ),
      ],
    );
  }
}

class _ControlsCard extends StatelessWidget {
  const _ControlsCard({required this.fa, required this.children});

  final bool fa;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Directionality(
        textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: children,
        ),
      ),
    );
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

class _FeatureList extends StatelessWidget {
  const _FeatureList({required this.fa});

  final bool fa;

  @override
  Widget build(BuildContext context) {
    final features = fa
        ? const [
            ('پخش HLS و MP4', 'کیفیت تطبیقی + منوی دستی کیفیت با رندیشن‌های MP4'),
            ('ژست‌های لمسی', 'دبل‌تپ ±۱۰ ثانیه، لانگ‌پرس ۲×، سوایپ روشنایی/صدا'),
            ('لیست پخش و فصل‌ها', 'سرتیتر فصل، قبلی/بعدی، پخش خودکار و کارت قسمت بعد'),
            ('تبلیغات', 'پیش/میان/پس از پخش با شمارنده رد کردن و کلیک‌ثرو'),
            ('زیرنویس و صدا', 'ترک‌های داخلی HLS + فایل‌های خارجی WebVTT/SRT'),
            ('آنالیتیکس اختیاری', 'رویدادهای استاندارد، هارت‌بیت و «ادامه پخش»'),
          ]
        : const [
            ('HLS & MP4', 'Adaptive quality + manual menu with MP4 renditions'),
            (
              'Touch gestures',
              'Double-tap ±10s, long-press 2×, brightness/volume swipe'
            ),
            (
              'Playlist & seasons',
              'Season headers, prev/next, auto-advance, up-next card'
            ),
            ('Ads', 'Pre/mid/post-roll with skip countdown and click-through'),
            (
              'Subtitles & audio',
              'Embedded HLS tracks + external WebVTT/SRT files'
            ),
            (
              'Optional analytics',
              'Canonical events, heartbeat, continue-watching'
            ),
          ];

    return Directionality(
      textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final feature in features)
            Container(
              width: 300,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    feature.$1,
                    style: const TextStyle(
                      color: Color(0xFFE8B84B),
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    feature.$2,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 12.5,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
