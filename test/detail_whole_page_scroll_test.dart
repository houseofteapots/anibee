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

/// 0.2.18: the 0.2.17 pinned Detail header is REVERTED (user:
/// "episode scroll pehle jesa banado"). The whole page scrolls
/// again (0.2.16 behavior) — banner, title, PLAY, My List,
/// synopsis, server picker and EPISODES header scroll AWAY with
/// the episode list; nothing stays fixed. In BOTH layouts (cards
/// and the 5-column number grid). The "Episode 9 in ..." airing
/// banner rides at the bottom of the page, below the episodes.
///
/// Harness copied from the deleted detail_pinned_header_test.dart
/// (0.2.17), on a PHONE surface (390x844) — the page must actually
/// need scrolling, or the test proves nothing.
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

  testWidgets('cards: scrolling the page scrolls the header away', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, airingNow);

    // Header + first card visible before scrolling.
    expect(find.text('Black Clover Season 2'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.text('EPISODES'), findsOneWidget);
    expect(find.text('EP 1'), findsOneWidget);

    // One drag up: the WHOLE page moves — title, PLAY and EP 1
    // all move up together (nothing is pinned).
    final double titleBefore =
        tester.getTopLeft(find.text('Black Clover Season 2')).dy;
    final double ep1Before = tester.getTopLeft(find.text('EP 1')).dy;
    final double bannerBefore = tester
        .getTopLeft(find.text('Episode 9 in 6d 20h · Nov 29 at 22:05'))
        .dy;
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.pump();
    final double titleAfter =
        tester.getTopLeft(find.text('Black Clover Season 2')).dy;
    final double ep1After = tester.getTopLeft(find.text('EP 1')).dy;
    final double bannerAfter = tester
        .getTopLeft(find.text('Episode 9 in 6d 20h · Nov 29 at 22:05'))
        .dy;
    expect(titleAfter, lessThan(titleBefore));
    expect(ep1After, lessThan(ep1Before));
    expect(bannerAfter, lessThan(bannerBefore));

    // Keep scrolling to the bottom: the header scrolls fully off
    // the top (the ListView destroys it — findsNothing), and the
    // airing banner (bottom of the page) comes into view.
    for (int i = 0; i < 6; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
    }
    await tester.pump();
    expect(find.text('Black Clover Season 2'), findsNothing);
    final double bannerDy = tester
        .getTopLeft(find.text('Episode 9 in 6d 20h · Nov 29 at 22:05'))
        .dy;
    expect(bannerDy, greaterThanOrEqualTo(0));
    expect(bannerDy, lessThan(844));
  });

  testWidgets('grid: scrolling the page scrolls the header away', (
    WidgetTester tester,
  ) async {
    await pumpDetail(tester, longAnime);

    // Grid mode (1180 episodes): range label + first cell visible.
    expect(find.text('One Piece'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
    expect(find.text('EPISODES'), findsOneWidget);
    expect(find.text('001-100'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    // One drag up: title and the grid move up together — the
    // header is NOT pinned.
    final Offset titleBefore = tester.getTopLeft(find.text('One Piece'));
    final double cellBefore = tester.getTopLeft(find.text('1')).dy;
    await tester.drag(find.text('1'), const Offset(0, -300));
    await tester.pump();
    await tester.pump();
    final Offset titleAfter = tester.getTopLeft(find.text('One Piece'));
    final double cellAfter = tester.getTopLeft(find.text('1')).dy;
    expect(titleAfter.dy, lessThan(titleBefore.dy));
    expect(cellAfter, lessThan(cellBefore));

    // Scroll further: the title leaves the screen entirely (the
    // ListView destroys it once it is far off-screen).
    for (int i = 0; i < 4; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
    }
    await tester.pump();
    expect(find.text('One Piece'), findsNothing);
  });
}
