import 'package:anibee/services/anilist_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.11: two-way AniList sync — the pull side parses the user's
/// MediaListCollection into (anime, status, progress) entries, and
/// the search filters build the right GraphQL variables.
void main() {
  Map<String, dynamic> media(int id, String title) =>
      <String, dynamic>{
        'id': id,
        'idMal': id + 1000,
        'title': <String, dynamic>{
          'romaji': title,
          'english': title,
          'native': title,
        },
        'coverImage': <String, dynamic>{
          'large': 'https://cdn.example.com/$id.jpg',
          'extraLarge': null,
        },
        'format': 'TV',
        'episodes': 12,
        'seasonYear': 2024,
        'averageScore': 85,
        'genres': <String>['Action'],
        'description': 'Test.',
        'status': 'FINISHED',
      };

  Map<String, dynamic> collectionJson() => <String, dynamic>{
    'MediaListCollection': <String, dynamic>{
      'lists': <Object>[
        <String, dynamic>{
          'entries': <Object>[
            <String, dynamic>{
              'status': 'CURRENT',
              'progress': 5,
              'media': media(113415, 'Jujutsu Kaisen'),
            },
            <String, dynamic>{
              'status': 'COMPLETED',
              'progress': 12,
              'media': media(1, 'Cowboy Bebop'),
            },
            <String, dynamic>{
              'status': 'PLANNING',
              'progress': 0,
              'media': media(2, 'Frieren'),
            },
            // PAUSED / DROPPED are out of scope — the API never
            // returns them (status_in filter), but the parser must
            // not crash if one shows up.
            <String, dynamic>{
              'status': 'PAUSED',
              'progress': 3,
              'media': media(3, 'Paused Show'),
            },
            // Entry without media is skipped, never crashes.
            <String, dynamic>{'status': 'CURRENT', 'progress': 0},
          ],
        },
      ],
    },
  };

  group('parseUserListEntries', () {
    test('parses statuses + progress, skips media-less entries', () {
      final List<AnilistListEntry> entries =
          AniListService.parseUserListEntries(collectionJson());
      expect(entries.length, 4);
      expect(entries[0].anime.anilistId, 113415);
      expect(entries[0].status, 'CURRENT');
      expect(entries[0].progress, 5);
      expect(entries[1].status, 'COMPLETED');
      expect(entries[1].progress, 12);
      expect(entries[2].status, 'PLANNING');
      expect(entries[2].progress, 0);
      expect(entries[3].status, 'PAUSED');
    });

    test('empty / malformed data parses to an empty list', () {
      expect(AniListService.parseUserListEntries(<String, dynamic>{}), isEmpty);
      expect(
        AniListService.parseUserListEntries(<String, dynamic>{
          'MediaListCollection': <String, dynamic>{'lists': <Object>[]},
        }),
        isEmpty,
      );
    });
  });

  group('searchVariables (filters)', () {
    test('no filters -> nulls (AniList treats them as unset)', () {
      final Map<String, Object?> vars = AniListService.searchVariables('jjk');
      expect(vars['q'], 'jjk');
      expect(vars['g'], isNull);
      expect(vars['y'], isNull);
      expect(vars['s'], isNull);
      expect(vars['f'], isNull);
    });

    test('genre + year + status + format all pass through', () {
      final Map<String, Object?> vars = AniListService.searchVariables(
        'frieren',
        genre: 'Fantasy',
        year: 2023,
        status: 'FINISHED',
        format: 'TV',
      );
      expect(vars['g'], 'Fantasy');
      expect(vars['y'], 2023);
      expect(vars['s'], 'FINISHED');
      expect(vars['f'], 'TV');
    });
  });

  // The Anime model needs a widget binding for Color only in
  // fromJson paths — the parser above already covers it.
  test('sanity: flutter binding available', () {
    expect(Colors.white, isNotNull);
  });
}
