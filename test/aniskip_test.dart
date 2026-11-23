import 'dart:convert';

import 'package:anibee/services/aniskip_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 0.2.4: real Skip Intro / Skip Outro from AniSkip replaces the
/// hardcoded "jump to 85s for the first 95s" button.
void main() {
  group('AniSkipService.fetchSkipTimes', () {
    test('parses op + ed intervals', () async {
      final MockClient client = MockClient((http.Request req) async {
        expect(req.url.path, '/v2/skip-times/113415/1');
        expect(
          req.url.queryParametersAll['types[]'],
          <String>['op', 'ed', 'recap'],
        );
        return http.Response(
          jsonEncode(<String, Object>{
            'found': true,
            'results': <Object>[
              <String, Object>{
                'skipId': 'a',
                'skipType': 'op',
                'interval': <String, Object>{
                  'startTime': 0,
                  'endTime': 85,
                },
              },
              <String, Object>{
                'skipId': 'b',
                'skipType': 'ed',
                'interval': <String, Object>{
                  'startTime': 1320,
                  'endTime': 1410,
                },
              },
            ],
          }),
          200,
        );
      });
      final AniSkipService service = AniSkipService(client: client);
      final SkipTimes? times = await service.fetchSkipTimes(
        malId: 113415,
        episode: 1,
      );
      expect(times, isNotNull);
      expect(times!.op?.startTime, 0);
      expect(times.op?.endTime, 85);
      expect(times.ed?.startTime, 1320);
      expect(times.ed?.endTime, 1410);
      expect(times.hasAny, isTrue);
    });

    test('episodeLength is sent when provided', () async {
      final MockClient client = MockClient((http.Request req) async {
        expect(req.url.query, contains('episodeLength=1440'));
        return http.Response('{"found":true,"results":[]}', 200);
      });
      final AniSkipService service = AniSkipService(client: client);
      final SkipTimes? times = await service.fetchSkipTimes(
        malId: 113415,
        episode: 1,
        episodeLength: 1440,
      );
      expect(times, isNotNull);
      expect(times!.hasAny, isFalse);
    });

    test('episodeLength is omitted when null (0.2.9: never send it empty)',
        () async {
      // AniSkip 400s on a missing/NaN episodeLength, so the player
      // defers the fetch instead — but the service itself must not
      // invent the parameter when the caller passes null.
      final MockClient client = MockClient((http.Request req) async {
        expect(req.url.query, isNot(contains('episodeLength')));
        return http.Response('{"found":true,"results":[]}', 200);
      });
      final AniSkipService service = AniSkipService(client: client);
      final SkipTimes? times = await service.fetchSkipTimes(
        malId: 113415,
        episode: 1,
      );
      expect(times, isNotNull);
    });

    test('404 means no data for this episode (null), not an error',
        () async {
      final AniSkipService service = AniSkipService(
        client: MockClient(
          (_) async => http.Response('{"found":false,"results":[]}', 404),
        ),
      );
      expect(await service.fetchSkipTimes(malId: 1, episode: 1), isNull);
    });

    test('found:false returns null', () async {
      final AniSkipService service = AniSkipService(
        client: MockClient(
          (_) async => http.Response('{"found":false,"results":[]}', 200),
        ),
      );
      expect(await service.fetchSkipTimes(malId: 1, episode: 1), isNull);
    });

    test('network failure returns null, never throws', () async {
      final AniSkipService service = AniSkipService(
        client: MockClient((_) async => throw Exception('offline')),
      );
      expect(await service.fetchSkipTimes(malId: 1, episode: 1), isNull);
    });

    test('non-200 returns null', () async {
      final AniSkipService service = AniSkipService(
        client: MockClient((_) async => http.Response('boom', 500)),
      );
      expect(await service.fetchSkipTimes(malId: 1, episode: 1), isNull);
    });
  });

  group('SkipInterval.contains', () {
    test('boundaries: start inclusive, end exclusive', () {
      const SkipInterval op = SkipInterval(startTime: 0, endTime: 85);
      expect(op.contains(0), isTrue);
      expect(op.contains(84.9), isTrue);
      expect(op.contains(85), isFalse);
      expect(op.contains(-1), isFalse);
    });
  });

  group('SkipTimes.fromJson', () {
    test('ignores unknown skip types', () {
      final SkipTimes times = SkipTimes.fromJson(<String, dynamic>{
        'found': true,
        'results': <Object>[
          <String, Object>{
            'skipType': 'preview',
            'interval': <String, Object>{'startTime': 10, 'endTime': 20},
          },
        ],
      });
      expect(times.hasAny, isFalse);
    });

    test('0.2.11: parses the recap segment like op/ed', () {
      final SkipTimes times = SkipTimes.fromJson(<String, dynamic>{
        'found': true,
        'results': <Object>[
          <String, Object>{
            'skipType': 'recap',
            'interval': <String, Object>{'startTime': 0, 'endTime': 90},
          },
        ],
      });
      expect(times.recap?.startTime, 0);
      expect(times.recap?.endTime, 90);
      expect(times.hasAny, isTrue);
      expect(times.op, isNull);
      expect(times.ed, isNull);
    });
  });
}
