import 'dart:convert';

import 'package:anibee/services/anilist_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// M2: AniList live search (public GraphQL, no key) + local fallback.
/// The search screen calls [AniListService.searchAnime] first and falls
/// back to the local catalogue when the network fails or returns nothing.
void main() {
  group('AniListService.searchAnime', () {
    MockClient clientFor(Map<String, dynamic> body, {int status = 200}) {
      return MockClient((http.Request req) async {
        // 0.2.15: the Kitsu fallback fires for empty/failed AniList
        // lookups — it is a GET with no body, so route it to an
        // empty Kitsu payload instead of the AniList URL assertion.
        if (req.url.host == 'kitsu.io') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'data': <dynamic>[],
              'included': <dynamic>[],
            }),
            200,
          );
        }
        expect(req.url.toString(), AniListService.graphqlUrl);
        return http.Response(jsonEncode(body), status);
      });
    }

    Map<String, dynamic> pageJson(List<Map<String, dynamic>> media) {
      return <String, dynamic>{
        'data': <String, dynamic>{
          'Page': <String, dynamic>{'media': media},
        },
      };
    }

    Map<String, dynamic> mediaJson({
      required int id,
      String? english,
      String? romaji,
      int? idMal,
      int episodes = 12,
      int score = 85,
    }) {
      return <String, dynamic>{
        'id': id,
        'idMal': idMal,
        'title': <String, dynamic>{'romaji': romaji, 'english': english},
        'coverImage': <String, dynamic>{
          'large': 'https://cdn.example.com/large.jpg',
          'extraLarge': 'https://cdn.example.com/xl.jpg',
        },
        'format': 'TV',
        'episodes': episodes,
        'seasonYear': 2024,
        'averageScore': score,
        'genres': <String>['Action', 'Fantasy'],
        'description': 'A <b>hero</b> rises.',
      };
    }

    test('parses Page.media into Anime with ids + poster', () async {
      final AniListService svc = AniListService(
        client: clientFor(
          pageJson(<Map<String, dynamic>>[
            mediaJson(id: 1, english: 'Frieren', idMal: 101),
            mediaJson(id: 2, romaji: 'Sousou no Frieren', episodes: 28),
          ]),
        ),
      );
      final results = await svc.searchAnime('Frieren');
      expect(results.length, 2);
      expect(results[0].title, 'Frieren');
      expect(results[0].anilistId, 1);
      expect(results[0].malId, 101);
      expect(results[0].id, 'anilist-1');
      expect(results[0].posterUrl, 'https://cdn.example.com/xl.jpg');
      expect(results[0].episodeCount, 12);
      expect(results[0].rating, closeTo(4.25, 0.01));
      // HTML stripped from the description.
      expect(results[0].synopsis, isNot(contains('<b>')));
      // English preferred over romaji.
      expect(results[1].title, 'Sousou no Frieren');
      expect(results[1].episodeCount, 28);
    });

    test('empty media returns an empty list (screen falls back local)',
        () async {
      final AniListService svc = AniListService(
        client: clientFor(pageJson(<Map<String, dynamic>>[])),
      );
      expect(await svc.searchAnime('zzz-no-such-anime'), isEmpty);
    });

    test('non-200 / bad body returns an empty list, never throws', () async {
      final AniListService svc = AniListService(
        client: clientFor(<String, dynamic>{}, status: 429),
      );
      expect(await svc.searchAnime('Frieren'), isEmpty);
    });

    test('resolveId picks the exact title match', () async {
      final AniListService svc = AniListService(
        client: clientFor(
          pageJson(<Map<String, dynamic>>[
            mediaJson(id: 9, english: 'Jujutsu Kaisen 2nd Season'),
            mediaJson(id: 5, english: 'Jujutsu Kaisen'),
          ]),
        ),
      );
      expect(await svc.resolveId('Jujutsu Kaisen'), 5);
    });

    test('resolveId returns 21459 for My Hero Academia (0.2.9)', () async {
      // 0.2.9 phone regression: the MHA catalogue entry had no
      // stored anilistId, so _loadSeasons never started and no
      // season selector showed. The detail screen now resolves by
      // title first — the exact match must win over the movie
      // sequel in the same search page.
      final AniListService svc = AniListService(
        client: clientFor(
          pageJson(<Map<String, dynamic>>[
            mediaJson(
              id: 21460,
              english: 'My Hero Academia: Heroes Rising',
            ),
            mediaJson(id: 21459, english: 'My Hero Academia'),
          ]),
        ),
      );
      expect(await svc.resolveId('My Hero Academia'), 21459);
    });
  });

  group('AniListService.animeFromMedia', () {
    test('falls back romaji -> native, drops Unknown', () {
      final anime = AniListService.animeFromMedia(<String, dynamic>{
        'id': 42,
        'title': <String, dynamic>{'romaji': 'Kimetsu no Yaiba'},
        'coverImage': <String, dynamic>{'large': 'https://x/y.jpg'},
        'episodes': 26,
      });
      expect(anime, isNotNull);
      expect(anime!.title, 'Kimetsu no Yaiba');
      expect(anime.anilistId, 42);
      expect(
        AniListService.animeFromMedia(<String, dynamic>{
          'id': 43,
          'title': <String, dynamic>{},
        }),
        isNull,
      );
    });

    test('still-airing TV derives the aired count from nextAiringEpisode',
        () {
      // 0.2.13: AniList `episodes` is null while a series airs —
      // next EP 9 means 8 have aired, and the upcoming EP + air
      // date travel with the Anime into Detail.
      final anime = AniListService.animeFromMedia(<String, dynamic>{
        'id': 97940,
        'title': <String, dynamic>{'romaji': 'Black Clover'},
        'format': 'TV',
        'episodes': null,
        'nextAiringEpisode': <String, dynamic>{
          'episode': 9,
          'airingAt': 1795739100,
        },
      });
      expect(anime, isNotNull);
      expect(anime!.episodeCount, 8);
      expect(anime.nextEpisode, 9);
      expect(anime.nextEpisodeIn, isNotNull);
      expect(
        anime.nextEpisodeAt,
        matches(RegExp(r'^[A-Z][a-z]{2} \d{1,2} at \d{2}:\d{2}$')),
      );
    });

    test('not-yet-aired TV keeps 0 episodes but carries the next EP', () {
      final anime = AniListService.animeFromMedia(<String, dynamic>{
        'id': 97941,
        'title': <String, dynamic>{'romaji': 'Future Season'},
        'format': 'TV',
        'episodes': null,
        'nextAiringEpisode': <String, dynamic>{
          'episode': 1,
          'airingAt': 1795739100,
        },
      });
      expect(anime, isNotNull);
      expect(anime!.episodeCount, 0);
      expect(anime.nextEpisode, 1);
    });
  });

  group('AniListService.viewer', () {
    test('parses id + name', () async {
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          expect(req.headers['Authorization'], 'Bearer tok123');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'data': <String, dynamic>{
                'Viewer': <String, dynamic>{'id': 7, 'name': 'Suresh'},
              },
            }),
            200,
          );
        }),
      );
      final viewer = await svc.viewer('tok123');
      expect(viewer.id, 7);
      expect(viewer.name, 'Suresh');
    });
  });

  group('cleanDescription', () {
    test('strips tags and collapses whitespace', () {
      expect(
        AniListService.cleanDescription(
          'Line one.<br>\n  Line   two.',
        ),
        'Line one. Line two.',
      );
      expect(AniListService.cleanDescription(null), '');
    });
  });

  test('gradient constant exists for search results', () {
    // Search results use the same fallback gradient as the catalogue.
    const gradient = <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)];
    expect(gradient.length, 2);
  });

  group('search misses (0.2.12, item 9)', () {
    Map<String, dynamic> media({
      required int id,
      required String english,
      String format = 'TV',
      int? episodes = 12,
      int year = 2020,
    }) {
      return <String, dynamic>{
        'id': id,
        'idMal': null,
        'title': <String, dynamic>{'romaji': english, 'english': english},
        'coverImage': <String, dynamic>{
          'large': 'https://cdn.example.com/large.jpg',
        },
        'format': format,
        'episodes': episodes,
        'seasonYear': year,
        'averageScore': 80,
        'genres': <String>['Drama'],
        'description': 'Test title.',
      };
    }

    Map<String, dynamic> pageJson(List<Map<String, dynamic>> m) {
      return <String, dynamic>{
        'data': <String, dynamic>{
          'Page': <String, dynamic>{'media': m},
        },
      };
    }

    test('stripSeasonSuffix drops trailing season markers only', () {
      expect(
        AniListService.stripSeasonSuffix('Black Clover S2'),
        'Black Clover',
      );
      expect(
        AniListService.stripSeasonSuffix('One Piece S02'),
        'One Piece',
      );
      expect(
        AniListService.stripSeasonSuffix('Jujutsu Kaisen Season 2'),
        'Jujutsu Kaisen',
      );
      expect(
        AniListService.stripSeasonSuffix('Jujutsu Kaisen Season2'),
        'Jujutsu Kaisen',
      );
      expect(
        AniListService.stripSeasonSuffix('Attack on Titan 2nd Season'),
        'Attack on Titan',
      );
      expect(
        AniListService.stripSeasonSuffix('Sword Art Online Part 2'),
        'Sword Art Online',
      );
      expect(AniListService.stripSeasonSuffix('Frieren'), 'Frieren');
      expect(AniListService.stripSeasonSuffix('Naruto'), 'Naruto');
      expect(
        AniListService.stripSeasonSuffix('Black Clover 2'),
        'Black Clover 2',
      );
    });

    test('The Garden of Words (MOVIE, episodes null) returns as 1 EP',
        () async {
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          return http.Response(
            jsonEncode(
              pageJson(<Map<String, dynamic>>[
                media(
                  id: 10408,
                  english: 'The Garden of Words',
                  format: 'MOVIE',
                  episodes: null,
                  year: 2013,
                ),
              ]),
            ),
            200,
          );
        }),
      );
      final List<dynamic> results =
          await svc.searchAnime('The Garden of Words');
      expect(results.length, 1);
      expect(results[0].title, 'The Garden of Words');
      expect(results[0].anilistId, 10408);
      // A movie is one episode — Detail must open it as a playable
      // single-episode title, not the "No episodes yet" dead end.
      expect(results[0].episodeCount, 1);
    });

    test('MOVIE with episodes 0 forces 1; TV with 0 stays 0', () {
      final movie = AniListService.animeFromMedia(
        media(
          id: 10408,
          english: 'The Garden of Words',
          format: 'MOVIE',
          episodes: 0,
        ),
      );
      expect(movie!.episodeCount, 1);
      final tv = AniListService.animeFromMedia(
        media(id: 1, english: 'Airing Show', format: 'TV', episodes: 0),
      );
      expect(tv!.episodeCount, 0);
    });

    test('Noblesse (TV) returns', () async {
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          return http.Response(
            jsonEncode(
              pageJson(<Map<String, dynamic>>[
                media(id: 118586, english: 'Noblesse'),
              ]),
            ),
            200,
          );
        }),
      );
      final results = await svc.searchAnime('Noblesse');
      expect(results.map((a) => a.title), contains('Noblesse'));
      expect(results.first.anilistId, 118586);
    });

    test('"Black Clover S2" falls back to the stripped base title',
        () async {
      int calls = 0;
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          calls++;
          // 0.2.15: the Kitsu fallback fires between the simplified
          // retry and the stripped search — it is a GET with no
          // body, so route it before the AniList body parse.
          if (req.url.host == 'kitsu.io') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'data': <dynamic>[],
                'included': <dynamic>[],
              }),
              200,
            );
          }
          final Map<String, dynamic> body =
              jsonDecode(req.body) as Map<String, dynamic>;
          final String q =
              (body['variables'] as Map<String, dynamic>)['q'] as String;
          if (q == 'Black Clover S2') {
            // AniList's fuzzy search finds nothing for the suffix.
            return http.Response(jsonEncode(pageJson(<Map<String, dynamic>>[])), 200);
          }
          expect(q, 'Black Clover');
          return http.Response(
            jsonEncode(
              pageJson(<Map<String, dynamic>>[
                media(id: 97940, english: 'Black Clover', episodes: 170),
              ]),
            ),
            200,
          );
        }),
      );
      final results = await svc.searchAnime('Black Clover S2');
      // 0.2.15: 4 calls — primary (empty) → simplified retry
      // (empty) → Kitsu fallback (empty) → stripped "Black Clover"
      // (hit).
      expect(calls, 4);
      expect(results.map((a) => a.title), contains('Black Clover'));
      expect(results.first.anilistId, 97940);
    });

    test('no fallback call when the first page already has the base',
        () async {
      int calls = 0;
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          calls++;
          return http.Response(
            jsonEncode(
              pageJson(<Map<String, dynamic>>[
                media(id: 97940, english: 'Black Clover', episodes: 170),
              ]),
            ),
            200,
          );
        }),
      );
      final results = await svc.searchAnime('Black Clover S2');
      expect(calls, 1);
      expect(results.length, 1);
    });

    test('searchAnimeDetailed reports a dead AniList honestly',
        () async {
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          return http.Response('rate limited', 429);
        }),
      );
      final r = await svc.searchAnimeDetailed('Frieren');
      expect(r.results, isEmpty);
      expect(r.lookupFailed, isTrue);
      // The swallowing variant keeps its contract for resolveId.
      expect(await svc.searchAnime('Frieren'), isEmpty);
    });

    test('searchAnimeDetailed: genuine no-match is not a lookup failure',
        () async {
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          return http.Response(
            jsonEncode(pageJson(<Map<String, dynamic>>[])),
            200,
          );
        }),
      );
      final r = await svc.searchAnimeDetailed('zzz-no-such-anime');
      expect(r.results, isEmpty);
      expect(r.lookupFailed, isFalse);
    });
  });

  group('search diagnostics + null-data failure (0.2.13, item 3)', () {
    Map<String, dynamic> pageJson(List<Map<String, dynamic>> m) {
      return <String, dynamic>{
        'data': <String, dynamic>{
          'Page': <String, dynamic>{'media': m},
        },
      };
    }

    Map<String, dynamic> media({
      required int id,
      required String english,
      String format = 'TV',
      int? episodes = 12,
    }) {
      return <String, dynamic>{
        'id': id,
        'idMal': null,
        'title': <String, dynamic>{'romaji': english, 'english': english},
        'coverImage': <String, dynamic>{
          'large': 'https://cdn.example.com/large.jpg',
        },
        'format': format,
        'episodes': episodes,
        'seasonYear': 2023,
        'averageScore': 80,
        'genres': <String>['Action'],
        'description': 'Test title.',
      };
    }

    http.Response bytesJson(Object body, int status) =>
        http.Response.bytes(utf8.encode(jsonEncode(body)), status);

    test('null data is a lookup failure, not an empty success', () async {
      // 0.2.12 phone symptom: "noblesse" = 0 results with NO
      // "Couldn't reach AniList" banner — a 200 with no `data`
      // fell through to media=[] and came back as an empty SUCCESS.
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          return bytesJson(<String, dynamic>{'data': null}, 200);
        }),
      );
      final r = await svc.searchAnimeDetailed('noblesse');
      expect(r.results, isEmpty);
      expect(r.lookupFailed, isTrue);
      final SearchDiagnostic? d = svc.lastSearchDiagnostic;
      expect(d, isNotNull);
      expect(d!.ok, isFalse);
      expect(d.error, 'no data');
      expect(d.summary, contains('failed (no data)'));
    });

    test('missing Page is a lookup failure', () async {
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          return bytesJson(<String, dynamic>{
            'data': <String, dynamic>{},
          }, 200);
        }),
      );
      final r = await svc.searchAnimeDetailed('noblesse');
      expect(r.lookupFailed, isTrue);
      expect(svc.lastSearchDiagnostic?.error, 'no data');
    });

    test('429 is a lookup failure with a rate-limited diagnostic', () async {
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          return http.Response('rate limited', 429);
        }),
      );
      final r = await svc.searchAnimeDetailed('Frieren');
      expect(r.lookupFailed, isTrue);
      expect(svc.lastSearchDiagnostic?.ok, isFalse);
      expect(svc.lastSearchDiagnostic?.error, 'rate limited');
      expect(svc.lastSearchDiagnostic?.attempts, 2); // one retry happened
    });

    test('one retry rescues a transient 429', () async {
      int calls = 0;
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          calls++;
          if (calls == 1) return http.Response('rate limited', 429);
          return bytesJson(
            pageJson(<Map<String, dynamic>>[
              media(id: 118586, english: 'Noblesse'),
            ]),
            200,
          );
        }),
      );
      final r = await svc.searchAnimeDetailed('noblesse');
      expect(calls, 2);
      expect(r.lookupFailed, isFalse);
      expect(r.results.map((a) => a.title), contains('Noblesse'));
      expect(svc.lastSearchDiagnostic?.ok, isTrue);
      expect(svc.lastSearchDiagnostic?.attempts, 2);
    });

    test('Black Clover search returns the TV series AND the movie', () async {
      // 0.2.12 phone: "black clover" = 1 result (TV only, local) —
      // the 2023 movie "Sword of the Wizard King" never appeared.
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          return bytesJson(
            pageJson(<Map<String, dynamic>>[
              media(id: 97940, english: 'Black Clover', episodes: 170),
              media(
                id: 142511,
                english: 'Black Clover: Sword of the Wizard King',
                format: 'MOVIE',
                episodes: null,
              ),
            ]),
            200,
          );
        }),
      );
      final r = await svc.searchAnimeDetailed('black clover');
      expect(r.lookupFailed, isFalse);
      expect(r.results.length, 2);
      expect(
        r.results.map((a) => a.title),
        contains('Black Clover: Sword of the Wizard King'),
      );
      final movie = r.results.firstWhere(
        (a) => a.anilistId == 142511,
      );
      expect(movie.episodeCount, 1);
      final SearchDiagnostic? d = svc.lastSearchDiagnostic;
      expect(d!.ok, isTrue);
      expect(d.rawMediaCount, 2);
      expect(d.mappedCount, 2);
      expect(d.summary, 'ok · 2 from AniList');
    });

    test('diagnostic counts dropped entries (raw vs mapped)', () async {
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          return bytesJson(
            pageJson(<Map<String, dynamic>>[
              media(id: 1, english: 'Good Title'),
              // No usable title — animeFromMedia drops it.
              <String, dynamic>{
                'id': 2,
                'title': <String, dynamic>{},
                'format': 'TV',
                'episodes': 12,
              },
            ]),
            200,
          );
        }),
      );
      final r = await svc.searchAnimeDetailed('good');
      expect(r.results.length, 1);
      final SearchDiagnostic? d = svc.lastSearchDiagnostic;
      expect(d!.rawMediaCount, 2);
      expect(d.mappedCount, 1);
      expect(d.summary, contains('1 shown (2 from AniList)'));
    });
  });

  group('search fallback (0.2.15)', () {
    Map<String, dynamic> pageJson(List<Map<String, dynamic>> m) {
      return <String, dynamic>{
        'data': <String, dynamic>{
          'Page': <String, dynamic>{'media': m},
        },
      };
    }

    Map<String, dynamic> media({
      required int id,
      required String english,
      String format = 'TV',
      int? episodes = 12,
    }) {
      return <String, dynamic>{
        'id': id,
        'idMal': null,
        'title': <String, dynamic>{'romaji': english, 'english': english},
        'coverImage': <String, dynamic>{
          'large': 'https://cdn.example.com/large.jpg',
        },
        'format': format,
        'episodes': episodes,
        'seasonYear': 2023,
        'averageScore': 80,
        'genres': <String>['Action'],
        'description': 'Test title.',
      };
    }

    http.Response bytesJson(Object body, int status) =>
        http.Response.bytes(utf8.encode(jsonEncode(body)), status);

    Map<String, dynamic> kitsuEmpty() =>
        <String, dynamic>{'data': <dynamic>[], 'included': <dynamic>[]};

    /// Minimal Kitsu payload: Noblesse with a direct AniList
    /// mapping (real ids from the live VM probe: Kitsu 43019 →
    /// AniList 116005, MAL 41345).
    Map<String, dynamic> kitsuNoblesse() {
      return <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{
            'id': '43019',
            'type': 'anime',
            'attributes': <String, dynamic>{
              'canonicalTitle': 'Noblesse',
              'averageRating': '69.23',
              'episodeCount': 13,
              'startDate': '2020-10-07',
              'showType': 'TV',
              'synopsis': 'A noble vampire awakens.',
              'posterImage': <String, dynamic>{
                'large':
                    'https://media.kitsu.app/anime/poster_images/43019/large.jpg',
              },
            },
            'relationships': <String, dynamic>{
              'mappings': <String, dynamic>{
                'data': <dynamic>[
                  <String, dynamic>{'id': 'm-anilist', 'type': 'mappings'},
                ],
              },
            },
          },
        ],
        'included': <dynamic>[
          <String, dynamic>{
            'id': 'm-anilist',
            'type': 'mappings',
            'attributes': <String, dynamic>{
              'externalSite': 'anilist/anime',
              'externalId': '116005',
            },
          },
        ],
      };
    }

    test('primary 0 -> simplified retry returns results', () async {
      // 0.2.13 phone symptom: "noblesse" = "ok · 0 from AniList".
      // The full filtered query returns nothing, the MINIMAL query
      // (only search + type:ANIME, no filter vars at all) finds it.
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          if (req.url.host == 'kitsu.io') {
            return bytesJson(kitsuEmpty(), 200);
          }
          final Map<String, dynamic> body =
              jsonDecode(req.body) as Map<String, dynamic>;
          final Map<String, dynamic> vars =
              body['variables'] as Map<String, dynamic>;
          // The minimal query sends NO null filter variables — its
          // variables map has no 'g' key at all.
          final bool minimal = !vars.containsKey('g');
          if (minimal) {
            return bytesJson(
              pageJson(<Map<String, dynamic>>[
                media(id: 116005, english: 'Noblesse', episodes: 13),
              ]),
              200,
            );
          }
          return bytesJson(pageJson(<Map<String, dynamic>>[]), 200);
        }),
      );
      final r = await svc.searchAnimeDetailed('noblesse');
      expect(r.lookupFailed, isFalse);
      expect(r.results.map((a) => a.title), contains('Noblesse'));
      expect(r.results.first.anilistId, 116005);
      final SearchDiagnostic? d = svc.lastSearchDiagnostic;
      expect(d!.source, 'anilist-simplified');
      expect(d.summary, 'ok · 1 from AniList (simplified retry)');
    });

    test('AniList empty + Kitsu returns Noblesse', () async {
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          if (req.url.host == 'kitsu.io') {
            return bytesJson(kitsuNoblesse(), 200);
          }
          return bytesJson(pageJson(<Map<String, dynamic>>[]), 200);
        }),
      );
      final r = await svc.searchAnimeDetailed('noblesse');
      expect(r.lookupFailed, isFalse);
      expect(r.results.length, 1);
      expect(r.results.first.title, 'Noblesse');
      expect(r.results.first.anilistId, 116005);
      // The Kitsu result carries a REAL AniList id — Detail opens
      // it and plays it, same as any AniList result.
      expect(r.results.first.id, 'anilist-116005');
      final SearchDiagnostic? d = svc.lastSearchDiagnostic;
      expect(d!.source, 'kitsu');
      expect(d.summary, 'ok · 1 from Kitsu (AniList empty)');
    });

    test('AniList fails -> Kitsu still serves the search', () async {
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          if (req.url.host == 'kitsu.io') {
            return bytesJson(kitsuNoblesse(), 200);
          }
          return http.Response('rate limited', 429);
        }),
      );
      final r = await svc.searchAnimeDetailed('noblesse');
      expect(r.lookupFailed, isFalse);
      expect(r.results.map((a) => a.title), contains('Noblesse'));
      final SearchDiagnostic? d = svc.lastSearchDiagnostic;
      expect(d!.source, 'kitsu');
      expect(
        d.summary,
        'ok · 1 from Kitsu (AniList failed: rate limited)',
      );
    });

    test('diagnostic shows the primary variables when all paths empty',
        () async {
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          if (req.url.host == 'kitsu.io') {
            return bytesJson(kitsuEmpty(), 200);
          }
          return bytesJson(pageJson(<Map<String, dynamic>>[]), 200);
        }),
      );
      final r = await svc.searchAnimeDetailed('noblesse');
      expect(r.results, isEmpty);
      expect(r.lookupFailed, isFalse);
      final SearchDiagnostic? d = svc.lastSearchDiagnostic;
      expect(d!.source, 'none');
      expect(
        d.summary,
        'ok · 0 from AniList · q=noblesse · genre=All · year=All · '
        'status=All · format=All',
      );
    });

    test('Kitsu entries without an AniList id are dropped, never shown',
        () async {
      final Map<String, dynamic> kitsu = kitsuNoblesse();
      // A second entry with no mapping at all — unplayable, must
      // not appear as a result.
      (kitsu['data'] as List<dynamic>).add(<String, dynamic>{
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
      final AniListService svc = AniListService(
        client: MockClient((http.Request req) async {
          if (req.url.host == 'kitsu.io') {
            return bytesJson(kitsu, 200);
          }
          return bytesJson(pageJson(<Map<String, dynamic>>[]), 200);
        }),
      );
      final r = await svc.searchAnimeDetailed('noblesse');
      expect(r.results.length, 1);
      expect(r.results.first.title, 'Noblesse');
      final SearchDiagnostic? d = svc.lastSearchDiagnostic;
      expect(d!.droppedCount, 1);
      expect(d.summary, contains('1 unmapped'));
    });
  });
}
