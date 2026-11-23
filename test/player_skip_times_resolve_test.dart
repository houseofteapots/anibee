import 'dart:convert';

import 'package:anibee/services/anilist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'player_skip_times_harness.dart';

/// 0.2.9 Skip Intro: a title with no ids resolves via AniList,
/// then fetches. Real libmpv + real 5 s video-only clip.
/// One media test per file (see the harness comment).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(configureSkipTestBindings);

  testWidgets('title with no ids resolves via AniList, then fetches', (
    WidgetTester tester,
  ) async {
    Map<String, dynamic> mediaJson() => <String, dynamic>{
      'id': 21459,
      'idMal': 31964,
      'title': <String, dynamic>{
        'romaji': 'My Hero Academia',
        'english': 'My Hero Academia',
      },
      'coverImage': <String, dynamic>{
        'large': 'https://cdn.example.com/large.jpg',
        'extraLarge': 'https://cdn.example.com/xl.jpg',
      },
      'format': 'TV',
      'episodes': 138,
      'seasonYear': 2016,
      'averageScore': 80,
      'genres': <String>['Action'],
      'description': 'A hero rises.',
    };
    final AniListService anilist = AniListService(
      client: MockClient((http.Request req) async {
        final String body = req.body;
        if (body.contains('Media(id:')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'data': <String, dynamic>{'Media': mediaJson()},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'data': <String, dynamic>{
              'Page': <String, dynamic>{
                'media': <Object>[mediaJson()],
              },
            },
          }),
          200,
        );
      }),
    );
    final SkipPlayerHarness h = SkipPlayerHarness();
    await h.pumpPlayer(
      tester,
      anime: mhaNoIds,
      aniSkip: h.recordingSkipService(),
      anilist: anilist,
    );
    // No ids at all, no media yet: nothing sent, fetch deferred.
    expect(h.skipRequests, isEmpty);
    expect(h.playerState(tester).skipTimesAwaitingDurationForTest, isTrue);
    await h.openTestClip(tester);
    expect(await h.waitForSkip(tester), isTrue);
    expect(h.skipRequests.length, 1);
    // Resolved by title: AniList 21459 -> MAL 31964.
    expect(h.skipRequests.first.url.path, '/v2/skip-times/31964/1');
    expect(h.skipRequests.first.url.queryParameters['episodeLength'], '5');
    await h.disposePlayer(tester);
  });
}
