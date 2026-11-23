import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../settings_store.dart';

/// Backup / restore (0.2.11): export watch history + settings
/// (Collection lists, Continue Watching positions, settings incl.
/// server order) to a versioned JSON file the user saves via the
/// share sheet; import restores it.
///
/// Deliberately NOT in a backup: login tokens, debrid API keys, the
/// app-lock PIN (secrets never leave the device this way), and
/// downloaded FILES + their records (device-local; a backup
/// restored on a fresh install has no files to point at).
class BackupService {
  static const int currentVersion = 1;

  /// Build the versioned backup document from the store. Pure.
  static Map<String, dynamic> exportBackup(SettingsStore store) {
    return <String, dynamic>{
      'format': 'anibee-backup',
      'version': currentVersion,
      'appVersion': '0.2.11',
      'exportedAt': DateTime.now().toIso8601String(),
      'lists': Map<String, String>.of(store.listStatus),
      'progressEpisodes': Map<String, int>.of(store.progressEpisodes),
      'watchHistory': store.watchHistory
          .map((WatchEntry e) => e.toJson())
          .toList(),
      'resumeSeconds': Map<String, double>.of(store.resumeSeconds),
      'resumeDurations': Map<String, double>.of(store.resumeDurations),
      'completedEpisodes': store.completedEpisodes.toList(),
      'syncedAnime': store.syncedAnime.map(
        (String k, Anime v) => MapEntry(k, v.toJson()),
      ),
      'settings': <String, dynamic>{
        'themeMode': switch (store.themeMode) {
          ThemeMode.light => 'light',
          ThemeMode.system => 'system',
          ThemeMode.dark => 'dark',
        },
        'accentIndex': store.accentIndex,
        'navStyle': store.navStyle,
        'subFont': store.subFont,
        'subSize': store.subSize,
        'subColorIndex': store.subColorIndex,
        'subBackgroundMode': store.subBackgroundMode,
        'subPosition': store.subPosition,
        'subDelayMs': store.subDelayMs,
        'doubleTapSeek': store.doubleTapSeek,
        'playbackSpeed': store.playbackSpeed,
        'gestures': store.gestures,
        'hwDecoding': store.hwDecoding,
        'skipIntro': store.skipIntro,
        'autoplayNext': store.autoplayNext,
        'autoplayCountdownSeconds': store.autoplayCountdownSeconds,
        'airingNotifications': store.airingNotifications,
        'preferredServer': store.preferredServer,
        'fallbackProviders': store.fallbackProviders,
        'downloadQuality': store.downloadQuality,
        'wifiOnly': store.wifiOnly,
        'autoDeleteDownloads': store.autoDeleteDownloads,
        'sources': store.sources
            .map(
              (ProviderSource s) => <String, Object>{
                'name': s.name,
                'tagline': s.tagline,
                'enabled': s.enabled,
                'preferred': s.preferred,
              },
            )
            .toList(),
      },
    };
  }

  /// Write the backup to a temp file and return it (the caller
  /// shares it via the iOS share sheet).
  static Future<File> exportToFile(SettingsStore store) async {
    final Directory dir = await getTemporaryDirectory();
    final DateTime now = DateTime.now();
    final String stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final File file = File('${dir.path}/anibee-backup-$stamp.json');
    await file.writeAsString(jsonEncode(exportBackup(store)));
    return file;
  }

  /// Validate + restore a parsed backup document. Returns
  /// (ok, message, restoredLists) — `message` is user-facing.
  static Future<({bool ok, String message, int lists})> importBackup(
    SettingsStore store,
    Map<String, dynamic> data,
  ) async {
    if (data['format'] != 'anibee-backup') {
      return (ok: false, message: 'Ye AniBee backup file nahi hai.', lists: 0);
    }
    final int? version = (data['version'] as num?)?.toInt();
    if (version == null) {
      return (
        ok: false,
        message: 'Backup file ka version nahi mila.',
        lists: 0,
      );
    }
    if (version > currentVersion) {
      return (
        ok: false,
        message:
            'Ye backup naye AniBee version ka hai — pehle app update karo.',
        lists: 0,
      );
    }
    try {
      await store.restoreFromBackup(data);
    } catch (_) {
      return (
        ok: false,
        message: 'Backup restore nahi hua — file corrupt ho sakti hai.',
        lists: 0,
      );
    }
    final Map<String, dynamic> lists =
        data['lists'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return (
      ok: true,
      message: 'Backup restore ho gaya.',
      lists: lists.length,
    );
  }

  /// Parse backup JSON text into a document (null when unparsable).
  static Map<String, dynamic>? parseBackupText(String text) {
    try {
      final dynamic decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }
}
