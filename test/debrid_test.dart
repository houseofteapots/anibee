import 'dart:convert';

import 'package:anibee/services/debrid_service.dart';
import 'package:anibee/services/miruro_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// M2: TorBox + Real-Debrid real API clients + Nyaa RSS parsing.
/// Network is fully mocked; the flows are verified step by step
/// (verify -> search -> add -> poll -> direct link).
void main() {
  group('parseNyaaRss', () {
    const String rss =
        '<?xml version="1.0"?><rss><channel>'
        '<item><title><![CDATA[[HorribleSubs] Frieren - 01 [1080p]]]></title>'
        '<nyaa:infoHash>ABCDEF0123456789ABCDEF0123456789ABCDEF01</nyaa:infoHash>'
        '<nyaa:seeders>120</nyaa:seeders></item>'
        '<item><title>[SubsPlease] Frieren - 01 (1080p)</title>'
        '<nyaa:infoHash>1111111111111111111111111111111111111111</nyaa:infoHash>'
        '<nyaa:seeders>450</nyaa:seeders></item>'
        '<item><title>No hash here</title></item>'
        '</channel></rss>';

    test('parses items, sorts by seeders, builds magnets', () {
      final List<NyaaTorrent> torrents = DebridService.parseNyaaRss(rss);
      expect(torrents.length, 2);
      expect(torrents[0].seeders, 450);
      expect(torrents[0].infoHash, '1111111111111111111111111111111111111111');
      expect(torrents[0].magnet, startsWith('magnet:?xt=urn:btih:1111'));
      // CDATA stripped, hash lowercased.
      expect(torrents[1].title, '[HorribleSubs] Frieren - 01 [1080p]');
      expect(
        torrents[1].infoHash,
        'abcdef0123456789abcdef0123456789abcdef01',
      );
      expect(torrents[1].seeders, 120);
    });

    test('empty feed returns empty', () {
      expect(DebridService.parseNyaaRss('<rss></rss>'), isEmpty);
    });
  });

  group('verify', () {
    test('TorBox /user/me success returns the username', () async {
      final DebridService svc = DebridService(
        client: MockClient((http.Request req) async {
          expect(req.url.path, '/v1/api/user/me');
          expect(req.headers['Authorization'], 'Bearer tb-key');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{'email': 'suresh@example.com'},
            }),
            200,
          );
        }),
      );
      expect(await svc.verifyTorbox('tb-key'), 'suresh@example.com');
    });

    test('TorBox 401 returns null', () async {
      final DebridService svc = DebridService(
        client: MockClient((_) async => http.Response('unauthorized', 401)),
      );
      expect(await svc.verifyTorbox('bad-key'), isNull);
    });

    test('Real-Debrid /user success returns the username', () async {
      final DebridService svc = DebridService(
        client: MockClient((http.Request req) async {
          expect(req.url.path, '/rest/1.0/user');
          expect(req.headers['Authorization'], 'Bearer rd-token');
          return http.Response(
            jsonEncode(<String, dynamic>{'username': 'suresh_rd'}),
            200,
          );
        }),
      );
      expect(await svc.verifyRealDebrid('rd-token'), 'suresh_rd');
    });

    test('Real-Debrid 401 returns null', () async {
      final DebridService svc = DebridService(
        client: MockClient((_) async => http.Response('unauthorized', 401)),
      );
      expect(await svc.verifyRealDebrid('bad-token'), isNull);
    });
  });

  group('resolveEpisode — TorBox end to end (mocked)', () {
    const String nyaaRss =
        '<rss><channel><item>'
        '<title>[SubsPlease] Frieren - 01 (1080p)</title>'
        '<nyaa:infoHash>aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa</nyaa:infoHash>'
        '<nyaa:seeders>450</nyaa:seeders>'
        '</item></channel></rss>';

    MockClient torboxClient() {
      return MockClient((http.Request req) async {
        final String u = req.url.toString();
        if (u.startsWith('https://nyaa.si/')) {
          return http.Response(nyaaRss, 200);
        }
        if (u.contains('/torrents/checkcached')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <dynamic>[
                <String, dynamic>{'name': 'Frieren - 01.mkv', 'size': 100},
              ],
            }),
            200,
          );
        }
        if (u.endsWith('/torrents/createtorrent')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{'torrent_id': 7},
            }),
            200,
          );
        }
        if (u.contains('/torrents/mylist')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'success': true,
              'data': <String, dynamic>{
                'download_state': 'downloaded',
                'progress': 1,
                'files': <dynamic>[
                  <String, dynamic>{
                    'id': 3,
                    'name': 'Frieren - 01.mkv',
                    'size': 900000000,
                  },
                ],
              },
            }),
            200,
          );
        }
        if (u.contains('/torrents/requestdl')) {
          return http.Response('', 302, headers: <String, String>{
            'location': 'https://dl.torbox.app/play/abc123/Frieren-01.mkv',
          });
        }
        return http.Response('not found: $u', 404);
      });
    }

    test('cached torrent -> direct playable link', () async {
      final DebridService svc = DebridService(client: torboxClient());
      final ResolvedStream? stream = await svc.resolveEpisode(
        service: 'torbox',
        apiKey: 'tb-key',
        title: 'Frieren',
        episode: 1,
      );
      expect(stream, isNotNull);
      expect(
        stream!.url,
        'https://dl.torbox.app/play/abc123/Frieren-01.mkv',
      );
      expect(stream.source, 'TorBox');
    });

    test('no Nyaa results -> null', () async {
      final DebridService svc = DebridService(
        client: MockClient((http.Request req) async {
          if (req.url.toString().startsWith('https://nyaa.si/')) {
            return http.Response('<rss><channel></channel></rss>', 200);
          }
          return http.Response('nope', 404);
        }),
      );
      expect(
        await svc.resolveEpisode(
          service: 'torbox',
          apiKey: 'tb-key',
          title: 'No Such Anime',
          episode: 1,
        ),
        isNull,
      );
    });
  });

  group('resolveEpisode — Real-Debrid end to end (mocked)', () {
    const String nyaaRss =
        '<rss><channel><item>'
        '<title>[SubsPlease] Frieren - 01 (1080p)</title>'
        '<nyaa:infoHash>bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb</nyaa:infoHash>'
        '<nyaa:seeders>300</nyaa:seeders>'
        '</item></channel></rss>';

    MockClient rdClient() {
      return MockClient((http.Request req) async {
        final String u = req.url.toString();
        if (u.startsWith('https://nyaa.si/')) {
          return http.Response(nyaaRss, 200);
        }
        if (u.endsWith('/torrents/addMagnet')) {
          return http.Response(
            jsonEncode(<String, dynamic>{'id': 'rd-99'}),
            201,
          );
        }
        if (u.contains('/torrents/selectFiles/')) {
          return http.Response('', 204);
        }
        if (u.contains('/torrents/info/')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'status': 'downloaded',
              'links': <dynamic>[
                'https://real-debrid.com/d/FILE1',
              ],
            }),
            200,
          );
        }
        if (u.endsWith('/unrestrict/link')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'download': 'https://dl.real-debrid.com/Frieren-01.mkv',
            }),
            200,
          );
        }
        return http.Response('not found: $u', 404);
      });
    }

    test('addMagnet -> selectFiles -> poll -> unrestrict', () async {
      final DebridService svc = DebridService(client: rdClient());
      final ResolvedStream? stream = await svc.resolveEpisode(
        service: 'realdebrid',
        apiKey: 'rd-token',
        title: 'Frieren',
        episode: 1,
      );
      expect(stream, isNotNull);
      expect(stream!.url, 'https://dl.real-debrid.com/Frieren-01.mkv');
      expect(stream.source, 'Real-Debrid');
    });
  });
}
