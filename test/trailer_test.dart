import 'package:anibee/models.dart';
import 'package:anibee/services/anilist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 0.2.4: real per-anime trailers from AniList (trailer { id, site })
/// — the same sample video on every title is gone.
void main() {
  Map<String, dynamic> mediaJson({Object? trailer}) {
    return <String, dynamic>{
      'id': 113415,
      'idMal': 40028,
      'title': <String, dynamic>{
        'romaji': 'Jujutsu Kaisen',
        'english': 'JUJUTSU KAISEN',
      },
      'coverImage': <String, dynamic>{
        'large': 'https://example.com/poster.jpg',
      },
      'episodes': 47,
      'seasonYear': 2020,
      'averageScore': 86,
      'genres': <String>['Action'],
      'description': 'A boy eats a finger.',
      // ignore: use_null_aware_elements
      if (trailer != null) 'trailer': trailer,
    };
  }

  group('fetchTrailer', () {
    test('returns the YouTube video id', () async {
      final MockClient client = MockClient(
        (_) async => http.Response(
          '{"data":{"Media":{"trailer":{"id":"dQw4w9WgXcQ","site":"youtube"}}}}',
          200,
        ),
      );
      final AniListService service = AniListService(client: client);
      final ({String site, String videoId})? trailer =
          await service.fetchTrailer(113415);
      expect(trailer?.site, 'youtube');
      expect(trailer?.videoId, 'dQw4w9WgXcQ');
    });

    test('null trailer -> null (banner shows the poster only)', () async {
      final MockClient client = MockClient(
        (_) async =>
            http.Response('{"data":{"Media":{"trailer":null}}}', 200),
      );
      final AniListService service = AniListService(client: client);
      expect(await service.fetchTrailer(113415), isNull);
    });

    test('network failure -> null, never throws', () async {
      final AniListService service = AniListService(
        client: MockClient((_) async => throw Exception('offline')),
      );
      expect(await service.fetchTrailer(113415), isNull);
    });
  });

  group('animeFromMedia trailer mapping', () {
    test('YouTube trailer -> watch URL', () {
      final Anime? anime = AniListService.animeFromMedia(
        mediaJson(
          trailer: <String, dynamic>{'id': 'abc123', 'site': 'youtube'},
        ),
      );
      expect(anime?.trailerUrl, 'https://www.youtube.com/watch?v=abc123');
    });

    test('no trailer -> null trailerUrl (never the sample video)', () {
      final Anime? anime = AniListService.animeFromMedia(mediaJson());
      expect(anime?.trailerUrl, isNull);
    });

    test('non-YouTube trailer -> null', () {
      final Anime? anime = AniListService.animeFromMedia(
        mediaJson(
          trailer: <String, dynamic>{'id': 'xyz', 'site': 'dailymotion'},
        ),
      );
      expect(anime?.trailerUrl, isNull);
    });
  });

  group('trailerWatchUrl', () {
    test('youtube -> watch URL', () {
      expect(
        trailerWatchUrl(<String, dynamic>{'id': 'abc', 'site': 'youtube'}),
        'https://www.youtube.com/watch?v=abc',
      );
    });

    test('other site / null -> null', () {
      expect(
        trailerWatchUrl(<String, dynamic>{'id': 'x', 'site': 'dailymotion'}),
        isNull,
      );
      expect(trailerWatchUrl(null), isNull);
    });
  });

  group('youtubeVideoIdFromUrl', () {
    test('watch URL', () {
      expect(
        youtubeVideoIdFromUrl('https://www.youtube.com/watch?v=abc123'),
        'abc123',
      );
    });

    test('youtu.be short URL', () {
      expect(youtubeVideoIdFromUrl('https://youtu.be/abc123'), 'abc123');
    });

    test('embed URL', () {
      expect(
        youtubeVideoIdFromUrl('https://www.youtube.com/embed/abc123'),
        'abc123',
      );
    });

    test('non-YouTube / null -> null', () {
      expect(youtubeVideoIdFromUrl('https://example.com/watch?v=abc'), isNull);
      expect(youtubeVideoIdFromUrl(null), isNull);
    });
  });

  group('youtubeEmbedUrl', () {
    test('inline banner: muted, looping, no YT chrome', () {
      final String url = youtubeEmbedUrl('abc123');
      expect(url, contains('youtube.com/embed/abc123'));
      expect(url, contains('autoplay=1'));
      expect(url, contains('mute=1'));
      expect(url, contains('loop=1'));
      expect(url, contains('playlist=abc123'));
      expect(url, contains('controls=0'));
    });

    test('fullscreen: sound + controls', () {
      final String url = youtubeEmbedUrl(
        'abc123',
        muted: false,
        controls: true,
      );
      expect(url, contains('mute=0'));
      expect(url, contains('controls=1'));
    });
  });

  group('mock catalogue has no sample trailer', () {
    test('every entry has no trailer URL or a YouTube one — never a sample',
        () {
      for (final Anime anime in mockCatalogue()) {
        expect(
          anime.trailerUrl == null ||
              anime.trailerUrl!.startsWith(
                'https://www.youtube.com/watch?v=',
              ),
          isTrue,
          reason: anime.title,
        );
      }
    });
  });
}
