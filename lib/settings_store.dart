import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// App-wide settings, persisted in SharedPreferences.
/// Every screen reads from this store; the Settings screens write to it.
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsStore> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsStore store = SettingsStore._(prefs);
    store._readAll();
    return store;
  }

  // --- Appearance ---
  ThemeMode themeMode = ThemeMode.dark;
  int accentIndex = 0;

  /// Bottom nav pill style: 'glass' (Liquid Glass, default) or 'blurry'
  /// (frosted blur). Applied to the nav pill immediately on change.
  String navStyle = 'blurry';

  // --- Player: subtitles ---
  String subFont = 'Inter Semibold';
  double subSize = 18;
  int subColorIndex = 0;
  bool subBackground = true;
  String subPosition = 'Bottom';
  int subDelayMs = 200;

  // --- Player: playback ---
  int doubleTapSeek = 10;
  double playbackSpeed = 1.0;
  bool gestures = true;
  bool hwDecoding = true;

  // --- Player: skip intro ---
  bool skipIntro = true;

  /// Auto-play the next episode when the current one ends (player overlay
  /// with a 5 s countdown; tap to cancel).
  bool autoplayNext = true;

  /// Resume positions, seconds into the episode. Key: "$animeId:$episode".
  Map<String, double> resumeSeconds = <String, double>{};

  // --- Servers / sources ---
  String preferredServer = 'Miruro';
  bool fallbackProviders = true;
  List<ProviderSource> sources = defaultSources();

  // --- Downloads ---
  String downloadQuality = '1080p';
  bool wifiOnly = true;

  /// Per-episode download state. Key: "$animeId:$episodeNumber".
  /// Values: 'queued' | 'downloading' | 'downloaded'.
  /// M1: UI state only — no real file download yet (wires in M2).
  Map<String, String> downloadStatus = <String, String>{};
  Map<String, double> downloadProgress = <String, double>{};

  // --- Debrid (M1: Settings UI only — key entry + connected state.
  /// No real API calls yet; the user connects his own paid account later.
  /// M2 must move these keys to secure storage (flutter_secure_storage).
  String? torboxApiKey;
  String? realDebridApiKey;

  // --- App lock ---
  bool appLockEnabled = false;
  bool faceIdEnabled = false;
  String? pinHash;

  // --- Collection lists (AniList-style statuses) ---
  // Explicit per-anime status: 'watching' | 'finished' | 'plan'.
  // Derived when unset: progress or a started episode -> watching;
  // saved with no progress -> plan. A newly saved title defaults to
  // 'plan' (To Be Watched). Downloads live in Settings only.
  Map<String, String> listStatus = <String, String>{};

  // --- Collection (M1: local only) ---
  Set<String> savedIds = <String>{};
  Map<String, int> progressEpisodes = <String, int>{};

  bool get hasPin => pinHash != null && pinHash!.isNotEmpty;

  void _readAll() {
    final String mode = _prefs.getString('theme_mode') ?? 'dark';
    themeMode = switch (mode) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    accentIndex = _prefs.getInt('accent_index') ?? 0;
    navStyle = _prefs.getString('nav_style') ?? 'blurry';
    subFont = _prefs.getString('sub_font') ?? 'Inter Semibold';
    subSize = _prefs.getDouble('sub_size') ?? 18;
    subColorIndex = _prefs.getInt('sub_color') ?? 0;
    subBackground = _prefs.getBool('sub_background') ?? true;
    subPosition = _prefs.getString('sub_position') ?? 'Bottom';
    subDelayMs = _prefs.getInt('sub_delay_ms') ?? 200;
    doubleTapSeek = _prefs.getInt('double_tap_seek') ?? 10;
    playbackSpeed = _prefs.getDouble('playback_speed') ?? 1.0;
    gestures = _prefs.getBool('gestures') ?? true;
    hwDecoding = _prefs.getBool('hw_decoding') ?? true;
    skipIntro = _prefs.getBool('skip_intro') ?? true;
    autoplayNext = _prefs.getBool('autoplay_next') ?? true;
    final String? resumeJson = _prefs.getString('resume_seconds');
    if (resumeJson != null) {
      try {
        final Map<String, dynamic> decoded =
            jsonDecode(resumeJson) as Map<String, dynamic>;
        resumeSeconds = decoded.map(
          (String k, dynamic v) => MapEntry(k, (v as num).toDouble()),
        );
      } catch (_) {
        resumeSeconds = <String, double>{};
      }
    }
    preferredServer = _prefs.getString('preferred_server') ?? 'Miruro';
    fallbackProviders = _prefs.getBool('fallback_providers') ?? true;
    downloadQuality = _prefs.getString('download_quality') ?? '1080p';
    wifiOnly = _prefs.getBool('wifi_only') ?? true;
    final String? downloadsJson = _prefs.getString('download_status');
    if (downloadsJson != null) {
      try {
        final Map<String, dynamic> decoded =
            jsonDecode(downloadsJson) as Map<String, dynamic>;
        downloadStatus = decoded.map(
          (String k, dynamic v) => MapEntry(k, v as String),
        );
      } catch (_) {
        downloadStatus = <String, String>{};
      }
    }
    final String? dlProgressJson = _prefs.getString('download_progress');
    if (dlProgressJson != null) {
      try {
        final Map<String, dynamic> decoded =
            jsonDecode(dlProgressJson) as Map<String, dynamic>;
        downloadProgress = decoded.map(
          (String k, dynamic v) => MapEntry(k, (v as num).toDouble()),
        );
      } catch (_) {
        downloadProgress = <String, double>{};
      }
    }
    torboxApiKey = _prefs.getString('torbox_api_key');
    realDebridApiKey = _prefs.getString('realdebrid_api_key');
    appLockEnabled = _prefs.getBool('app_lock') ?? false;
    faceIdEnabled = _prefs.getBool('face_id') ?? false;
    pinHash = _prefs.getString('pin_hash');
    savedIds = _prefs.getStringList('saved_ids')?.toSet() ?? <String>{};
    final String? progressJson = _prefs.getString('progress_eps');
    if (progressJson != null) {
      final Map<String, dynamic> decoded =
          jsonDecode(progressJson) as Map<String, dynamic>;
      progressEpisodes = decoded.map(
        (String k, dynamic v) => MapEntry(k, (v as num).toInt()),
      );
    }
    final String? listStatusJson = _prefs.getString('list_status');
    if (listStatusJson != null) {
      try {
        final Map<String, dynamic> decoded =
            jsonDecode(listStatusJson) as Map<String, dynamic>;
        listStatus = decoded.map(
          (String k, dynamic v) => MapEntry(k, v as String),
        );
      } catch (_) {
        listStatus = <String, String>{};
      }
    }
    final String? sourcesJson = _prefs.getString('sources');
    if (sourcesJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(sourcesJson) as List<dynamic>;
        sources = decoded.map((dynamic e) {
          final Map<String, dynamic> m = e as Map<String, dynamic>;
          return ProviderSource(
            name: m['name'] as String,
            tagline: m['tagline'] as String,
            enabled: m['enabled'] as bool,
            preferred: m['preferred'] as bool? ?? false,
          );
        }).toList();
      } catch (_) {
        sources = defaultSources();
      }
    }
  }

  Future<void> _save(String key, Object value) async {
    if (value is String) {
      await _prefs.setString(key, value);
    } else if (value is int) {
      await _prefs.setInt(key, value);
    } else if (value is double) {
      await _prefs.setDouble(key, value);
    } else if (value is bool) {
      await _prefs.setBool(key, value);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await _save('theme_mode', switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    });
    notifyListeners();
  }

  Future<void> setAccentIndex(int index) async {
    accentIndex = index;
    await _save('accent_index', index);
    notifyListeners();
  }

  Future<void> setNavStyle(String style) async {
    navStyle = style;
    await _save('nav_style', style);
    notifyListeners();
  }

  Future<void> setSubFont(String font) async {
    subFont = font;
    await _save('sub_font', font);
    notifyListeners();
  }

  Future<void> setSubSize(double size) async {
    subSize = size;
    await _save('sub_size', size);
    notifyListeners();
  }

  Future<void> setSubColorIndex(int index) async {
    subColorIndex = index;
    await _save('sub_color', index);
    notifyListeners();
  }

  Future<void> setSubBackground(bool value) async {
    subBackground = value;
    await _save('sub_background', value);
    notifyListeners();
  }

  Future<void> setSubPosition(String position) async {
    subPosition = position;
    await _save('sub_position', position);
    notifyListeners();
  }

  Future<void> setSubDelayMs(int ms) async {
    subDelayMs = ms;
    await _save('sub_delay_ms', ms);
    notifyListeners();
  }

  Future<void> setDoubleTapSeek(int seconds) async {
    doubleTapSeek = seconds;
    await _save('double_tap_seek', seconds);
    notifyListeners();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    playbackSpeed = speed;
    await _save('playback_speed', speed);
    notifyListeners();
  }

  Future<void> setGestures(bool value) async {
    gestures = value;
    await _save('gestures', value);
    notifyListeners();
  }

  Future<void> setHwDecoding(bool value) async {
    hwDecoding = value;
    await _save('hw_decoding', value);
    notifyListeners();
  }

  Future<void> setSkipIntro(bool value) async {
    skipIntro = value;
    await _save('skip_intro', value);
    notifyListeners();
  }

  Future<void> setAutoplayNext(bool value) async {
    autoplayNext = value;
    await _save('autoplay_next', value);
    notifyListeners();
  }

  Future<void> setResumeSeconds(String key, double seconds) async {
    resumeSeconds[key] = seconds;
    await _prefs.setString('resume_seconds', jsonEncode(resumeSeconds));
    notifyListeners();
  }

  Future<void> clearResumeSeconds(String key) async {
    resumeSeconds.remove(key);
    await _prefs.setString('resume_seconds', jsonEncode(resumeSeconds));
    notifyListeners();
  }

  Future<void> setPreferredServer(String name) async {
    preferredServer = name;
    sources = sources
        .map((ProviderSource s) => s.copyWith(preferred: s.name == name))
        .toList();
    await _save('preferred_server', name);
    await _saveSources();
    notifyListeners();
  }

  Future<void> setFallbackProviders(bool value) async {
    fallbackProviders = value;
    await _save('fallback_providers', value);
    notifyListeners();
  }

  Future<void> setSources(List<ProviderSource> next) async {
    sources = List<ProviderSource>.of(next);
    await _saveSources();
    notifyListeners();
  }

  Future<void> _saveSources() async {
    final String json = jsonEncode(
      sources
          .map(
            (ProviderSource s) => <String, Object>{
              'name': s.name,
              'tagline': s.tagline,
              'enabled': s.enabled,
              'preferred': s.preferred,
            },
          )
          .toList(),
    );
    await _prefs.setString('sources', json);
  }

  Future<void> setDownloadQuality(String quality) async {
    downloadQuality = quality;
    await _save('download_quality', quality);
    notifyListeners();
  }

  Future<void> setWifiOnly(bool value) async {
    wifiOnly = value;
    await _save('wifi_only', value);
    notifyListeners();
  }

  Future<void> setDownloadStatus(String key, String status) async {
    downloadStatus[key] = status;
    if (status == 'downloaded') {
      downloadProgress[key] = 1.0;
    }
    await _prefs.setString('download_status', jsonEncode(downloadStatus));
    await _prefs.setString('download_progress', jsonEncode(downloadProgress));
    notifyListeners();
  }

  Future<void> setDownloadProgress(String key, double progress) async {
    downloadProgress[key] = progress;
    await _prefs.setString('download_progress', jsonEncode(downloadProgress));
    notifyListeners();
  }

  Future<void> removeDownload(String key) async {
    downloadStatus.remove(key);
    downloadProgress.remove(key);
    await _prefs.setString('download_status', jsonEncode(downloadStatus));
    await _prefs.setString('download_progress', jsonEncode(downloadProgress));
    notifyListeners();
  }

  Future<void> setTorboxApiKey(String? key) async {
    torboxApiKey = key;
    if (key == null || key.isEmpty) {
      await _prefs.remove('torbox_api_key');
    } else {
      await _prefs.setString('torbox_api_key', key);
    }
    notifyListeners();
  }

  Future<void> setRealDebridApiKey(String? key) async {
    realDebridApiKey = key;
    if (key == null || key.isEmpty) {
      await _prefs.remove('realdebrid_api_key');
    } else {
      await _prefs.setString('realdebrid_api_key', key);
    }
    notifyListeners();
  }

  Future<void> setAppLockEnabled(bool value) async {
    appLockEnabled = value;
    await _save('app_lock', value);
    notifyListeners();
  }

  Future<void> setFaceIdEnabled(bool value) async {
    faceIdEnabled = value;
    await _save('face_id', value);
    notifyListeners();
  }

  Future<void> setPinHash(String? hash) async {
    pinHash = hash;
    if (hash == null) {
      await _prefs.remove('pin_hash');
    } else {
      await _prefs.setString('pin_hash', hash);
    }
    notifyListeners();
  }

  Future<void> toggleSaved(String animeId) async {
    if (savedIds.contains(animeId)) {
      savedIds.remove(animeId);
      listStatus.remove(animeId);
      await _saveListStatus();
    } else {
      savedIds.add(animeId);
      // A newly saved title defaults to To Be Watched.
      listStatus.putIfAbsent(animeId, () => 'plan');
      await _saveListStatus();
    }
    await _prefs.setStringList('saved_ids', savedIds.toList());
    notifyListeners();
  }

  /// Collection status for an anime: explicit list status when set,
  /// else derived — started (progress / Continue Watching) is Watching,
  /// saved-but-unstarted is To Be Watched, otherwise not listed.
  /// Returns 'watching' | 'finished' | 'plan' | null.
  String? statusOf(Anime anime) {
    final String? explicit = listStatus[anime.id];
    if (explicit != null) return explicit;
    final int? ep = progressEpisodes[anime.id];
    if (ep != null || anime.currentEpisode != null) return 'watching';
    if (savedIds.contains(anime.id)) return 'plan';
    return null;
  }

  Future<void> _saveListStatus() async {
    await _prefs.setString('list_status', jsonEncode(listStatus));
  }

  /// Move an anime to a Collection list ('watching' | 'finished' |
  /// 'plan'); null removes it from all lists. Listing implies saved.
  Future<void> setListStatus(String animeId, String? status) async {
    if (status == null) {
      listStatus.remove(animeId);
    } else {
      listStatus[animeId] = status;
      if (!savedIds.contains(animeId)) {
        savedIds.add(animeId);
        await _prefs.setStringList('saved_ids', savedIds.toList());
      }
    }
    await _saveListStatus();
    notifyListeners();
  }

  Future<void> markProgress(String animeId, int episode) async {
    progressEpisodes[animeId] = episode;
    await _prefs.setString('progress_eps', jsonEncode(progressEpisodes));
    notifyListeners();
  }
}
