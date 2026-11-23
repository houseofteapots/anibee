import 'dart:convert';

import 'package:anibee/models.dart';
import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/screens/detail_screen.dart';
import 'package:anibee/services/airing_notifications.dart';
import 'package:anibee/services/airing_service.dart';
import 'package:anibee/services/anilist_service.dart';
import 'package:anibee/services/app_services.dart';
import 'package:anibee/services/debrid_service.dart';
import 'package:anibee/services/download_service.dart';
import 'package:anibee/services/miruro_resolver.dart';
import 'package:anibee/services/oauth_service.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.13 airing Detail: the 0.2.12 phone test showed the generic
/// "No episodes available yet" on Black Clover Season 2 (and the
/// follow-up: NO airing title showed episodes at all) — the airing
/// info never reached Detail, PLAY sat on a 0-episode title, and
/// the synopsis was blank. Now: aired episodes (next EP - 1) show,
/// the upcoming EP + air date show, PLAY hides while nothing has
/// aired, and Detail fetches the missing synopsis/aired count
/// itself via mediaById.
///
/// Harness copied from detail_season_selector_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    MediaKit.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.alexmercerind/media_kit_video'),
      (MethodCall call) async {
        if (call.method == 'VideoOutputManager.Create') {
          final Map<Object?, Object?> args =
              call.arguments as Map<Object?, Object?>;
          final int handle = int.parse(args['handle'] as String);
          await messenger.handlePlatformMessage(
            'com.alexmercerind/media_kit_video',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('VideoOutput.Resize', <String, Object>{
                'handle': handle,
                'rect': <String, Object>{
                  'left': 0.0,
                  'top': 0.0,
                  'width': 800.0,
                  'height': 600.0,
                },
                'id': 1,
              }),
            ),
            null,
          );
        }
        return null;
      },
    );
  });

  const Anime unreleased = Anime(
    id: 'unreleased-season',
    title: 'Unreleased Season',
    rating: 0,
    year: 2026,
    episodeCount: 0,
    genres: <String>['Action'],
    synopsis: '',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
  );

  const Anime airingNow = Anime(
    id: 'anilist-97940',
    title: 'Black Clover Season 2',
    rating: 0,
    year: 2026,
    episodeCount: 8,
    genres: <String>['Action'],
    synopsis: '',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    anilistId: 97940,
    nextEpisode: 9,
    nextEpisodeIn: '6d 20h',
    nextEpisodeAt: 'Nov 29 at 22:05',
  );

  /// Mock AniList: search resolves nothing; Media(id:97940) is a
  /// still-airing series (episodes null, next EP 9, description).
  AniListService mockAnilist() {
    return AniListService(
      client: MockClient((http.Request req) async {
        final String body = req.body;
        if (body.contains('Media(id:97940')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'data': <String, dynamic>{
                'Media': <String, dynamic>{
                  'id': 97940,
                  'idMal': null,
                  'title': <String, dynamic>{
                    'romaji': 'Black Clover Season 2',
                    'english': 'Black Clover Season 2',
                  },
                  'format': 'TV',
                  'episodes': null,
                  'seasonYear': 2026,
                  'description': 'Asta returns for a new season.',
                  'nextAiringEpisode': <String, dynamic>{
                    'episode': 9,
                    'airingAt': 1795739100,
                  },
                  'genres': <String>['Action'],
                  'averageScore': 80,
                },
              },
            }),
            200,
          );
        }
        return http.Response('{"data":{}}', 200);
      }),
    );
  }

  AppServices servicesFor(AniListService anilist) {
    return AppServices(
      anilist: anilist,
      miruro: MiruroResolver(anilist: anilist),
      debrid: DebridService(),
      oauth: OAuthService(),
      downloads: DownloadService(),
      airing: AiringService(anilist: anilist),
      airingNotifications: AiringNotifications(),
    );
  }

  Future<void> pumpDetail(
    WidgetTester tester,
    Anime anime,
    AppServices services,
  ) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final SettingsStore store = await SettingsStore.load();
    late TrailerPlayer trailer;
    await tester.runAsync(() async {
      trailer = TrailerPlayer();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          anime: anime,
          store: store,
          services: services,
          player: trailer,
        ),
      ),
    );
    await tester.pump();
  }

  /// Pump until [text] appears (async loads settle) or give up.
  Future<void> waitFor(WidgetTester tester, String text) async {
    for (int i = 0; i < 20; i++) {
      if (find.text(text).evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
    }
  }

  testWidgets('unreleased season: no PLAY, generic empty state',
      (WidgetTester tester) async {
    await pumpDetail(tester, unreleased, servicesFor(mockAnilist()));
    // _loadDetails resolves the id by title; the mock returns
    // {"data":{}} (a failure now) so the 0.2.13 search retry's
    // 300 ms Timer must be pumped past before teardown, or the
    // test fails with a pending Timer.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('PLAY'), findsNothing);
    expect(find.text('No episodes yet'), findsOneWidget);
    expect(find.text('No episodes available yet'), findsOneWidget);
  });

  testWidgets('airing season: 8 aired episodes + upcoming banner + PLAY',
      (WidgetTester tester) async {
    await pumpDetail(tester, airingNow, servicesFor(mockAnilist()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.text('8 Episodes'), findsOneWidget);
    expect(
      find.text('Episode 9 in 6d 20h · Nov 29 at 22:05'),
      findsOneWidget,
    );
    expect(find.text('No episodes available yet'), findsNothing);
  });

  testWidgets('_loadDetails fills synopsis + aired count from mediaById',
      (WidgetTester tester) async {
    // Opens with 0 episodes + blank synopsis (the AIRING SOON
    // pre-0.2.13 shape); the media fetch fills both in.
    const Anime bare = Anime(
      id: 'anilist-97940',
      title: 'Black Clover Season 2',
      rating: 0,
      year: 2026,
      episodeCount: 0,
      genres: <String>['Action'],
      synopsis: '',
      gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
      anilistId: 97940,
    );
    await pumpDetail(tester, bare, servicesFor(mockAnilist()));
    await waitFor(tester, '8 Episodes');
    expect(find.text('8 Episodes'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.text('Asta returns for a new season.'), findsOneWidget);
    // Aired list + the upcoming-EP countdown bar (exact countdown
    // depends on "now", so match the prefix only).
    expect(find.textContaining('Episode 9 in'), findsOneWidget);
  });
}
