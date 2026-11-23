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

/// 0.2.17: pinned Detail header (user report 2026-11-24 03:26,
/// screen-recording video): scrolling the episodes scrolled the
/// WHOLE page — banner, title, synopsis and server picker all flew
/// away. Now only the episode list scrolls; the header (banner,
/// title, PLAY, My List, synopsis, server picker, EPISODES header
/// + sort/eye/grid controls) stays FIXED, in BOTH layouts (cards
/// and the 5-column number grid). The "Episode 9 in ..." airing
/// banner rides at the bottom of the scrolling list.
///
/// Harness copied from detail_airing_test.dart, but on a PHONE
/// surface (390x844) — the list must actually need scrolling, or
/// the test proves nothing (the airing harness uses 800x3000).
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

  const Anime longAnime = Anime(
    id: 'one-piece',
    title: 'One Piece',
    rating: 4.5,
    year: 1999,
    episodeCount: 1180,
    genres: <String>['Action'],
    synopsis: 'Pirates chase the legendary treasure.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
  );

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

  Future<void> pumpDetail(WidgetTester tester, Anime anime) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          services: servicesFor(mockAnilist()),
          player: trailer,
        ),
      ),
    );
    await tester.pump();
    // _loadDetails resolves the id by title; the mock returns
    // {"data":{}} (a failure) so the 0.2.13 search retry's 300 ms
    // Timer must be pumped past before teardown.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  testWidgets('cards: scrolling episodes keeps the header fixed', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, airingNow);

    // Header + first card visible before scrolling.
    expect(find.text('Black Clover Season 2'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.text('EPISODES'), findsOneWidget);
    expect(find.text('EP 1'), findsOneWidget);
    // The airing banner is at the bottom of the list — not built
    // yet on a phone-size viewport (ListView is lazy).
    expect(find.text('Episode 9 in 6d 20h · Nov 29 at 22:05'), findsNothing);

    // Scroll the episode list to the bottom — scrollUntilVisible
    // steps the list until the banner (at the very bottom, lazily
    // built) comes into view. The scrollable is the Scrollable the
    // ListView builds (a ListView is NOT itself a Scrollable —
    // passing find.byType(ListView) throws a TypeError).
    await tester.scrollUntilVisible(
      find.text('Episode 9 in 6d 20h · Nov 29 at 22:05'),
      300,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();

    // Header is STILL on screen; EP 1 scrolled away; the airing
    // banner rode to the bottom of the list and is now visible.
    expect(find.text('Black Clover Season 2'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.text('EPISODES'), findsOneWidget);
    expect(find.text('EP 1'), findsNothing);
    expect(find.text('Episode 9 in 6d 20h · Nov 29 at 22:05'), findsOneWidget);
  });

  testWidgets('grid: scrolling the number grid keeps the header fixed', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, longAnime);

    // Grid mode (1180 episodes): range label + first cell visible.
    expect(find.text('One Piece'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.text('EPISODES'), findsOneWidget);
    expect(find.text('001-100'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // Scroll the grid down. (A shrink-wrapped grid builds ALL its
    // cells, so "cell gone" can't prove scrolling — compare rects
    // instead: the cell must move up while the title stays put.)
    final Offset titleBefore = tester.getTopLeft(find.text('One Piece'));
    final double cellBefore = tester.getTopLeft(find.text('1')).dy;
    await tester.drag(find.text('1'), const Offset(0, -300));
    await tester.pump();
    await tester.pump();
    final Offset titleAfter = tester.getTopLeft(find.text('One Piece'));
    final double cellAfter = tester.getTopLeft(find.text('1')).dy;

    // Header still on screen, unmoved; the grid scrolled up.
    expect(find.text('One Piece'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.text('EPISODES'), findsOneWidget);
    expect(find.text('001-100'), findsOneWidget);
    expect(titleAfter, titleBefore);
    expect(cellBefore - cellAfter, greaterThan(200));
  });
}
