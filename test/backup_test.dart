import 'dart:convert';

import 'package:anibee/models.dart';
import 'package:anibee/services/backup_service.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.11: backup / restore — export is versioned JSON with lists,
/// progress, history and settings; import restores them. Secrets
/// (tokens, debrid keys, PIN) and download records never leave the
/// device in a backup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async => null,
    );
  });

  const Anime jjk = Anime(
    id: 'anilist-113415',
    title: 'Jujutsu Kaisen',
    rating: 4.5,
    year: 2020,
    episodeCount: 24,
    genres: <String>['Action'],
    synopsis: 'Test anime.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    anilistId: 113415,
  );

  test('export -> wipe -> import restores lists + progress + settings',
      () async {
    final SettingsStore store = await SettingsStore.load();
    await store.setListStatus(jjk, 'watching');
    await store.markProgress(jjk, 5);
    await store.setAutoplayCountdownSeconds(10);
    await store.setPreferredServer('AniKoto');

    final Map<String, dynamic> doc = BackupService.exportBackup(store);
    expect(doc['format'], 'anibee-backup');
    expect(doc['version'], BackupService.currentVersion);
    // 0.2.18: list keys are canonical ('al:<anilistId>').
    expect(doc['lists'], <String, String>{'al:113415': 'watching'});
    expect(doc['settings']['autoplayCountdownSeconds'], 10);
    expect(doc['settings']['preferredServer'], 'AniKoto');
    // No secrets anywhere in the document.
    final String json = jsonEncode(doc);
    expect(json, isNot(contains('torboxApiKey')));
    expect(json, isNot(contains('realDebridApiKey')));
    expect(json, isNot(contains('pinHash')));
    expect(json, isNot(contains('anilistToken')));

    // Wipe the state, then restore from the exported doc.
    await store.setListStatus(jjk, null);
    // 0.2.18: "Remove from list" keeps the progress but the
    // title is in NO tab — and the removal marker travels in the
    // backup.
    expect(store.statusOf(jjk), isNull);
    expect(store.progressEpisodeFor(jjk), 5);
    final Map<String, dynamic> removedDoc =
        BackupService.exportBackup(store);
    expect(removedDoc['removedLists'], contains('al:113415'));
    await store.setAutoplayCountdownSeconds(5);
    await store.setPreferredServer('Miruro');
    final ({bool ok, String message, int lists}) result =
        await BackupService.importBackup(store, doc);
    expect(result.ok, isTrue);
    expect(result.lists, 1);
    expect(result.message, isNotEmpty);
    expect(store.listStatus['al:113415'], 'watching');
    expect(store.progressEpisodes['al:113415'], 5);
    expect(store.autoplayCountdownSeconds, 10);
    expect(store.preferredServer, 'AniKoto');
  });

  test('import rejects wrong format / bad version', () async {
    final SettingsStore store = await SettingsStore.load();
    final badFormat = await BackupService.importBackup(store, <String, dynamic>{
      'format': 'something-else',
      'version': 1,
    });
    expect(badFormat.ok, isFalse);
    final badVersion = await BackupService.importBackup(store, <String, dynamic>{
      'format': 'anibee-backup',
      'version': 99,
    });
    expect(badVersion.ok, isFalse);
    expect(BackupService.parseBackupText('not json'), isNull);
    expect(BackupService.parseBackupText('{"format":"anibee-backup"}'), isNotNull);
  });
}
