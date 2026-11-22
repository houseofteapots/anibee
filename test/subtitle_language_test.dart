import 'dart:convert';

import 'package:anibee/models.dart';
import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/services/miruro_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit/media_kit.dart';

/// 0.2.3: subtitle language selection + English fetch.
/// - pickSubtitleTrack honours the Settings → Player language
///   (Auto = English) and falls back English → first track.
/// - isEnglishLabel is the single source of truth for English.
/// - fetchSubtitlesOnly pulls English tracks from the justanime
///   endpoints when the playing stream carries none (0.2.1: the
///   sheet showed only Off + Arabic).
void main() {
  group('pickSubtitleTrack', () {
    SubtitleTrack track(String label) =>
        SubtitleTrack.uri('https://example.com/$label.vtt', title: label);

    final List<SubtitleTrack> tracks = <SubtitleTrack>[
      track('Arabic'),
      track('English'),
      track('Hindi'),
    ];

    test('auto picks English', () {
      expect(pickSubtitleTrack(tracks, 'auto')?.title, 'English');
    });

    test('explicit language picks its track', () {
      expect(pickSubtitleTrack(tracks, 'hi')?.title, 'Hindi');
      expect(pickSubtitleTrack(tracks, 'ar')?.title, 'Arabic');
      expect(pickSubtitleTrack(tracks, 'en')?.title, 'English');
    });

    test('missing language falls back to English, then first', () {
      // Hindi requested, only Arabic + English present -> English.
      expect(
        pickSubtitleTrack(<SubtitleTrack>[track('Arabic'), track('English')], 'hi')?.title,
        'English',
      );
      // English requested, only Arabic present -> first track.
      expect(
        pickSubtitleTrack(<SubtitleTrack>[track('Arabic')], 'en')?.title,
        'Arabic',
      );
    });

    test('off returns null (no track)', () {
      expect(pickSubtitleTrack(tracks, 'off'), isNull);
    });

    test('empty list returns null', () {
      expect(pickSubtitleTrack(<SubtitleTrack>[], 'auto'), isNull);
    });
  });

  group('isEnglishLabel', () {
    test('matches English variants', () {
      expect(MiruroResolver.isEnglishLabel('English'), isTrue);
      expect(MiruroResolver.isEnglishLabel('English [SDH]'), isTrue);
      expect(MiruroResolver.isEnglishLabel('en'), isTrue);
      expect(MiruroResolver.isEnglishLabel('eng'), isTrue);
      expect(MiruroResolver.isEnglishLabel('en-US'), isTrue);
      expect(MiruroResolver.isEnglishLabel('[EN] English'), isTrue);
    });

    test('rejects other languages and blanks', () {
      expect(MiruroResolver.isEnglishLabel('Arabic'), isFalse);
      expect(MiruroResolver.isEnglishLabel('Hindi'), isFalse);
      expect(MiruroResolver.isEnglishLabel('Spanish'), isFalse);
      expect(MiruroResolver.isEnglishLabel(''), isFalse);
      expect(MiruroResolver.isEnglishLabel(null), isFalse);
    });
  });

  group('fetchSubtitlesOnly', () {
    Anime anime() => const Anime(
      id: 'jujutsu-kaisen',
      title: 'JUJUTSU KAISEN',
      rating: 8.5,
      year: 2023,
      episodeCount: 24,
      genres: <String>['Action'],
      synopsis: '',
      gradient: <Color>[Colors.black],
      anilistId: 113415,
    );

    String justAnimeBody(List<Map<String, String>> subs) {
      return jsonEncode(<String, dynamic>{
        'sub': <String, dynamic>{
          'subtitles': subs
              .map(
                (Map<String, String> s) => <String, String>{
                  'label': s['label']!,
                  'file': s['file']!,
                  'kind': 'captions',
                },
              )
              .toList(),
        },
      });
    }

    test('returns English when the endpoint has it', () async {
      final MockClient client = MockClient((http.Request request) async {
        if (request.url.path.contains('megaplay')) {
          return http.Response(
            justAnimeBody(<Map<String, String>>[
              <String, String>{
                'label': 'Arabic',
                'file': 'https://cdn.example.com/ar.vtt',
              },
              <String, String>{
                'label': 'English',
                'file': 'https://cdn.example.com/en.vtt',
              },
            ]),
            200,
          );
        }
        return http.Response('{"error":"nope"}', 404);
      });
      final MiruroResolver resolver = MiruroResolver(client: client);
      final List<SubtitleInfo> subs = await resolver.fetchSubtitlesOnly(
        anime: anime(),
        episodeNumber: 1,
      );
      expect(
        subs.map((SubtitleInfo s) => s.label),
        containsAll(<String>['Arabic', 'English']),
      );
      expect(
        subs
            .where((SubtitleInfo s) => MiruroResolver.isEnglishLabel(s.label))
            .map((SubtitleInfo s) => s.url),
        contains('https://cdn.example.com/en.vtt'),
      );
    });

    test('returns only Arabic when no English exists for the episode', () async {
      final MockClient client = MockClient((http.Request request) async {
        return http.Response(
          justAnimeBody(<Map<String, String>>[
            <String, String>{
              'label': 'Arabic',
              'file': 'https://cdn.example.com/ar.vtt',
            },
          ]),
          200,
        );
      });
      final MiruroResolver resolver = MiruroResolver(client: client);
      final List<SubtitleInfo> subs = await resolver.fetchSubtitlesOnly(
        anime: anime(),
        episodeNumber: 1,
      );
      expect(subs, hasLength(1));
      expect(subs.first.label, 'Arabic');
      expect(
        subs.any((SubtitleInfo s) => MiruroResolver.isEnglishLabel(s.label)),
        isFalse,
      );
    });

    test('dedupes the same track across megaplay and animegg', () async {
      final MockClient client = MockClient((http.Request request) async {
        return http.Response(
          justAnimeBody(<Map<String, String>>[
            <String, String>{
              'label': 'English',
              'file': 'https://cdn.example.com/en.vtt',
            },
          ]),
          200,
        );
      });
      final MiruroResolver resolver = MiruroResolver(client: client);
      final List<SubtitleInfo> subs = await resolver.fetchSubtitlesOnly(
        anime: anime(),
        episodeNumber: 1,
      );
      expect(subs, hasLength(1));
    });

    test('returns empty (never throws) when the endpoints fail', () async {
      final MockClient client = MockClient(
        (http.Request request) async => http.Response('boom', 500),
      );
      final MiruroResolver resolver = MiruroResolver(client: client);
      final List<SubtitleInfo> subs = await resolver.fetchSubtitlesOnly(
        anime: anime(),
        episodeNumber: 1,
      );
      expect(subs, isEmpty);
    });
  });
}
