import 'dart:convert';

import 'package:anibee/services/kitsu_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 0.2.15: Kitsu is the search fallback — AniList's `search:` query
/// returns an EMPTY media list on the user's phone ("noblesse" →
/// "ok · 0 from AniList"), and AniList is Cloudflare-blocked from
/// the VM, so the fallback must be verified against Kitsu's real
/// response shape (verified live from the VM for noblesse / black
/// clover / the garden of words, each with a direct `anilist/anime`
/// mapping in the same response via `include=mappings`).
void main() {
  /// One Kitsu entry, real ids from the live probe: Noblesse is
  /// Kitsu 43019 → AniList 116005, MAL 41345.
  Map<String, dynamic> noblesseEntry() {
    return <String, dynamic>{
      'id': '43019',
      'type': 'anime',
      'attributes': <String, dynamic>{
        'canonicalTitle': 'Noblesse',
        // Kitsu sends averageRating as a STRING ("69.23"), not a number.
        'averageRating': '69.23',
        'episodeCount': 13,
        'startDate': '2020-10-07',
        'showType': 'TV',
        'synopsis': 'A noble vampire awakens after 820 years.',
        'posterImage': <String, dynamic>{
          'large':
              'https://media.kitsu.app/anime/poster_images/43019/large.jpg',
          'medium':
              'https://media.kitsu.app/anime/poster_images/43019/medium.jpg',
        },
      },
      'relationships': <String, dynamic>{
        'mappings': <String, dynamic>{
          'data': <dynamic>[
            <String, dynamic>{'id': 'm-anilist', 'type': 'mappings'},
            <String, dynamic>{'id': 'm-mal', 'type': 'mappings'},
          ],
        },
      },
    };
  }

  Map<String, dynamic> noblesseResponse() {
    return <String, dynamic>{
      'data': <dynamic>[noblesseEntry()],
      'included': <dynamic>[
        <String, dynamic>{
          'id': 'm-anilist',
          'type': 'mappings',
          'attributes': <String, dynamic>{
            'externalSite': 'anilist/anime',
            'externalId': '116005',
          },
        },
        <String, dynamic>{
          'id': 'm-mal',
          'type': 'mappings',
          'attributes': <String, dynamic>{
            'externalSite': 'myanimelist/anime',
            'externalId': '41345',
          },
        },
      ],
    };
  }

  group('KitsuSearch.parseSearchResults', () {
    test('parses Noblesse with a direct AniList mapping', () {
      final parsed = KitsuSearch.parseSearchResults(noblesseResponse());
      expect(parsed.dropped, 0);
      expect(parsed.results.length, 1);
      final anime = parsed.results.first;
      expect(anime.title, 'Noblesse');
      expect(anime.anilistId, 116005);
      expect(anime.malId, 41345);
      expect(anime.id, 'anilist-116005');
      expect(anime.episodeCount, 13);
      expect(anime.year, 2020);
      // 69.23 / 20, same 0–5 scale as animeFromMedia.
      expect(anime.rating, closeTo(3.46, 0.01));
      expect(
        anime.posterUrl,
        'https://media.kitsu.app/anime/poster_images/43019/large.jpg',
      );
    });

    test('drops entries with no AniList mapping (never fake playable)',
        () {
      final Map<String, dynamic> json = noblesseResponse();
      (json['data'] as List<dynamic>).add(<String, dynamic>{
        'id': '99999',
        'type': 'anime',
        'attributes': <String, dynamic>{
          'canonicalTitle': 'Unmapped Title',
          'episodeCount': 12,
          'showType': 'TV',
        },
        'relationships': <String, dynamic>{
          'mappings': <String, dynamic>{'data': <dynamic>[]},
        },
      });
      final parsed = KitsuSearch.parseSearchResults(json);
      expect(parsed.results.length, 1);
      expect(parsed.results.first.title, 'Noblesse');
      expect(parsed.dropped, 1);
    });

    test('movie with null episodeCount forces 1 episode', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{
            'id': '7905',
            'type': 'anime',
            'attributes': <String, dynamic>{
              'canonicalTitle': 'The Garden of Words',
              'averageRating': '81.35',
              'episodeCount': null,
              'startDate': '2013-05-31',
              'showType': 'movie',
              'synopsis': 'A rainy-day meeting.',
            },
            'relationships': <String, dynamic>{
              'mappings': <String, dynamic>{
                'data': <dynamic>[
                  <String, dynamic>{'id': 'm-gow', 'type': 'mappings'},
                ],
              },
            },
          },
        ],
        'included': <dynamic>[
          <String, dynamic>{
            'id': 'm-gow',
            'type': 'mappings',
            'attributes': <String, dynamic>{
              'externalSite': 'anilist/anime',
              'externalId': '16782',
            },
          },
        ],
      };
      final parsed = KitsuSearch.parseSearchResults(json);
      expect(parsed.results.length, 1);
      expect(parsed.results.first.anilistId, 16782);
      expect(parsed.results.first.episodeCount, 1);
    });

    test('wrong-shaped bodies parse to empty, never throw', () {
      expect(
        KitsuSearch.parseSearchResults(<String, dynamic>{}).results,
        isEmpty,
      );
      expect(
        KitsuSearch.parseSearchResults(
          <String, dynamic>{'data': 'not-a-list'},
        ).results,
        isEmpty,
      );
    });
  });

  group('KitsuSearch.search', () {
    test('hits kitsu.io with the right params and parses', () async {
      Uri? seenUri;
      final result = await KitsuSearch.search(
        'noblesse',
        client: MockClient((http.Request req) async {
          seenUri = req.url;
          return http.Response.bytes(
            utf8.encode(jsonEncode(noblesseResponse())),
            200,
          );
        }),
      );
      expect(seenUri!.host, 'kitsu.io');
      expect(seenUri!.queryParameters['filter[text]'], 'noblesse');
      expect(seenUri!.queryParameters['page[limit]'], '20');
      expect(seenUri!.queryParameters['include'], 'mappings');
      expect(result.failed, isFalse);
      expect(result.results.length, 1);
      expect(result.results.first.anilistId, 116005);
    });

    test('non-200 and thrown errors report failed, never throw', () async {
      final r500 = await KitsuSearch.search(
        'noblesse',
        client: MockClient((http.Request req) async {
          return http.Response('boom', 500);
        }),
      );
      expect(r500.failed, isTrue);
      expect(r500.results, isEmpty);
      final rThrow = await KitsuSearch.search(
        'noblesse',
        client: MockClient((http.Request req) async {
          throw Exception('no network');
        }),
      );
      expect(rThrow.failed, isTrue);
      expect(rThrow.results, isEmpty);
    });
  });
}
