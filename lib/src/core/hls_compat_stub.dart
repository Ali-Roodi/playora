/// No-op on non-web platforms — HLS playback is handled natively by mpv.
void ensureWebHlsPlayable() {}

/// Non-web: quality comes from mpv's embedded video tracks.
List<({int index, int? height})> webHlsLevels() => const [];

int webHlsCurrentLevel() => -1;

bool webHlsAutoEnabled() => true;

void setWebHlsLevel(int index) {}
