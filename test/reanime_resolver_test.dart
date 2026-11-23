import 'dart:convert';
import 'dart:io';

import 'package:anibee/models.dart';
import 'package:anibee/services/reanime_resolver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 0.2.11: ReAnime resolver — flix API -> flixcloud embed -> on-device
/// decrypt. The embed HTML + token API payload come from the golden
/// fixture (real embed page); the flix server list is canned in the
/// shape the live API returned during research.
void main() {
  const Anime jjk = Anime(
    id: 'anilist-113415',
    title: 'Jujutsu Kaisen',
    rating: 4.5,
    year: 2020,
    episodeCount: 24,
    genres: <String>['Action'],
    synopsis: 'Test anime.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    anilistId: 113415,
  );

  List<Map<String, dynamic>> flixServers() => <Map<String, dynamic>>[
    <String, dynamic>{
      'serverName': 'HD-1',
      'dataType': 'sub',
      'dataLink': 'https://flixcloud.cc/e/daeomiul3z2p?v=1',
    },
    <String, dynamic>{
      'serverName': 'HD-2',
      'dataType': 'sub',
      'dataLink': 'https://flixcloud.cc/e/daeomiul3z2p?v=2',
    },
    <String, dynamic>{
      'serverName': 'HD-2',
      'dataType': 'dub',
      'dataLink': 'https://flixcloud.cc/e/daeomiul3z2p?v=2',
    },
  ];

  test('pickServerLink prefers HD-2 and filters by Sub/Dub', () {
    final List<Map<String, dynamic>> servers = flixServers();
    expect(
      ReAnimeResolver.pickServerLink(servers, 'Sub'),
      'https://flixcloud.cc/e/daeomiul3z2p?v=2',
    );
    expect(
      ReAnimeResolver.pickServerLink(servers, 'Dub'),
      'https://flixcloud.cc/e/daeomiul3z2p?v=2',
    );
    expect(
      ReAnimeResolver.pickServerLink(
        servers
            .where(
              (Map<String, dynamic> s) => s['serverName'] == 'HD-1',
            )
            .toList(),
        'Sub',
      ),
      'https://flixcloud.cc/e/daeomiul3z2p?v=1',
    );
    expect(ReAnimeResolver.pickServerLink(<dynamic>[], 'Sub'), isNull);
    expect(
      ReAnimeResolver.pickServerLink(servers, 'Dub') != null &&
          ReAnimeResolver.pickServerLink(
                <dynamic>[
                  <String, dynamic>{
                    'serverName': 'HD-2',
                    'dataType': 'sub',
                    'dataLink': 'https://flixcloud.cc/e/x?v=2',
                  },
                ],
                'Dub',
              ) ==
              null,
      isTrue,
    );
  });

  test('resolve end-to-end against mocked flix + embed + token APIs',
      () async {
    final Map<String, dynamic> golden =
        jsonDecode(
              File('test/fixtures/flixcloud_golden.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final String embedHtml = File(
      'test/fixtures/flixcloud_embed.html',
    ).readAsStringSync();

    final MockClient client = MockClient((http.Request req) async {
      final String url = req.url.toString();
      if (url == 'https://reanime.to/api/flix/113415/1') {
        return http.Response(
          jsonEncode(<String, Object>{
            'success': true,
            'servers': flixServers(),
          }),
          200,
        );
      }
      if (url.startsWith('https://flixcloud.cc/e/')) {
        // Response(String) encodes Latin-1 and throws on the embed's
        // non-ASCII chars — send UTF-8 bytes instead.
        return http.Response.bytes(
          utf8.encode(embedHtml),
          200,
          headers: <String, String>{
            'content-type': 'text/html; charset=utf-8',
          },
        );
      }
      if (url.startsWith('https://flixcloud.cc/api/m3u8/')) {
        return http.Response(
          jsonEncode(golden['tokenData'] as Map<String, dynamic>),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    final ReAnimeResolver resolver = ReAnimeResolver(client: client);
    final stream = await resolver.resolve(
      anime: jjk,
      episodeNumber: 1,
      subDub: 'Sub',
    );
    expect(stream, isNotNull);
    expect(stream!.url, golden['expectedUrl']);
    expect(stream.source, 'ReAnime');
    expect(stream.label, contains('HD-2'));
    expect(stream.headers['Referer'], contains('flixcloud.cc'));
  });

  test('resolve returns null (never a fake stream) when flix has no Sub',
      () async {
    final MockClient client = MockClient((http.Request req) async {
      if (req.url.toString() == 'https://reanime.to/api/flix/113415/1') {
        return http.Response(
          jsonEncode(<String, Object>{
            'success': true,
            'servers': <Object>[
              <String, dynamic>{
                'serverName': 'HD-2',
                'dataType': 'dub',
                'dataLink': 'https://flixcloud.cc/e/x?v=2',
              },
            ],
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });
    final ReAnimeResolver resolver = ReAnimeResolver(client: client);
    final stream = await resolver.resolve(
      anime: jjk,
      episodeNumber: 1,
      subDub: 'Sub',
    );
    expect(stream, isNull);
    expect(resolver.lastError, isNotNull);
  });
}
