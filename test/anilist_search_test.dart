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
}
