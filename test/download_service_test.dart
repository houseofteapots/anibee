import 'dart:io';

import 'package:anibee/models.dart';
import 'package:anibee/screens/downloads_screen.dart';
import 'package:anibee/services/download_service.dart';
import 'package:anibee/services/miruro_resolver.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.5: real offline downloads. Pure playlist parsing is unit-tested
/// directly; the end-to-end flow (master -> variant -> segments ->
/// local playlist, resume after a failure, direct-file Range resume)
/// runs against a MockClient with a repo-local temp dir (NOT /tmp —
/// the VM's /tmp tmpfs is full).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  setUp(() async {
    tempDir = Directory('${Directory.current.path}/.tmp-downloads-test');
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    await tempDir.create(recursive: true);
  });

  tearDownAll(() async {
    final Directory dir = Directory(
      '${Directory.current.path}/.tmp-downloads-test',
    );
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  const String masterBody =
      '#EXTM3U\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080\n'
      'v1080.m3u8\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720\n'
      'v720.m3u8\n'
      '#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=854x480\n'
      'v480.m3u8\n';

  const String mediaBody =
      '#EXTM3U\n'
      '#EXT-X-VERSION:3\n'
      '#EXT-X-TARGETDURATION:6\n'
      '#EXT-X-KEY:METHOD=AES-128,URI="key.key"\n'
      '#EXTINF:6.0,\n'
      'seg0.ts\n'
      '#EXTINF:6.0,\n'
      'seg1.ts\n'
      '#EXTINF:6.0,\n'
      'seg2.ts\n'
      '#EXT-X-ENDLIST\n';

  // Distinct anime per test: the mock prefs are shared across the
  // tests in this file, so each download needs its own key.
  Anime dlAnime(String id, int anilistId) {
    return Anime(
      id: id,
      anilistId: anilistId,
      title: 'Download Test Anime',
      rating: 4.0,
      year: 2024,
      episodeCount: 12,
      genres: <String>['Action'],
      synopsis: 'Test anime for downloads.',
      gradient: const <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    );
  }

  const Anime anime = Anime(
    id: 'dl-test',
    anilistId: 999021,
    title: 'Download Test Anime',
    rating: 4.0,
    year: 2024,
    episodeCount: 12,
    genres: <String>['Action'],
    synopsis: 'Test anime for downloads.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
  );

  ResolvedStream hlsStream({List<SubtitleInfo> subtitles = const []}) {
    return ResolvedStream(
      url: 'https://cdn.example.com/master.m3u8',
      label: 'Miruro 1080p',
      source: 'Miruro',
      headers: const <String, String>{'Referer': 'https://example.com/'},
      subtitles: subtitles,
    );
  }

  MockClient hlsClient(Map<String, int> counts, {bool failSeg1 = false}) {
    return MockClient((http.Request request) async {
      final String url = request.url.toString();
      counts[url] = (counts[url] ?? 0) + 1;
      if (url.endsWith('master.m3u8')) return http.Response(masterBody, 200);
      if (url.endsWith('v1080.m3u8')) return http.Response(mediaBody, 200);
      if (url.endsWith('v720.m3u8')) return http.Response(mediaBody, 200);
      if (url.endsWith('v480.m3u8')) return http.Response(mediaBody, 200);
      if (url.endsWith('key.key')) {
        return http.Response.bytes(<int>[1, 2, 3, 4], 200);
      }
      if (url.endsWith('seg1.ts') && failSeg1) {
        throw http.ClientException('boom', Uri.parse(url));
      }
      if (url.endsWith('.ts')) {
        return http.Response.bytes(<int>[0, 1, 2, 3, 4, 5], 200);
      }
      if (url.endsWith('.vtt')) {
        return http.Response('WEBVTT\n\n00:00.000 --> 00:01.000\nHi', 200);
      }
      return http.Response('not found', 404);
    });
  }

  test('pickVariant matches the download quality', () {
    final List<HlsVariant> variants = DownloadService.parseMasterPlaylist(
      masterBody,
    );
    expect(variants.length, 3);
    expect(DownloadService.pickVariant(variants, '1080p')?.height, 1080);
    expect(DownloadService.pickVariant(variants, '720p')?.height, 720);
    expect(DownloadService.pickVariant(variants, '480p')?.height, 480);
    // A quality above the best available still picks the best.
    expect(DownloadService.pickVariant(variants, '2160p')?.height, 1080);
  });

  test('parseMediaPlaylist finds segments, durations and keys', () {
    final HlsMediaPlaylist pl = DownloadService.parseMediaPlaylist(mediaBody);
    expect(pl.segments.length, 3);
    expect(pl.segments[0].uri, 'seg0.ts');
    expect(pl.segments[0].duration, 6.0);
    expect(pl.keyUris, <String>['key.key']);
    expect(pl.mapUris, isEmpty);
  });

  test('buildLocalPlaylist rewrites remote URIs to local files', () {
    final String local = DownloadService.buildLocalPlaylist(
      mediaBody,
      segmentFile: (int i, String uri) =>
          'seg${i.toString().padLeft(6, '0')}.ts',
      keyFile: (String uri) => 'key0.key',
      mapFile: (String uri) => uri,
    );
    expect(local, contains('seg000000.ts'));
    expect(local, contains('seg000002.ts'));
    expect(local, contains('URI="key0.key"'));
    expect(local, isNot(contains('seg0.ts\n')));
    expect(local, contains('#EXT-X-ENDLIST'));
  });

  // NOTE: plain test(), NOT testWidgets + tester.runAsync — the
  // runAsync form deadlocks this flow (the service awaits mock
  // SharedPreferences channel calls that never complete inside the
  // testWidgets fake-async zone); the direct await completes in ms
  // (verified with a scratch test). The service itself is unchanged.
  test('HLS download runs to 100% and plays offline', () async {
    final SettingsStore store = await SettingsStore.load();
    final Map<String, int> counts = <String, int>{};
    final DownloadService service = DownloadService(
      client: hlsClient(counts),
      baseDirOverride: tempDir,
    );
    final List<Episode> eps = mockEpisodes(anime);
    await service.startDownload(
      anime: anime,
      episode: eps[0],
      stream: hlsStream(
        subtitles: const <SubtitleInfo>[
          SubtitleInfo(label: 'English', url: 'https://cdn.example.com/en.vtt'),
        ],
      ),
      store: store,
    );

    const String key = 'dl-test:1';
    expect(store.downloadStatus[key], 'downloaded');
    expect(store.downloadProgress[key], 1.0);
    // The 1080p variant was picked (quality setting), not 720/480.
    expect(counts['https://cdn.example.com/v1080.m3u8'], 1);
    expect(counts['https://cdn.example.com/v720.m3u8'], isNull);
    final File playlist = File(
      '${tempDir.path}/downloads/dl-test_1/playlist.m3u8',
    );
    expect(await playlist.exists(), isTrue);
    final String local = await playlist.readAsString();
    expect(local, contains('seg000000.ts'));
    expect(local, contains('URI="key0.key"'));
    expect(local, isNot(contains('cdn.example.com')));
    expect(
      await File('${tempDir.path}/downloads/dl-test_1/seg000001.ts').exists(),
      isTrue,
    );
    expect(
      await File('${tempDir.path}/downloads/dl-test_1/key0.key').exists(),
      isTrue,
    );
    expect(
      await File('${tempDir.path}/downloads/dl-test_1/sub0.vtt').exists(),
      isTrue,
    );
    // Offline playback: a file:// playlist with local subtitles.
    final ResolvedStream? offline = service.localStreamFor(key, store);
    expect(offline, isNotNull);
    expect(offline!.url, startsWith('file://'));
    expect(offline.url, endsWith('playlist.m3u8'));
    expect(offline.subtitles.length, 1);
    expect(offline.subtitles.first.url, startsWith('file://'));
  });

  test('interrupted download resumes without re-fetching', () async {
    final SettingsStore store = await SettingsStore.load();
    final Map<String, int> counts = <String, int>{};
    final Anime anime = dlAnime('dl-test-resume', 999022);
    final List<Episode> eps = mockEpisodes(anime);
    const String key = 'dl-test-resume:1';

    // First run: segment 1 fails (after its 3 retries) -> 'failed',
    // segment 0 stays on disk.
    DownloadService service = DownloadService(
      client: hlsClient(counts, failSeg1: true),
      baseDirOverride: tempDir,
    );
    await service.startDownload(
      anime: anime,
      episode: eps[0],
      stream: hlsStream(),
      store: store,
    );
    expect(store.downloadStatus[key], 'failed');
    expect(
      await File('${tempDir.path}/downloads/dl-test-resume_1/seg000000.ts')
          .exists(),
      isTrue,
    );
    expect(
      await File('${tempDir.path}/downloads/dl-test-resume_1/seg000001.ts')
          .exists(),
      isFalse,
    );
    expect(counts['https://cdn.example.com/seg0.ts'], 1);
    expect(counts['https://cdn.example.com/seg1.ts'], 3);

    // Second run, healthy client: resumes — seg0 is NOT re-fetched.
    service = DownloadService(
      client: hlsClient(counts),
      baseDirOverride: tempDir,
    );
    await service.startDownload(
      anime: anime,
      episode: eps[0],
      stream: hlsStream(),
      store: store,
    );
    expect(store.downloadStatus[key], 'downloaded');
    expect(counts['https://cdn.example.com/seg0.ts'], 1);
    expect(counts['https://cdn.example.com/seg1.ts'], 4);
    expect(counts['https://cdn.example.com/seg2.ts'], 1);
  });

  test('direct-file download streams to disk with Range resume', () async {
    final SettingsStore store = await SettingsStore.load();
    final Anime anime = dlAnime('dl-test-file', 999023);
    final List<int> bytes = List<int>.generate(1024, (int i) => i % 256);
    final MockClient client = MockClient((http.Request request) async {
      final String? range = request.headers['Range'];
      if (range == 'bytes=512-') {
        return http.Response.bytes(
          bytes.sublist(512),
          206,
          headers: <String, String>{'content-length': '512'},
        );
      }
      return http.Response.bytes(
        bytes,
        200,
        headers: <String, String>{'content-length': '1024'},
      );
    });
    final DownloadService service = DownloadService(
      client: client,
      baseDirOverride: tempDir,
    );
    final List<Episode> eps = mockEpisodes(anime);
    const String key = 'dl-test-file:1';
    await service.startDownload(
      anime: anime,
      episode: eps[0],
      stream: const ResolvedStream(
        url: 'https://files.example.com/ep1.mp4',
        label: 'TorBox 1080p',
        source: 'TorBox',
      ),
      store: store,
    );
    expect(store.downloadStatus[key], 'downloaded');
    final File file = File(
      '${tempDir.path}/downloads/dl-test-file_1/episode.mp4',
    );
    expect(await file.exists(), isTrue);
    expect(await file.length(), 1024);
    final ResolvedStream? offline = service.localStreamFor(key, store);
    expect(offline, isNotNull);
    expect(offline!.url, endsWith('episode.mp4'));
  });

  test('localStreamFor is null without a download', () async {
    final SettingsStore store = await SettingsStore.load();
    final DownloadService service = DownloadService(baseDirOverride: tempDir);
    expect(service.localStreamFor('dl-test:9', store), isNull);
  });

  testWidgets('tapping a downloaded row plays it offline', (
    WidgetTester tester,
  ) async {
    final SettingsStore store = await SettingsStore.load();
    // Distinct key/title: the mock prefs are shared across the tests
    // in this file, so the HLS/resume/file tests' 'Download Test
    // Anime' rows are still listed here too.
    const String key = 'dl-test-tap:1';
    await store.setDownloadRecord(key, <String, dynamic>{
      'animeId': 'dl-test-tap',
      'anilistId': 999024,
      'title': 'Tap Test Anime',
      'posterUrl': null,
      'episodeCount': 12,
      'episode': 1,
      'kind': 'hls',
      'localPath': '${tempDir.path}/downloads/dl-test-tap_1/playlist.m3u8',
    });
    await store.setDownloadStatus(key, 'downloaded');

    final List<String> tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: DownloadsScreen(store: store, onPlayDownload: tapped.add),
      ),
    );
    await tester.pump();

    expect(find.text('Tap Test Anime'), findsOneWidget);
    expect(find.textContaining('Ready offline'), findsWidgets);
    await tester.tap(find.text('Tap Test Anime'));
    await tester.pump();
    expect(tapped, <String>[key]);
  });
}
