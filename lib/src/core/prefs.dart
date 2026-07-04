import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Viewer preferences persisted across sessions when `persistSettings` is on.
@immutable
class PlayerPrefs {
  const PlayerPrefs({this.volume, this.muted, this.rate, this.brightness});

  final double? volume;
  final bool? muted;
  final double? rate;
  final double? brightness;

  PlayerPrefs merge(PlayerPrefs patch) => PlayerPrefs(
        volume: patch.volume ?? volume,
        muted: patch.muted ?? muted,
        rate: patch.rate ?? rate,
        brightness: patch.brightness ?? brightness,
      );

  Map<String, Object?> toJson() => {
        if (volume != null) 'volume': volume,
        if (muted != null) 'muted': muted,
        if (rate != null) 'rate': rate,
        if (brightness != null) 'brightness': brightness,
      };

  factory PlayerPrefs.fromJson(Map<String, dynamic> json) => PlayerPrefs(
        volume: (json['volume'] as num?)?.toDouble(),
        muted: json['muted'] as bool?,
        rate: (json['rate'] as num?)?.toDouble(),
        brightness: (json['brightness'] as num?)?.toDouble(),
      );
}

const String defaultPrefsKey = 'playora';

/// Loads/saves [PlayerPrefs] as a single JSON blob under [key]. Distinct keys
/// scope preferences (e.g. per app or per profile).
class PlayerPrefsStore {
  PlayerPrefsStore([this.key = defaultPrefsKey]);

  final String key;

  Future<PlayerPrefs> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return const PlayerPrefs();
      return PlayerPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const PlayerPrefs();
    }
  }

  Future<void> save(PlayerPrefs patch) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final merged = (await load()).merge(patch);
      await prefs.setString(key, jsonEncode(merged.toJson()));
    } catch (_) {
      // Storage unavailable — ignore.
    }
  }
}
