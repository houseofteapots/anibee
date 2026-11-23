import 'dart:convert';

import 'package:anibee/models.dart';
import 'package:anibee/services/anilist_service.dart';
import 'package:anibee/services/anizone_resolver.dart';
import 'package:anibee/services/miruro_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 0.2.12 AniZone resolver: search -> series -> watch HLS, all
/// against canned real-shaped pages (the live flow was verified
/// from the VM 2026-11-23: Naruto search, series page, watch page
/// with a real master.m3u8). Non-ASCII fixture bodies go through
/// `Response.bytes(utf8.encode(...))` — `Response(String)` encodes
/// Latin-1 and throws on non-ASCII.
void main() {
  const Anime naruto = Anime(
    id: 'naruto',
    title: 'Naruto',
    rating: 4.2,
    year: 2002,
    episodeCount: 220,
    genres: <String>['Action'],
    synopsis: 'Test anime.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    anilistId: 20,
  );

  const String searchHtml = '''
<html><head><meta name="csrf-token" content="test-csrf"></head><body>
<script>items: JSON.parse('[{"slug":"bsagbos2","url":"https:\\/\\/anizone.to\\/anime\\/bsagbos2","main_title":"Boruto: Naruto Next Generations","title_list":{"1":"Boruto: Naruto Next Generations"},"type":"TV Series","start_year":2017,"episode_count":293},{"slug":"spjuxray","url":"https:\\/\\/anizone.to\\/anime\\/spjuxray","main_title":"Naruto","title_list":{"1":"Naruto","5":"Naruto","8":"\\u30ca\\u30eb\\u30c8"},"type":"TV Series","start_year":2002,"episode_count":220},{"slug":"dkpkuwbc","url":"https:\\/\\/anizone.to\\/anime\\/dkpkuwbc","main_title":"Naruto Shippuuden","title_list":{"1":"Naruto Shippuuden"},"type":"TV Series","start_year":2007,"episode_count":500}]')</script>
</body></html>
''';

  const String seriesHtml = '''
<html><head><meta name="csrf-token" content="test-csrf"></head><body>
<div wire:snapshot="{&quot;data&quot;:{},&quot;memo&quot;:{&quot;id&quot;:&quot;x&quot;,&quot;name&quot;:&quot;pages.anime-detail&quot;,&quot;path&quot;:&quot;anime\\/spjuxray&quot;},&quot;checksum&quot;:&quot;y&quot;}"></div>
<script>items: JSON.parse('[{"slug":"1","url":"https://anizone.to/anime/spjuxray/1","title_list":{"1":"Enter: Naruto Uzumaki!"},"summary":"Welcome to the Village Hidden in the Leaves.","duration":"23:12","videos_count":1},{"slug":"2","url":"https://anizone.to/anime/spjuxray/2","title_list":{"1":"My Name is Konohamaru!"},"summary":"Second episode.","duration":"23:12","videos_count":1}]')</script>
<script>nextCursor: 'cursor-1', hasMore: false, loading: false</script>
</body></html>
''';

  const String watchHtml = '''
<html><body><script>vidstackPlayer(JSON.parse('{"src":"https://seiryuu.vid-cdn.xyz/abc123/master.m3u8","subtitles":[{"title":"English(SRT)","format":"srt","language":"en","default":true,"file":"https://seiryuu.vid-cdn.xyz/abc123/subtitles/2_en.srt"},{"title":"Only Song & Signs(SRT)","format":"srt","language":"en","default":false,"file":"https://seiryuu.vid-cdn.xyz/abc123/subtitles/3_en.srt"}],"storyboard":null,"chapter":null}'))</script></body></html>
''';

  http.Response bytes(String body, [int code = 200]) =>
      http.Response.bytes(utf8.encode(body), code);

  MockClient anilistClient({bool fail = false}) {
    return MockClient((http.Request req) async {
      if (fail) return http.Response('error', 500);
      final Map<String, dynamic> body =
          jsonDecode(req.body) as Map<String, dynamic>;
      final String query = (body['query'] as String?) ?? '';
      if (query.contains('Media(id:')) {
        return bytes(jsonEncode(<String, Object>{
          'data': <String, Object>{
            'Media': <String, Object>{
              'title': <String, Object>{
                'romaji': 'Naruto',
                'english': 'Naruto',
                'native': 'ナルト',
              },
              'seasonYear': 2002,
              'format': 'TV',
              'episodes': 220,
              'status': 'FINISHED',
            },
          },
        }));
      }
      return http.Response('not found', 404);
    });
  }

  MockClient azClient({
    String searchPage = searchHtml,
    String seriesPage = seriesHtml,
    String watchPage = watchHtml,
    String? livewireBody,
  }) {
    return MockClient((http.Request req) async {
      final String path = req.url.path;
      if (req.method == 'POST' && path == '/livewire/update') {
        if (livewireBody == null) return http.Response('not found', 404);
        return bytes(livewireBody);
      }
      if (path == '/anime' && req.url.queryParameters.containsKey('search')) {
        return bytes(searchPage);
      }
      if (path == '/anime/spjuxray') return bytes(seriesPage);
      if (path == '/anime/spjuxray/1') return bytes(watchPage);
      if (path == '/anime/spjuxray/100') {
        return bytes(
          watchHtml.replaceAll(
            'abc123',
            'ep100',
          ),
        );
      }
      return http.Response('not found', 404);
    });
  }

  AniZoneResolver resolver({
    MockClient? az,
    MockClient? anilist,
  }) {
    return AniZoneResolver(
      client: az ?? azClient(),
      anilist: AniListService(client: anilist ?? anilistClient()),
    );
  }

  group('parseSearchItems', () {
    test('parses the live search shape, unescapes \\/ and \\uXXXX', () {
      final List<AniZoneCandidate> items =
          AniZoneResolver.parseSearchItems(searchHtml);
      expect(items.length, 3);
      expect(items[1].slug, 'spjuxray');
      expect(items[1].title, 'Naruto');
      expect(items[1].year, 2002);
      expect(items[1].episodeCount, 220);
      expect(items[1].type, 'tv');
      // The native title arrives as \u escapes in the page.
      expect(items[1].titles, contains('ナルト'));
      expect(items[0].title, contains('Boruto'));
      expect(items[2].title, 'Naruto Shippuuden');
    });

    test('empty / garbage HTML parses to no candidates', () {
      expect(AniZoneResolver.parseSearchItems('<html></html>'), isEmpty);
      expect(AniZoneResolver.parseSearchItems(''), isEmpty);
    });
  });

  group('resolve', () {
    test('Naruto EP1 resolves to the watch HLS + subtitles', () async {
      final AniZoneResolver r = resolver();
      final ResolvedStream? stream = await r.resolve(
        anime: naruto,
        episodeNumber: 1,
        subDub: 'Sub',
      );
      expect(stream, isNotNull);
      expect(
        stream!.url,
        'https://seiryuu.vid-cdn.xyz/abc123/master.m3u8',
      );
      expect(stream.source, 'AniZone');
      expect(stream.label, 'AniZone Sub');
      expect(stream.subtitles.length, 2);
      expect(stream.subtitles.first.label, 'English(SRT)');
      expect(
        stream.subtitles.first.url,
        contains('subtitles/2_en.srt'),
      );
      expect(r.lastError, isNull);
    });

    test('Dub fails honestly — AniZone is Sub-only', () async {
      final AniZoneResolver r = resolver();
      final ResolvedStream? stream = await r.resolve(
        anime: naruto,
        episodeNumber: 1,
        subDub: 'Dub',
      );
      expect(stream, isNull);
      expect(r.lastError, contains('no Dub'));
    });

    test('no confident match fails honestly (Boruto only)', () async {
      const String borutoOnly = '''
<html><body><script>items: JSON.parse('[{"slug":"bsagbos2","url":"https://anizone.to/anime/bsagbos2","main_title":"Boruto: Naruto Next Generations","title_list":{"1":"Boruto: Naruto Next Generations"},"type":"TV Series","start_year":2017,"episode_count":293}]')</script></body></html>
''';
      final AniZoneResolver r = resolver(az: azClient(searchPage: borutoOnly));
      final ResolvedStream? stream = await r.resolve(
        anime: naruto,
        episodeNumber: 1,
        subDub: 'Sub',
      );
      expect(stream, isNull);
      expect(r.lastError, contains('Could not find "Naruto" on AniZone.'));
    });

    test('missing episode fails honestly', () async {
      final AniZoneResolver r = resolver();
      final ResolvedStream? stream = await r.resolve(
        anime: naruto,
        episodeNumber: 5,
        subDub: 'Sub',
      );
      expect(stream, isNull);
      expect(r.lastError, contains('no episode 5'));
    });

    test('AniList lookup failure is reported as a lookup failure',
        () async {
      const Anime noId = Anime(
        id: 'no-id',
        title: 'Naruto',
        rating: 4.0,
        year: 2002,
        episodeCount: 220,
        genres: <String>['Action'],
        synopsis: 'Test anime.',
        gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
      );
      final AniZoneResolver r = resolver(anilist: anilistClient(fail: true));
      final ResolvedStream? stream = await r.resolve(
        anime: noId,
        episodeNumber: 1,
        subDub: 'Sub',
      );
      expect(stream, isNull);
      expect(r.lastError, contains('AniList lookup failed'));
    });

    test('Livewire pagination finds EP 100 past the first page',
        () async {
      const String seriesPage1 = '''
<html><head><meta name="csrf-token" content="test-csrf"></head><body>
<div wire:snapshot="{&quot;data&quot;:{},&quot;memo&quot;:{&quot;id&quot;:&quot;x&quot;,&quot;name&quot;:&quot;pages.anime-detail&quot;,&quot;path&quot;:&quot;anime\\/spjuxray&quot;},&quot;checksum&quot;:&quot;y&quot;}"></div>
<script>items: JSON.parse('[{"slug":"1","url":"https://anizone.to/anime/spjuxray/1","title_list":{"1":"Enter: Naruto Uzumaki!"},"videos_count":1}]')</script>
<script>nextCursor: 'cursor-1', hasMore: true, loading: false</script>
</body></html>
''';
      const String livewireJson = '''
{"components":[{"snapshot":"snap-2","effects":{"dispatches":[{"name":"items-loaded","params":{"items":[{"slug":"100","url":"https://anizone.to/anime/spjuxray/100","title_list":{"1":"Episode 100"},"videos_count":1}],"nextCursor":null,"hasMore":false}}]}}]}
''';
      final AniZoneResolver r = resolver(
        az: azClient(seriesPage: seriesPage1, livewireBody: livewireJson),
      );
      final ResolvedStream? stream = await r.resolve(
        anime: naruto,
        episodeNumber: 100,
        subDub: 'Sub',
      );
      expect(stream, isNotNull);
      expect(stream!.url, contains('ep100/master.m3u8'));
      expect(r.lastError, isNull);
    });
  });
}
