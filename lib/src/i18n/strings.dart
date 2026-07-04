import 'package:flutter/widgets.dart';

import '../models/types.dart';

/// UI strings for the player skin. Use [PlayerStrings.of] for the built-in
/// fa/en tables, or construct your own to override individual labels.
@immutable
class PlayerStrings {
  const PlayerStrings({
    required this.play,
    required this.pause,
    required this.rewind10,
    required this.forward10,
    required this.prevEpisode,
    required this.nextEpisode,
    required this.nextUpTitle,
    required this.mute,
    required this.unmute,
    required this.fullscreenEnter,
    required this.fullscreenExit,
    required this.settings,
    required this.quality,
    required this.qualityTitle,
    required this.qualityAuto,
    required this.speed,
    required this.speedNormal,
    required this.lock,
    required this.unlock,
    required this.playlist,
    required this.resumeTitle,
    required this.resumeMessage,
    required this.resumeCta,
    required this.dismiss,
    required this.skipAd,
    required this.adLabel,
    required this.back,
    required this.loading,
    required this.retry,
    required this.exit,
    required this.captions,
    required this.captionsTitle,
    required this.audioTrack,
    required this.audioTitle,
    required this.off,
  });

  final String play;
  final String pause;
  final String rewind10;
  final String forward10;
  final String prevEpisode;
  final String nextEpisode;

  /// Header of the "up next" card shown near the end of an episode.
  final String nextUpTitle;
  final String mute;
  final String unmute;
  final String fullscreenEnter;
  final String fullscreenExit;
  final String settings;
  final String quality;
  final String qualityTitle;
  final String qualityAuto;
  final String speed;
  final String speedNormal;
  final String lock;
  final String unlock;
  final String playlist;
  final String resumeTitle;
  final String resumeMessage;

  /// Resume button prefix; the minute is appended (e.g. "مشاهده از دقیقه ۳۲").
  final String resumeCta;
  final String dismiss;
  final String skipAd;
  final String adLabel;
  final String back;
  final String loading;
  final String retry;
  final String exit;
  final String captions;
  final String captionsTitle;
  final String audioTrack;
  final String audioTitle;
  final String off;

  static const PlayerStrings fa = PlayerStrings(
    play: 'پخش',
    pause: 'توقف',
    rewind10: '۱۰ ثانیه عقب',
    forward10: '۱۰ ثانیه جلو',
    prevEpisode: 'قسمت قبل',
    nextEpisode: 'قسمت بعد',
    nextUpTitle: 'قسمت بعدی',
    mute: 'بی‌صدا',
    unmute: 'صدا',
    fullscreenEnter: 'تمام‌صفحه',
    fullscreenExit: 'خروج از تمام‌صفحه',
    settings: 'تنظیمات',
    quality: 'کیفیت پخش',
    qualityTitle: 'تنظیمات کیفیت پخش',
    qualityAuto: 'اتوماتیک',
    speed: 'سرعت پخش',
    speedNormal: 'عادی',
    lock: 'قفل کنترل‌ها',
    unlock: 'باز کردن قفل',
    playlist: 'لیست پخش',
    resumeTitle: 'ادامه پخش',
    resumeMessage: 'شما این فیلم/سریال رو از گذشته مشاهده کردی',
    resumeCta: 'مشاهده از دقیقه',
    dismiss: 'بستن',
    skipAd: 'رد کردن آگهی',
    adLabel: 'آگهی',
    back: 'بازگشت',
    loading: 'لطفاً صبر کنید …',
    retry: 'تلاش مجدد',
    exit: 'خروج',
    captions: 'زیرنویس',
    captionsTitle: 'انتخاب زیرنویس',
    audioTrack: 'صدا',
    audioTitle: 'انتخاب زبان صدا',
    off: 'خاموش',
  );

  static const PlayerStrings en = PlayerStrings(
    play: 'Play',
    pause: 'Pause',
    rewind10: 'Rewind 10s',
    forward10: 'Forward 10s',
    prevEpisode: 'Previous episode',
    nextEpisode: 'Next episode',
    nextUpTitle: 'Up next',
    mute: 'Mute',
    unmute: 'Unmute',
    fullscreenEnter: 'Fullscreen',
    fullscreenExit: 'Exit fullscreen',
    settings: 'Settings',
    quality: 'Quality',
    qualityTitle: 'Playback quality',
    qualityAuto: 'Auto',
    speed: 'Speed',
    speedNormal: 'Normal',
    lock: 'Lock controls',
    unlock: 'Unlock',
    playlist: 'Playlist',
    resumeTitle: 'Continue watching',
    resumeMessage: 'You already watched part of this',
    resumeCta: 'Resume from minute',
    dismiss: 'Dismiss',
    skipAd: 'Skip ad',
    adLabel: 'Ad',
    back: 'Back',
    loading: 'Please wait …',
    retry: 'Retry',
    exit: 'Exit',
    captions: 'Subtitles',
    captionsTitle: 'Subtitles',
    audioTrack: 'Audio',
    audioTitle: 'Audio language',
    off: 'Off',
  );

  static PlayerStrings of(PlayerLocale locale) =>
      locale == PlayerLocale.fa ? fa : en;
}

/// Text direction for a locale, honoring an explicit override.
TextDirection dirFor(PlayerLocale locale, TextDirection? override) {
  if (override != null) return override;
  return locale == PlayerLocale.fa ? TextDirection.rtl : TextDirection.ltr;
}

/// Format a number in the locale's digits (fa → Persian digits).
String localeDigits(PlayerLocale locale, int value) {
  final s = '$value';
  if (locale != PlayerLocale.fa) return s;
  const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
  var out = s;
  for (var i = 0; i < western.length; i++) {
    out = out.replaceAll(western[i], persian[i]);
  }
  return out;
}
