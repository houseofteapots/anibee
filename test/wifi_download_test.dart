import 'dart:io';

import 'package:anibee/models.dart';
import 'package:anibee/services/download_service.dart';
import 'package:anibee/services/miruro_resolver.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.11: Wi-Fi-only downloads ENFORCED (the setting existed since
/// 0.2.5 but was UI-only). With wifiOnly ON and no Wi-Fi, a download
/// must not start — the record goes 'paused' and startDownload
/// returns false. With Wi-Fi (or the setting OFF) it proceeds.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async => null,
    );
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anibee-wifi-test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  const Anime anime = Anime(
    id: 'dl-wifi',
    title: 'WiFi Test Anime',
    rating: 4.0,
    year: 2024,
    episodeCount: 1,
    genres: <String>['Action'],
    synopsis: 'Test anime.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    anilistId: 999031,
  );

  List<Episode> episodes() => <Episode>[
    const Episode(
      number: 1,
      title: 'Episode 1',
      duration: '24 min',
      synopsis: 'Test episode.',
      airDate: 'Oct 4, 2026',
      hasDub: true,
    ),
  ];

  MockClient fileClient() => MockClient((http.Request request) async {
    const List<int> bytes = <int>[0, 1, 2, 3, 4, 5, 6, 7];
    return http.Response.bytes(
      bytes,
      200,
      headers: <String, String>{'content-length': '8'},
    );
  });

  test('wifiOnly ON + mobile data -> startDownload false, status paused',
      () async {
    final SettingsStore store = await SettingsStore.load();
    await store.setWifiOnly(true);
    final DownloadService service = DownloadService(
      client: fileClient(),
      baseDirOverride: tempDir,
      isWifiOverride: () async => false,
    );
    final bool started = await service.startDownload(
      anime: anime,
      episode: episodes()[0],
      stream: const ResolvedStream(
        url: 'https://files.example.com/ep1.mp4',
        label: 'Test 1080p',
        source: 'Miruro',
      ),
      store: store,
    );
    expect(started, isFalse);
    expect(store.downloadStatus['dl-wifi:1'], 'paused');
    // Nothing was written to disk (the gate is before any dir/file
    // creation in startDownload).
    expect(
      await Directory('${tempDir.path}/downloads/dl-wifi_1').exists(),
      isFalse,
    );
  });

  test('wifiOnly ON + Wi-Fi -> download proceeds to downloaded', () async {
    final SettingsStore store = await SettingsStore.load();
    await store.setWifiOnly(true);
    final DownloadService service = DownloadService(
      client: fileClient(),
      baseDirOverride: tempDir,
      isWifiOverride: () async => true,
    );
    final bool started = await service.startDownload(
      anime: anime,
      episode: episodes()[0],
      stream: const ResolvedStream(
        url: 'https://files.example.com/ep1.mp4',
        label: 'Test 1080p',
        source: 'Miruro',
      ),
      store: store,
    );
    expect(started, isTrue);
    expect(store.downloadStatus['dl-wifi:1'], 'downloaded');
  });

  test('wifiOnly OFF + mobile data -> download proceeds', () async {
    final SettingsStore store = await SettingsStore.load();
    await store.setWifiOnly(false);
    final DownloadService service = DownloadService(
      client: fileClient(),
      baseDirOverride: tempDir,
      isWifiOverride: () async => false,
    );
    final bool started = await service.startDownload(
      anime: anime,
      episode: episodes()[0],
      stream: const ResolvedStream(
        url: 'https://files.example.com/ep1.mp4',
        label: 'Test 1080p',
        source: 'Miruro',
      ),
      store: store,
    );
    expect(started, isTrue);
    expect(store.downloadStatus['dl-wifi:1'], 'downloaded');
    await store.setWifiOnly(true);
  });
}
