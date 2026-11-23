import 'dart:convert';

import 'package:anibee/models.dart';
import 'package:anibee/services/anilist_service.dart';
import 'package:anibee/settings_store.dart';
import 'package:anibee/widgets/episode_list.dart';
import 'package:anibee/widgets/poster.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.9 per-episode thumbnails: AniList `streamingEpisodes` gives
/// each episode its own thumbnail; the card falls back to the anime
/// poster only when AniList has none. Never faked, never derived.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // SettingsStore.load() reads secrets from flutter_secure_storage —
    // an unmocked channel call never completes in flutter_test and
    // the test hangs forever (seen 2026-11-23).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });
  group('matchEpisodeThumbnails', () {
    test('numbered titles map to their episode number', () {
      final Map<int, String> got = AniListService.matchEpisodeThumbnails(
        <Map<String, dynamic>>[
          <String, dynamic>{'title': 'Episode 1', 'thumbnail': 't1.jpg'},
          <String, dynamic>{'title': 'Episode 2', 'thumbnail': 't2.jpg'},
          <String, dynamic>{'title': 'Ep. 12', 'thumbnail': 't12.jpg'},
          <String, dynamic>{'title': '12', 'thumbnail': 't12b.jpg'},
        ],
        episodeCount: 24,
      );
      expect(got, <int, String>{1: 't1.jpg', 2: 't2.jpg', 12: 't12.jpg'});
    });

    test('unnumbered titles fill the lowest unclaimed numbers in order', () {
      final Map<int, String> got = AniListService.matchEpisodeThumbnails(
        <Map<String, dynamic>>[
          <String, dynamic>{'title': 'Episode 1', 'thumbnail': 't1.jpg'},
          <String, dynamic>{'title': 'The Beginning', 'thumbnail': 'u1.jpg'},
          <String, dynamic>{'title': 'A New Power', 'thumbnail': 'u2.jpg'},
        ],
        episodeCount: 5,
      );
      expect(got, <int, String>{1: 't1.jpg', 2: 'u1.jpg', 3: 'u2.jpg'});
    });

    test('missing or empty thumbnails are skipped', () {
      final Map<int, String> got = AniListService.matchEpisodeThumbnails(
        <Map<String, dynamic>>[
          <String, dynamic>{'title': 'Episode 1', 'thumbnail': null},
          <String, dynamic>{'title': 'Episode 2', 'thumbnail': ''},
          <String, dynamic>{'title': 'Episode 3', 'thumbnail': 't3.jpg'},
        ],
        episodeCount: 3,
      );
      expect(got, <int, String>{3: 't3.jpg'});
    });

    test('out-of-range numbers are ignored, first entry wins a duplicate', () {
      final Map<int, String> got = AniListService.matchEpisodeThumbnails(
        <Map<String, dynamic>>[
          <String, dynamic>{'title': 'Episode 99', 'thumbnail': 'far.jpg'},
          <String, dynamic>{'title': 'Episode 1', 'thumbnail': 'first.jpg'},
          <String, dynamic>{'title': 'Episode 1', 'thumbnail': 'dup.jpg'},
        ],
        episodeCount: 12,
      );
      expect(got, <int, String>{1: 'first.jpg'});
    });
  });

  group('fetchEpisodeThumbnails', () {
    test('parses streamingEpisodes from the GraphQL response', () async {
      final MockClient client = MockClient((http.Request req) async {
        expect(req.url.toString(), AniListService.graphqlUrl);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'data': <String, dynamic>{
              'Media': <String, dynamic>{
                'streamingEpisodes': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'title': 'Episode 1',
                    'thumbnail': 'https://img.example.com/ep1.jpg',
                    'url': 'https://site.example.com/e1',
                    'site': 'Crunchyroll',
                  },
                  <String, dynamic>{
                    'title': 'Episode 2',
                    'thumbnail': null,
                    'url': 'https://site.example.com/e2',
                    'site': 'Crunchyroll',
                  },
                ],
              },
            },
          }),
          200,
        );
      });
      final AniListService svc = AniListService(client: client);
      final Map<int, String> got = await svc.fetchEpisodeThumbnails(
        114129,
        episodeCount: 47,
      );
      expect(got, <int, String>{1: 'https://img.example.com/ep1.jpg'});
    });

    test('returns empty on failure', () async {
      final MockClient client = MockClient(
        (http.Request req) async => http.Response('oops', 500),
      );
      final AniListService svc = AniListService(client: client);
      expect(await svc.fetchEpisodeThumbnails(1), isEmpty);
    });
  });

  group('EpisodeSection cards', () {
    testWidgets('card with thumbnailUrl shows it, without shows poster', (
      WidgetTester tester,
    ) async {
      // Unroutable localhost URLs: the connection is REFUSED
      // instantly, so Image.network fails fast into its
      // errorBuilder (poster fallback) instead of hanging on a
      // real request — external hosts stall behind this VM's
      // egress proxy and a real URL hangs the test (seen 2026-11-23:
      // the widget test never completed with example.com URLs).
      // The Image WIDGETS are still in the tree, which is what the
      // assertions below check.
      const String thumbUrl = 'http://127.0.0.1:9/ep1.jpg';
      const String posterUrl = 'http://127.0.0.1:9/poster.jpg';
      const Anime anime = Anime(
        id: 'thumb-test',
        title: 'Thumbnail Test',
        rating: 4.0,
        year: 2024,
        episodeCount: 3,
        genres: <String>['Action'],
        synopsis: 'Test anime for episode thumbnails.',
        posterUrl: posterUrl,
        gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
      );
      final SettingsStore store = await SettingsStore.load();
      final List<Episode> eps = mockEpisodes(anime)
          .map(
            (Episode e) =>
                e.number == 1 ? e.copyWith(thumbnailUrl: thumbUrl) : e,
          )
          .toList();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 800,
              child: EpisodeSection(
                anime: anime,
                episodes: eps,
                store: store,
                onPlay: (_) {},
                onToggleDownload: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Exactly one episode thumbnail image (EP 1's own thumbnail).
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Image &&
              w.image is NetworkImage &&
              (w.image as NetworkImage).url == thumbUrl,
        ),
        findsOneWidget,
      );
      // Every card still carries the poster underneath as the
      // fallback (3 cards → 3 poster images).
      expect(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Image &&
              w.image is NetworkImage &&
              (w.image as NetworkImage).url == posterUrl,
        ),
        findsNWidgets(3),
      );
      expect(find.byType(PosterArt), findsNWidgets(3));
      expect(find.text('EP 1'), findsOneWidget);
      expect(find.text('EP 2'), findsOneWidget);
    });
  });
}
