import 'dart:convert';

import 'package:anibee/models.dart';
import 'package:anibee/services/anilist_service.dart';
import 'package:anibee/services/miruro_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// M2: Miruro resolve — justanime primary + Anikoto fallback chain.
/// Crypto + playlist parsing are pure and tested directly; the full
/// Anikoto chain is tested end-to-end against a MockClient that plays
/// back canned site responses.
void main() {
  group('decryptMegaplay / encryptMegaplay', () {
    test('round-trips (AES-256-CBC, Anikoto v3 key/IV)', () {
      const String plain =
          '{"file":"https://cdn.example.com/master.m3u8","tracks":[]}';
      final String enc = MiruroResolver.encryptMegaplay(plain);
      expect(MiruroResolver.decryptMegaplay(enc), plain);
    });

    test('garbage input returns null, never throws', () {
      expect(MiruroResolver.decryptMegaplay('!!!not-base64!!!'), isNull);
      expect(MiruroResolver.decryptMegaplay(''), isNull);
    });
  });

  group('fileFromJsonText', () {
    test('extracts the file field', () {
      expect(
        MiruroResolver.fileFromJsonText(
          '{"file":"https://cdn.example.com/master.m3u8"}',
        ),
        'https://cdn.example.com/master.m3u8',
      );
      expect(MiruroResolver.fileFromJsonText('{"other":1}'), isNull);
      expect(MiruroResolver.fileFromJsonText('not json'), isNull);
    });
  });

  group('signMegaPlayUrl', () {
    const String h1 = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
    const String h2 = '0987654321fedcba0987654321fedcba';
    final String url = 'https://cdn.example.com/$h1/$h2/master.m3u8';

    test('appends a verifiable HMAC token (fixed clock)', () {
      final String signed = MiruroResolver.signMegaPlayUrl(
        url,
        nowSeconds: 1700000000,
      );
      expect(signed, startsWith('$url?token='));
      final String token = signed.split('token=').last;
      final List<String> parts = token.split('.');
      expect(parts.length, 2);
      final String payload = utf8.decode(
        base64Url.decode(base64.normalize(parts[0])),
      );
      // expiry = now + 90s, payload "<expiry>|<hash1>/<hash2>".
      expect(payload, '1700000090|$h1/$h2');
    });

    test('leaves non-megaplay URLs and already-signed URLs alone', () {
      expect(
        MiruroResolver.signMegaPlayUrl('https://cdn.example.com/a.m3u8'),
        'https://cdn.example.com/a.m3u8',
      );
      expect(
        MiruroResolver.signMegaPlayUrl('$url?token=abc'),
        '$url?token=abc',
      );
    });
  });

  group('parseMasterPlaylist', () {
    const String master =
        '#EXTM3U\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360\n'
        '360p/index.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=1400000,RESOLUTION=1280x720\n'
        '720p/index.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1920x1080\n'
        'https://cdn.example.com/1080p/index.m3u8\n';

    test('expands variants, resolves relative URLs, sorts best first', () {
      final List<StreamVariant> variants =
          MiruroResolver.parseMasterPlaylist(
            master,
            'https://cdn.example.com/hls/master.m3u8',
          );
      expect(variants.length, 3);
      expect(variants[0].qualityLabel, '1080p');
      expect(variants[0].url, 'https://cdn.example.com/1080p/index.m3u8');
      expect(variants[1].qualityLabel, '720p');
      expect(variants[1].url, 'https://cdn.example.com/hls/720p/index.m3u8');
      expect(variants[2].qualityLabel, '360p');
    });

    test('non-master body returns empty', () {
      expect(
        MiruroResolver.parseMasterPlaylist(
          '#EXTM3U\n#EXTINF:10,\nseg.ts\n',
          'https://cdn.example.com/x.m3u8',
        ),
        isEmpty,
      );
    });
  });

  group('resolve() — Anikoto fallback end to end (mocked)', () {
    const String searchHtml =
        '<div id="list-items"><div class="item">'
        '<div class="ani poster"><a href="/watch/jujutsu-kaisen-123/ep-1">'
        '<img alt="Jujutsu Kaisen"></a></div>'
        '<a class="name d-title">Jujutsu Kaisen</a>'
        '</div></div>';
    const String watchHtml =
        '<div data-anime-id="12345"></div>';
    const String episodeListHtml =
        '<a data-id="1" data-num="1" data-ids="tok-ep1"></a>'
        '<a data-id="2" data-num="2" data-ids="tok-ep2"></a>';
    const String serverListHtml =
        '<div class="type" data-type="sub">'
        '<li data-link-id="link-hd1">HD-1</li>'
        '<li data-link-id="link-hd2">HD-2</li></div>'
        '<div class="type" data-type="dub">'
        '<li data-link-id="link-dub1">HD-1</li></div>';
    const String embedHtml =
        '<div id="megaplay-player" data-id="mp-1" data-realid="mp-real"></div>';
    const String masterBody =
        '#EXTM3U\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=1400000,RESOLUTION=1280x720\n'
        '720p/index.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1920x1080\n'
        '1080p/index.m3u8\n';

    MockClient anikotoClient() {
      return MockClient((http.Request req) async {
        final String u = req.url.toString();
        if (u.startsWith('https://core.justanime.to/')) {
          return http.Response('{"error":"not found"}', 404);
        }
        if (u.startsWith('https://anikoto.cz/filter')) {
          return http.Response(searchHtml, 200);
        }
        if (u == 'https://anikoto.cz/watch/jujutsu-kaisen-123') {
          return http.Response(watchHtml, 200);
        }
        if (u.startsWith('https://anikoto.cz/ajax/episode/list/')) {
          return http.Response(
            jsonEncode(<String, dynamic>{'result': episodeListHtml}),
            200,
          );
        }
        if (u.startsWith('https://anikoto.cz/ajax/server/list')) {
          return http.Response(
            jsonEncode(<String, dynamic>{'result': serverListHtml}),
            200,
          );
        }
        if (u.startsWith('https://anikoto.cz/ajax/server?get=link-hd1')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'result': <String, dynamic>{
                'url': 'https://megaplay.buzz/embed/mp-1',
              },
            }),
            200,
          );
        }
        if (u == 'https://megaplay.buzz/embed/mp-1') {
          return http.Response(embedHtml, 200);
        }
        if (u.startsWith('https://megaplay.buzz/stream/getSources')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'sources': <String, dynamic>{
                'file': 'https://cdn.example.com/hls/master.m3u8',
              },
              'tracks': <dynamic>[
                <String, dynamic>{
                  'kind': 'captions',
                  'label': 'English',
                  'file': 'https://cdn.example.com/en.vtt',
                },
              ],
            }),
            200,
          );
        }
        if (u == 'https://cdn.example.com/hls/master.m3u8') {
          return http.Response(masterBody, 200);
        }
        return http.Response('not found: $u', 404);
      });
    }

    Anime jjk() => const Anime(
      id: 'anilist-5',
      anilistId: 5,
      title: 'Jujutsu Kaisen',
      rating: 4.5,
      year: 2020,
      episodeCount: 24,
      genres: <String>['Action'],
      synopsis: 'Cursed spirits.',
      gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    );

    test('justanime down -> Anikoto chain resolves a real stream', () async {
      final MiruroResolver resolver = MiruroResolver(
        client: anikotoClient(),
        anilist: AniListService(client: MockClient((_) async {
          return http.Response('{}', 404);
        })),
      );
      final ResolvedStream? stream = await resolver.resolve(
        anime: jjk(),
        episodeNumber: 1,
        subDub: 'Sub',
      );
      expect(stream, isNotNull);
      expect(stream!.url, 'https://cdn.example.com/hls/1080p/index.m3u8');
      expect(stream.source, 'Anikoto');
      expect(stream.variants.length, 2);
      expect(stream.variants.first.qualityLabel, '1080p');
      expect(stream.subtitles.length, 1);
      expect(stream.subtitles.first.label, 'English');
      expect(stream.headers['Referer'], 'https://megaplay.buzz/');
    });

    test('nothing found anywhere -> null + lastError set', () async {
      final MiruroResolver resolver = MiruroResolver(
        client: MockClient((_) async => http.Response('nope', 404)),
        anilist: AniListService(client: MockClient((_) async {
          return http.Response('{}', 404);
        })),
      );
      expect(
        await resolver.resolve(
          anime: jjk(),
          episodeNumber: 1,
          subDub: 'Sub',
        ),
        isNull,
      );
      expect(resolver.lastError, isNotNull);
    });
  });
}
