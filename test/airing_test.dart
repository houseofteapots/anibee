// AIRING (0.2.10): countdown formatting, soonest-first sort,
// AiringEntry parsing, fetchAiring paths (user list / followed ids /
// trending / failure) and the notification pure helpers.
import 'dart:convert';

import 'package:anibee/services/airing_notifications.dart';
import 'package:anibee/services/airing_service.dart';
import 'package:anibee/services/anilist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('formatAiringCountdown', () {
    final DateTime now = DateTime(2026, 11, 23, 12, 0);

    test('days + hours', () {
      final DateTime at = DateTime(2026, 11, 25, 16, 30);
      expect(formatAiringCountdown(at, now: now), 'in 2d 4h');
    });

    test('hours + minutes', () {
      final DateTime at = DateTime(2026, 11, 23, 15, 12);
      expect(formatAiringCountdown(at, now: now), 'in 3h 12m');
    });

    test('minutes only', () {
      final DateTime at = DateTime(2026, 11, 23, 12, 45);
      expect(formatAiringCountdown(at, now: now), 'in 45m');
    });

    test('past or now is airing now', () {
      expect(formatAiringCountdown(now, now: now), 'Airing now');
      expect(
        formatAiringCountdown(now.subtract(const Duration(minutes: 5)),
            now: now),
        'Airing now',
      );
    });
  });

  group('formatAiringDate (0.2.13)', () {
    test('renders "Nov 29 at 22:05" shape in local time', () {
      final DateTime at = DateTime.utc(2026, 11, 29, 16, 35);
      final String s = formatAiringDate(at);
      expect(s, matches(RegExp(r'^[A-Z][a-z]{2} \d{1,2} at \d{2}:\d{2}$')));
      expect(s, contains('at'));
    });
  });

  group('AiringEntry.airedCount (0.2.13)', () {
    test('next EP 9 means 8 aired; next EP 1 means 0 aired', () {
      final DateTime at = DateTime(2026, 11, 29, 22, 5);
      expect(
        AiringEntry(
          anilistId: 1,
          title: 'Mid-season',
          episode: 9,
          airingAt: at,
        ).airedCount,
        8,
      );
      expect(
        AiringEntry(
          anilistId: 2,
          title: 'Not started',
          episode: 1,
          airingAt: at,
        ).airedCount,
        0,
      );
    });
  });

  group('sortAiringEntries', () {
    test('soonest first, past dropped, capped at 20', () {
      final DateTime now = DateTime(2026, 11, 23, 12, 0);
      final List<AiringEntry> entries = <AiringEntry>[
        AiringEntry(
          anilistId: 1,
          title: 'Late',
          episode: 5,
          airingAt: now.add(const Duration(days: 3)),
        ),
        AiringEntry(
          anilistId: 2,
          title: 'Past',
          episode: 5,
          airingAt: now.subtract(const Duration(hours: 1)),
        ),
        AiringEntry(
          anilistId: 3,
          title: 'Soon',
          episode: 5,
          airingAt: now.add(const Duration(hours: 2)),
        ),
        ...List<AiringEntry>.generate(
          25,
          (int i) => AiringEntry(
            anilistId: 100 + i,
            title: 'Far $i',
            episode: 1,
            airingAt: now.add(Duration(days: 10 + i)),
          ),
        ),
      ];
      final List<AiringEntry> sorted = sortAiringEntries(entries, now: now);
      expect(sorted.length, 20);
      expect(sorted.first.title, 'Soon');
      expect(sorted[1].title, 'Late');
      expect(sorted.any((AiringEntry e) => e.title == 'Past'), isFalse);
    });
  });

  group('AiringEntry.fromMedia', () {
    test('parses romaji/english/userPreferred + episode + poster', () {
      final DateTime at = DateTime.utc(2026, 11, 24, 10, 0);
      final AiringEntry? entry = AiringEntry.fromMedia(<String, dynamic>{
        'id': 21,
        'title': <String, dynamic>{
          'romaji': 'One Piece',
          'english': null,
          'userPreferred': 'One Piece',
        },
        'nextAiringEpisode': <String, dynamic>{
          'airingAt': at.millisecondsSinceEpoch ~/ 1000,
          'episode': 1181,
        },
        'episodes': 1180,
        'coverImage': <String, dynamic>{'large': 'https://example.com/p.jpg'},
      });
      expect(entry, isNotNull);
      expect(entry!.anilistId, 21);
      expect(entry.title, 'One Piece');
      expect(entry.episode, 1181);
      expect(entry.airingAt, at);
      expect(entry.episodeCount, 1180);
      expect(entry.posterUrl, 'https://example.com/p.jpg');
    });

    test('null when no next airing episode', () {
      expect(
        AiringEntry.fromMedia(<String, dynamic>{
          'id': 1,
          'title': <String, dynamic>{'userPreferred': 'Finished'},
          'nextAiringEpisode': null,
          'episodes': 12,
        }),
        isNull,
      );
    });

    test('prefers english title when present', () {
      final AiringEntry? entry = AiringEntry.fromMedia(<String, dynamic>{
        'id': 2,
        'title': <String, dynamic>{
          'romaji': 'Romaji Name',
          'english': 'English Name',
          'userPreferred': 'Romaji Name',
        },
        'nextAiringEpisode': <String, dynamic>{
          'airingAt': 1794000000,
          'episode': 3,
        },
      });
      expect(entry!.title, 'English Name');
    });
  });

  group('AiringService.fetchAiring', () {
    late int viewerAiringAt;
    late int soonAiringAt;

    setUp(() {
      final DateTime now = DateTime.now();
      viewerAiringAt = now.add(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000;
      soonAiringAt = now.add(const Duration(hours: 5)).millisecondsSinceEpoch ~/ 1000;
    });

    MockClient clientFor({
      required Map<String, dynamic> listResponse,
      required Map<String, dynamic> pageResponse,
    }) {
      return MockClient((http.Request request) async {
        final String body = request.body;
        if (body.contains('Viewer')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'data': <String, dynamic>{
                'Viewer': <String, dynamic>{'id': 7, 'name': 'Test'},
              },
            }),
            200,
          );
        }
        if (body.contains('MediaListCollection')) {
          return http.Response(jsonEncode(listResponse), 200);
        }
        return http.Response(jsonEncode(pageResponse), 200);
      });
    }

    Map<String, dynamic> mediaEntry(
      int id,
      String title,
      int airingAt,
      int episode,
    ) {
      return <String, dynamic>{
        'id': id,
        'title': <String, dynamic>{
          'romaji': title,
          'english': null,
          'userPreferred': title,
        },
        'nextAiringEpisode': <String, dynamic>{
          'airingAt': airingAt,
          'episode': episode,
        },
        'episodes': 100,
        'coverImage': <String, dynamic>{'large': 'https://example.com/$id.jpg'},
      };
    }

    test('token -> user list, only airing entries, soonest first', () async {
      final AiringService service = AiringService(
        anilist: AniListService(
          client: clientFor(
            listResponse: <String, dynamic>{
              'data': <String, dynamic>{
                'MediaListCollection': <String, dynamic>{
                  'lists': <dynamic>[
                    <String, dynamic>{
                      'entries': <dynamic>[
                        <String, dynamic>{
                          'media': mediaEntry(1, 'Late Show', viewerAiringAt, 9),
                        },
                        <String, dynamic>{
                          'media': mediaEntry(2, 'Soon Show', soonAiringAt, 4),
                        },
                        <String, dynamic>{
                          // Finished show: no next airing episode.
                          'media': <String, dynamic>{
                            'id': 3,
                            'title': <String, dynamic>{
                              'userPreferred': 'Done Show',
                            },
                            'nextAiringEpisode': null,
                          },
                        },
                      ],
                    },
                  ],
                },
              },
            },
            pageResponse: <String, dynamic>{'data': <String, dynamic>{}},
          ),
        ),
      );
      final List<AiringEntry> entries =
          await service.fetchAiring(token: 'tok');
      expect(entries.map((AiringEntry e) => e.title), <String>[
        'Soon Show',
        'Late Show',
      ]);
      expect(entries.first.episode, 4);
    });

    test('no token + followedIds -> id_in page query', () async {
      final AiringService service = AiringService(
        anilist: AniListService(
          client: clientFor(
            listResponse: <String, dynamic>{'data': <String, dynamic>{}},
            pageResponse: <String, dynamic>{
              'data': <String, dynamic>{
                'Page': <String, dynamic>{
                  'media': <dynamic>[
                    mediaEntry(10, 'Followed One', soonAiringAt, 7),
                  ],
                },
              },
            },
          ),
        ),
      );
      final List<AiringEntry> entries =
          await service.fetchAiring(followedIds: <int>[10]);
      expect(entries.length, 1);
      expect(entries.first.anilistId, 10);
      expect(entries.first.episode, 7);
    });

    test('no token + no ids -> trending RELEASING', () async {
      final AiringService service = AiringService(
        anilist: AniListService(
          client: clientFor(
            listResponse: <String, dynamic>{'data': <String, dynamic>{}},
            pageResponse: <String, dynamic>{
              'data': <String, dynamic>{
                'Page': <String, dynamic>{
                  'media': <dynamic>[
                    mediaEntry(20, 'Trending Show', soonAiringAt, 2),
                  ],
                },
              },
            },
          ),
        ),
      );
      final List<AiringEntry> entries = await service.fetchAiring();
      expect(entries.length, 1);
      expect(entries.first.title, 'Trending Show');
    });

    test('network failure -> empty, never throws', () async {
      final AiringService service = AiringService(
        anilist: AniListService(
          client: MockClient((_) async {
            throw Exception('offline');
          }),
        ),
      );
      expect(await service.fetchAiring(token: 'tok'), isEmpty);
      expect(await service.fetchAiring(), isEmpty);
    });
  });

  group('AiringNotifications pure helpers', () {
    AiringEntry entryAt(DateTime airingAt, {int id = 1}) {
      return AiringEntry(
        anilistId: id,
        title: 'Show $id',
        episode: 1,
        airingAt: airingAt,
      );
    }

    test('fireTimeFor is 15 minutes before airing', () {
      expect(
        AiringNotifications.fireTimeFor(
          entryAt(DateTime.utc(2026, 11, 24, 10, 0)),
        ),
        DateTime.utc(2026, 11, 24, 9, 45),
      );
    });

    test('schedulable: only entries whose fire time is still future', () {
      final DateTime now = DateTime.now().toUtc();
      final List<AiringEntry> result = AiringNotifications.schedulable(
        <AiringEntry>[
          entryAt(now.add(const Duration(hours: 1)), id: 1),
          entryAt(now.subtract(const Duration(hours: 1)), id: 2),
          // Airing in 10 minutes: fire time (airing - 15m) is past.
          entryAt(now.add(const Duration(minutes: 10)), id: 3),
        ],
        now: now,
      );
      expect(result.map((AiringEntry e) => e.anilistId), <int>[1]);
    });
  });
}
