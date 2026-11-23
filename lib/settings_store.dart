import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'services/secure_store.dart';

/// One real Continue Watching entry: the title, episode, saved
/// position + duration, and enough anime metadata to rebuild the
/// Detail screen. Persisted in `watch_history` (most recent first,
/// capped at 20). The mock catalogue's currentEpisode/minutesLeft
/// must NOT drive the row — only these real entries do (0.2.3: the
/// row showed Solo Leveling EP 7 / JJK EP 5 / Demon Slayer EP 5
/// while the user had actually watched JJK EP 1 + Chainsaw Man EP 2).
class WatchEntry {
  const WatchEntry({
    required this.key,
    required this.animeId,
    required this.title,
    required this.episode,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.updatedAt,
    this.anilistId,
    this.posterUrl,
    this.episodeCount = 0,
    this.year = 0,
    this.rating = 0,
    this.genres = const <String>[],
    this.synopsis = '',
  });

  factory WatchEntry.fromJson(Map<String, dynamic> json) {
    return WatchEntry(
      key: json['key'] as String? ?? '',
      animeId: json['animeId'] as String? ?? '',
      anilistId: (json['anilistId'] as num?)?.toInt(),
      title: json['title'] as String? ?? 'Unknown',
      posterUrl: json['posterUrl'] as String?,
      episodeCount: (json['episodeCount'] as num?)?.toInt() ?? 0,
      year: (json['year'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      genres:
          (json['genres'] as List<dynamic>?)
              ?.map((dynamic e) => e as String)
              .toList() ??
          const <String>[],
      synopsis: json['synopsis'] as String? ?? '',
      episode: (json['episode'] as num?)?.toInt() ?? 1,
      positionSeconds: (json['position'] as num?)?.toDouble() ?? 0,
      durationSeconds: (json['duration'] as num?)?.toDouble() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  /// Canonical identity: `'al:<anilistId>'` when known, else
  /// `'id:<catalogue id>'`.
  final String key;
  final String animeId;
  final int? anilistId;
  final String title;
  final String? posterUrl;
  final int episodeCount;
  final int year;
  final double rating;
  final List<String> genres;
  final String synopsis;
  final int episode;
  final double positionSeconds;
  final double durationSeconds;
  final int updatedAt;

  double get progress {
    if (durationSeconds <= 0) return 0;
    return (positionSeconds / durationSeconds).clamp(0.0, 1.0);
  }

  int get minutesLeft {
    if (durationSeconds <= positionSeconds) return 0;
    return ((durationSeconds - positionSeconds) / 60).ceil();
  }

  WatchEntry copyWith({
    int? episode,
    double? positionSeconds,
    double? durationSeconds,
    int? updatedAt,
  }) {
    return WatchEntry(
      key: key,
      animeId: animeId,
      anilistId: anilistId,
      title: title,
      posterUrl: posterUrl,
      episodeCount: episodeCount,
      year: year,
      rating: rating,
      genres: genres,
      synopsis: synopsis,
      episode: episode ?? this.episode,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'key': key,
      'animeId': animeId,
      'anilistId': anilistId,
      'title': title,
      'posterUrl': posterUrl,
      'episodeCount': episodeCount,
      'year': year,
      'rating': rating,
      'genres': genres,
      'synopsis': synopsis,
      'episode': episode,
      'position': positionSeconds,
      'duration': durationSeconds,
      'updatedAt': updatedAt,
    };
  }

  Anime toAnime() {
    return Anime(
      id: animeId,
      anilistId: anilistId,
      title: title,
      rating: rating,
      year: year,
      episodeCount: episodeCount,
      genres: genres,
      synopsis: synopsis,
      gradient: const <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
      posterUrl: posterUrl,
      currentEpisode: episode,
      minutesLeft: minutesLeft,
    );
  }
}

/// App-wide settings, persisted in SharedPreferences.
/// Secrets (Debrid keys, OAuth tokens, client IDs) live in secure
/// storage (M2) — migrated from prefs on first load.
/// Every screen reads from this store; the Settings screens write to it.
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._prefs, this._secure);

  final SharedPreferences _prefs;
  final SecureStore _secure;

  static Future<SettingsStore> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SecureStore secure = SecureStore();
    final SettingsStore store = SettingsStore._(prefs, secure);
    await store._migrateSecrets();
    store._readAll();
    await store._readSecrets();
    return store;
  }

  /// M2: move Debrid keys out of SharedPreferences plaintext into
  /// the Keychain (iOS). Runs once — old prefs keys are deleted after.
  Future<void> _migrateSecrets() async {
    final String? torbox = _prefs.getString('torbox_api_key');
    if (torbox != null && torbox.isNotEmpty) {
      await _secure.write(SecureStore.torboxApiKey, torbox);
      await _prefs.remove('torbox_api_key');
    }
    final String? rd = _prefs.getString('realdebrid_api_key');
    if (rd != null && rd.isNotEmpty) {
      await _secure.write(SecureStore.realDebridApiKey, rd);
      await _prefs.remove('realdebrid_api_key');
    }
  }

  Future<void> _readSecrets() async {
    torboxApiKey = await _secure.read(SecureStore.torboxApiKey);
    realDebridApiKey = await _secure.read(SecureStore.realDebridApiKey);
    anilistToken = await _secure.read(SecureStore.anilistAccessToken);
    malAccessToken = await _secure.read(SecureStore.malAccessToken);
    malRefreshToken = await _secure.read(SecureStore.malRefreshToken);
    final String? expiry = await _secure.read(SecureStore.malTokenExpiry);
    malTokenExpiry = expiry == null ? null : DateTime.tryParse(expiry);
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
  // 0.2.4: background migrated from a bool to a mode ('off' | 'dark' |
  // 'solid'); the bool getter below keeps player_settings_screen.dart
  // working unchanged. Outline/opacity/encoding/auto-adjust/manual
  // position drive the Zeus-style subtitle editor in the player.
  String subBackgroundMode = 'dark';
  bool get subBackground => subBackgroundMode != 'off';
  String subPosition = 'Bottom';
  int subDelayMs = 200;
  bool subBold = false;
  String subOutline = 'medium';
  int subOpacity = 100;
  String subEncoding = 'auto';
  bool subAutoAdjust = true;
  double subManualPercent = 0;

  /// Preferred subtitle language (Settings → Player): 'auto' |
  /// 'en' | 'hi' | 'ar' | 'off'. 'auto' means English by default.
  /// The player auto-selects this language's track when available.
  String subtitleLanguage = 'auto';

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

  /// Resume positions, seconds into the episode. Key: canonical
  /// resume key (see [resumeKeyFor]) — `'al:<anilistId>:ep<n>'` or
  /// `'id:<catalogue id>:ep<n>'`.
  Map<String, double> resumeSeconds = <String, double>{};

  /// Per-episode watched DURATION (seconds) for the resume key, so
  /// the episode list can show real progress fractions (0.2.5).
  /// Written alongside the resume position by the player; cleared
  /// with it when the episode finishes.
  Map<String, double> resumeDurations = <String, double>{};

  /// Episodes watched to the end, by resume key. The player marks an
  /// episode when playback passes the finished threshold; the episode
  /// list shows it as completed (checkmark / watched tick).
  Set<String> completedEpisodes = <String>{};

  /// Completed = watched to the end: position >= 90% of duration.
  /// Same threshold the player uses to clear the resume (pos within
  /// the last 20 s of a ~24 min episode is ~98% — the 0.9 bar also
  /// covers shorter episodes and a seek-to-end).
  static const double kCompletedFraction = 0.9;

  /// Offline download records (0.2.5): key -> JSON record (anime id
  /// + title + episode, local playlist/file path, stream URL +
  /// headers for resume, segment state). The file itself lives under
  /// the app documents dir; this map is the index. A 'downloaded'
  /// status with NO record here is a pre-0.2.5 simulated download
  /// (no file exists) — the download service prunes those at start.
  Map<String, Map<String, dynamic>> downloadRecords =
      <String, Map<String, dynamic>>{};

  /// Real Continue Watching history (most recent first). The Home
  /// row is driven ONLY by this — never by the mock catalogue.
  List<WatchEntry> watchHistory = <WatchEntry>[];

  // --- Servers / sources ---
  String preferredServer = 'Miruro';
  bool fallbackProviders = true;
  List<ProviderSource> sources = defaultSources();

  // --- Downloads ---
  String downloadQuality = '1080p';
  bool wifiOnly = true;

  /// Per-episode download state. Key: "$animeId:$episodeNumber".
  /// Values: 'queued' | 'downloading' | 'downloaded' | 'failed'.
  /// 0.2.5: real files — see DownloadService + [downloadRecords].
  /// 'downloaded' with no record = pre-0.2.5 simulation, pruned.
  Map<String, String> downloadStatus = <String, String>{};
  Map<String, double> downloadProgress = <String, double>{};

  // --- Debrid (M2: keys in secure storage; verified with a real
  /// API call on save — "Connected" means the key actually works.)
  String? torboxApiKey;
  String? realDebridApiKey;
  bool torboxVerified = false;
  String? torboxAccount;
  bool realDebridVerified = false;
  String? realDebridAccount;

  // --- Accounts (M2: real OAuth). Tokens live in secure storage.
  // Client IDs are NOT user-entered: they are the app's developer
  // clients, read from the remote provider config (0.2.3) — the
  // login sheet opens the browser authorize page directly.
  String? anilistToken;
  String? anilistUsername;
  String? malAccessToken;
  String? malRefreshToken;
  DateTime? malTokenExpiry;
  String? malUsername;

  bool get anilistConnected => anilistToken != null && anilistToken!.isNotEmpty;
  bool get malConnected => malAccessToken != null && malAccessToken!.isNotEmpty;

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
    // Migrate the old bool ('sub_background'): dark when it was on.
    subBackgroundMode =
        _prefs.getString('sub_background_mode') ??
        ((_prefs.getBool('sub_background') ?? true) ? 'dark' : 'off');
    subPosition = _prefs.getString('sub_position') ?? 'Bottom';
    subDelayMs = _prefs.getInt('sub_delay_ms') ?? 200;
    subBold = _prefs.getBool('sub_bold') ?? false;
    subOutline = _prefs.getString('sub_outline') ?? 'medium';
    subOpacity = _prefs.getInt('sub_opacity') ?? 100;
    subEncoding = _prefs.getString('sub_encoding') ?? 'auto';
    subAutoAdjust = _prefs.getBool('sub_auto_adjust') ?? true;
    subManualPercent = _prefs.getDouble('sub_manual_percent') ?? 0;
    subtitleLanguage = _prefs.getString('sub_language') ?? 'auto';
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
    final String? durationsJson = _prefs.getString('resume_durations');
    if (durationsJson != null) {
      try {
        final Map<String, dynamic> decoded =
            jsonDecode(durationsJson) as Map<String, dynamic>;
        resumeDurations = decoded.map(
          (String k, dynamic v) => MapEntry(k, (v as num).toDouble()),
        );
      } catch (_) {
        resumeDurations = <String, double>{};
      }
    }
    completedEpisodes =
        _prefs.getStringList('completed_eps')?.toSet() ?? <String>{};
    final String? recordsJson = _prefs.getString('download_records');
    if (recordsJson != null) {
      try {
        final Map<String, dynamic> decoded =
            jsonDecode(recordsJson) as Map<String, dynamic>;
        downloadRecords = decoded.map(
          (String k, dynamic v) =>
              MapEntry(k, Map<String, dynamic>.from(v as Map<String, dynamic>)),
        );
      } catch (_) {
        downloadRecords = <String, Map<String, dynamic>>{};
      }
    }
    final String? historyJson = _prefs.getString('watch_history');
    if (historyJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(historyJson) as List<dynamic>;
        watchHistory = decoded
            .map((dynamic e) => WatchEntry.fromJson(e as Map<String, dynamic>))
            .where((WatchEntry e) => e.key.isNotEmpty)
            .toList();
      } catch (_) {
        watchHistory = <WatchEntry>[];
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
    torboxVerified = _prefs.getBool('torbox_verified') ?? false;
    torboxAccount = _prefs.getString('torbox_account');
    realDebridVerified = _prefs.getBool('realdebrid_verified') ?? false;
    realDebridAccount = _prefs.getString('realdebrid_account');
    anilistUsername = _prefs.getString('anilist_username');
    malUsername = _prefs.getString('mal_username');
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
    subBackgroundMode = value ? 'dark' : 'off';
    await _save('sub_background', value);
    await _save('sub_background_mode', subBackgroundMode);
    notifyListeners();
  }

  Future<void> setSubBackgroundMode(String mode) async {
    subBackgroundMode = mode;
    await _save('sub_background_mode', mode);
    await _save('sub_background', mode != 'off');
    notifyListeners();
  }

  Future<void> setSubBold(bool value) async {
    subBold = value;
    await _save('sub_bold', value);
    notifyListeners();
  }

  Future<void> setSubOutline(String outline) async {
    subOutline = outline;
    await _save('sub_outline', outline);
    notifyListeners();
  }

  Future<void> setSubOpacity(int value) async {
    subOpacity = value.clamp(0, 100);
    await _save('sub_opacity', subOpacity);
    notifyListeners();
  }

  Future<void> setSubEncoding(String encoding) async {
    subEncoding = encoding;
    await _save('sub_encoding', encoding);
    notifyListeners();
  }

  Future<void> setSubAutoAdjust(bool value) async {
    subAutoAdjust = value;
    await _save('sub_auto_adjust', value);
    notifyListeners();
  }

  Future<void> setSubManualPercent(double value) async {
    subManualPercent = value.clamp(0, 100);
    await _save('sub_manual_percent', subManualPercent);
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

  Future<void> setSubtitleLanguage(String language) async {
    subtitleLanguage = language;
    await _save('sub_language', language);
    notifyListeners();
  }

  // ------------------------------------------------- canonical identity

  /// Canonical identity for an anime: the AniList id when known
  /// ('al:113415'), else the catalogue id ('id:jujutsu-kaisen').
  /// The SAME title opened from Home ('jujutsu-kaisen') and from
  /// Search ('anilist-113415') must share one progress/resume key —
  /// raw ids fragmented them and resume was lost across entry points.
  static String keyFor(Anime anime) {
    if (anime.anilistId != null) return 'al:${anime.anilistId}';
    return 'id:${anime.id}';
  }

  String resumeKeyFor(Anime anime, int episode) {
    return '${keyFor(anime)}:ep$episode';
  }

  /// Saved resume position (seconds) for an anime episode: canonical
  /// key first, legacy raw-id key (`'<anime.id>:<episode>'`) as
  /// fallback for positions saved before 0.2.3.
  double? resumePositionFor(Anime anime, int episode) {
    final double? canonical = resumeSeconds[resumeKeyFor(anime, episode)];
    if (canonical != null) return canonical;
    return resumeSeconds['${anime.id}:$episode'];
  }

  /// Episode the user was last watching for this title (real watch
  /// history first, then the per-episode progress map), or null.
  int? progressEpisodeFor(Anime anime) {
    final String key = keyFor(anime);
    for (final WatchEntry e in watchHistory) {
      if (e.key == key) return e.episode;
    }
    return progressEpisodes[key] ?? progressEpisodes[anime.id];
  }

  // --------------------------------------------------- watch history

  /// Record real watch progress (called on play / pause / exit and
  /// periodically while playing). Upserts by canonical key, most
  /// recent first, capped at 20. This is what drives Continue
  /// Watching — never the mock catalogue.
  Future<void> recordWatch({
    required Anime anime,
    required int episode,
    required double positionSeconds,
    required double durationSeconds,
  }) async {
    final String key = keyFor(anime);
    watchHistory.removeWhere((WatchEntry e) => e.key == key);
    watchHistory.insert(
      0,
      WatchEntry(
        key: key,
        animeId: anime.id,
        anilistId: anime.anilistId,
        title: anime.title,
        posterUrl: anime.posterUrl,
        episodeCount: anime.episodeCount,
        year: anime.year,
        rating: anime.rating,
        genres: anime.genres,
        synopsis: anime.synopsis,
        episode: episode,
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (watchHistory.length > 20) {
      watchHistory.removeRange(20, watchHistory.length);
    }
    await _saveWatchHistory();
    notifyListeners();
  }

  Future<void> _saveWatchHistory() async {
    await _prefs.setString(
      'watch_history',
      jsonEncode(watchHistory.map((WatchEntry e) => e.toJson()).toList()),
    );
  }

  /// "Clear All" on the Continue Watching header (with a confirm step
  /// in the UI). Also drops the per-episode progress map so the row
  /// stays empty until the user watches something again.
  Future<void> clearWatchHistory() async {
    watchHistory = <WatchEntry>[];
    progressEpisodes = <String, int>{};
    await _prefs.remove('watch_history');
    await _prefs.setString('progress_eps', jsonEncode(progressEpisodes));
    notifyListeners();
  }

  Future<void> removeWatchEntry(String key) async {
    watchHistory.removeWhere((WatchEntry e) => e.key == key);
    await _saveWatchHistory();
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

  Future<void> setResumeDuration(String key, double seconds) async {
    resumeDurations[key] = seconds;
    await _prefs.setString('resume_durations', jsonEncode(resumeDurations));
    notifyListeners();
  }

  Future<void> clearResumeDuration(String key) async {
    resumeDurations.remove(key);
    await _prefs.setString('resume_durations', jsonEncode(resumeDurations));
    notifyListeners();
  }

  Future<void> markEpisodeCompleted(String key) async {
    if (completedEpisodes.add(key)) {
      await _prefs.setStringList('completed_eps', completedEpisodes.toList());
      notifyListeners();
    }
  }

  Future<void> clearEpisodeCompleted(String key) async {
    if (completedEpisodes.remove(key)) {
      await _prefs.setStringList('completed_eps', completedEpisodes.toList());
      notifyListeners();
    }
  }

  /// Parse an Episode.duration string ('23:12' / '1:02:30') to
  /// seconds. Null when unparseable.
  static double? parseDurationString(String raw) {
    final List<String> parts = raw.split(':');
    if (parts.isEmpty || parts.length > 3) return null;
    double total = 0;
    for (final String p in parts) {
      final int? v = int.tryParse(p);
      if (v == null) return null;
      total = total * 60 + v;
    }
    return total > 0 ? total : null;
  }

  /// Known duration (seconds) for an episode, best available: the
  /// duration the player saved with the resume, else the Continue
  /// Watching entry's duration when this is the latest episode, else
  /// the episode's own 'mm:ss' duration string. Null when unknown.
  double? episodeDurationFor(Anime anime, Episode episode) {
    final String key = resumeKeyFor(anime, episode.number);
    final double? saved =
        resumeDurations[key] ??
        resumeDurations['${anime.id}:${episode.number}'];
    if (saved != null && saved > 0) return saved;
    final String canonical = keyFor(anime);
    for (final WatchEntry e in watchHistory) {
      if (e.key == canonical && e.episode == episode.number) {
        if (e.durationSeconds > 0) return e.durationSeconds;
        break;
      }
    }
    return parseDurationString(episode.duration);
  }

  /// Real watch fraction 0..1 for an episode (0 = unwatched). 1.0
  /// when completed. Partial progress comes from the saved resume
  /// position over the known duration — never invented.
  double episodeProgressFor(Anime anime, Episode episode) {
    if (isEpisodeCompleted(anime, episode)) return 1.0;
    final double? pos = resumePositionFor(anime, episode.number);
    final double? dur = episodeDurationFor(anime, episode);
    if (pos == null || dur == null || dur <= 0) return 0;
    return (pos / dur).clamp(0.0, 1.0);
  }

  /// True when the episode was watched to the end (0.2.5):
  /// - an explicit completed marker from the player, OR
  /// - the saved resume fraction is >= [kCompletedFraction], OR
  /// - legacy inference for episodes finished before 0.2.5 kept no
  ///   marker/duration: the user has since started a LATER episode
  ///   of the same title (the app's existing "watched" rule).
  bool isEpisodeCompleted(Anime anime, Episode episode) {
    final String key = resumeKeyFor(anime, episode.number);
    if (completedEpisodes.contains(key) ||
        completedEpisodes.contains('${anime.id}:${episode.number}')) {
      return true;
    }
    final double? pos = resumePositionFor(anime, episode.number);
    final double? dur = episodeDurationFor(anime, episode);
    if (pos != null &&
        dur != null &&
        dur > 0 &&
        pos / dur >= kCompletedFraction) {
      return true;
    }
    final String canonical = keyFor(anime);
    int? latest;
    for (final WatchEntry e in watchHistory) {
      if (e.key == canonical) {
        latest = e.episode;
        break;
      }
    }
    latest ??= progressEpisodes[canonical] ?? progressEpisodes[anime.id];
    return latest != null && episode.number < latest;
  }

  /// Offline download record for a download key, or null when this
  /// episode was never really downloaded (pre-0.2.5 simulation).
  Map<String, dynamic>? downloadRecordFor(String key) => downloadRecords[key];

  Future<void> setDownloadRecord(
    String key,
    Map<String, dynamic> record,
  ) async {
    downloadRecords[key] = record;
    await _prefs.setString('download_records', jsonEncode(downloadRecords));
    notifyListeners();
  }

  Future<void> removeDownloadRecord(String key) async {
    if (downloadRecords.remove(key) != null) {
      await _prefs.setString('download_records', jsonEncode(downloadRecords));
      notifyListeners();
    }
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
    torboxVerified = false;
    torboxAccount = null;
    if (key == null || key.isEmpty) {
      await _secure.delete(SecureStore.torboxApiKey);
    } else {
      await _secure.write(SecureStore.torboxApiKey, key);
    }
    await _prefs.setBool('torbox_verified', false);
    await _prefs.remove('torbox_account');
    notifyListeners();
  }

  Future<void> setRealDebridApiKey(String? key) async {
    realDebridApiKey = key;
    realDebridVerified = false;
    realDebridAccount = null;
    if (key == null || key.isEmpty) {
      await _secure.delete(SecureStore.realDebridApiKey);
    } else {
      await _secure.write(SecureStore.realDebridApiKey, key);
    }
    await _prefs.setBool('realdebrid_verified', false);
    await _prefs.remove('realdebrid_account');
    notifyListeners();
  }

  /// Result of a real API verify call (GET /user/me, GET /user).
  Future<void> setTorboxVerified(bool verified, String? account) async {
    torboxVerified = verified;
    torboxAccount = account;
    await _prefs.setBool('torbox_verified', verified);
    if (account == null) {
      await _prefs.remove('torbox_account');
    } else {
      await _prefs.setString('torbox_account', account);
    }
    notifyListeners();
  }

  Future<void> setRealDebridVerified(bool verified, String? account) async {
    realDebridVerified = verified;
    realDebridAccount = account;
    await _prefs.setBool('realdebrid_verified', verified);
    if (account == null) {
      await _prefs.remove('realdebrid_account');
    } else {
      await _prefs.setString('realdebrid_account', account);
    }
    notifyListeners();
  }

  Future<void> setAnilistSession(String? token, String? username) async {
    anilistToken = token;
    anilistUsername = username;
    if (token == null || token.isEmpty) {
      await _secure.delete(SecureStore.anilistAccessToken);
    } else {
      await _secure.write(SecureStore.anilistAccessToken, token);
    }
    if (username == null) {
      await _prefs.remove('anilist_username');
    } else {
      await _prefs.setString('anilist_username', username);
    }
    notifyListeners();
  }

  Future<void> setMalSession({
    String? accessToken,
    String? refreshToken,
    DateTime? expiry,
    String? username,
  }) async {
    malAccessToken = accessToken;
    malRefreshToken = refreshToken;
    malTokenExpiry = expiry;
    malUsername = username;
    if (accessToken == null || accessToken.isEmpty) {
      await _secure.delete(SecureStore.malAccessToken);
    } else {
      await _secure.write(SecureStore.malAccessToken, accessToken);
    }
    if (refreshToken == null || refreshToken.isEmpty) {
      await _secure.delete(SecureStore.malRefreshToken);
    } else {
      await _secure.write(SecureStore.malRefreshToken, refreshToken);
    }
    if (expiry == null) {
      await _secure.delete(SecureStore.malTokenExpiry);
    } else {
      await _secure.write(SecureStore.malTokenExpiry, expiry.toIso8601String());
    }
    if (username == null) {
      await _prefs.remove('mal_username');
    } else {
      await _prefs.setString('mal_username', username);
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

  Future<void> markProgress(Anime anime, int episode) async {
    progressEpisodes[keyFor(anime)] = episode;
    await _prefs.setString('progress_eps', jsonEncode(progressEpisodes));
    // Keep the Continue Watching entry's episode in step even before
    // the player has saved a position for the new episode.
    final String key = keyFor(anime);
    final int i = watchHistory.indexWhere((WatchEntry e) => e.key == key);
    if (i >= 0) {
      watchHistory[i] = watchHistory[i].copyWith(episode: episode);
      await _saveWatchHistory();
    }
    notifyListeners();
  }
}
