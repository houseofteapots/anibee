import 'dart:convert';

import 'package:http/http.dart' as http;

/// Real Skip Intro / Skip Outro / Skip Recap data from AniSkip
/// (https://api.aniskip.com/v2). 0.2.4 replaces the hardcoded
/// "jump to 85s for the first 95s" button: the player shows
/// "Skip Intro" only while the position is inside the real OP
/// segment, and "Skip Outro" only inside the real ED segment.
/// 0.2.11 adds the recap segment the same way ("Skip Recap").
/// No AniSkip data for an episode -> no button at all.
///
/// API: GET /v2/skip-times/{malId}/{episode}?types[]=op&types[]=ed
///      [&types[]=recap][&episodeLength={seconds}]
/// 200 + {"found": true, "results": [{"skipType": "op",
///      "interval": {"startTime": 0, "endTime": 85}}]}.
/// 404 (or found:false) = no data for this episode — not an error.
class AniSkipService {
  AniSkipService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String baseUrl = 'https://api.aniskip.com/v2';

  Future<SkipTimes?> fetchSkipTimes({
    required int malId,
    required int episode,
    int? episodeLength,
  }) async {
    final StringBuffer url = StringBuffer(
      '$baseUrl/skip-times/$malId/$episode?types[]=op&types[]=ed&types[]=recap',
    );
    if (episodeLength != null && episodeLength > 0) {
      url.write('&episodeLength=$episodeLength');
    }
    http.Response resp;
    try {
      resp = await _client
          .get(
            Uri.parse(url.toString()),
            headers: <String, String>{'User-Agent': 'AniBee/0.2.4'},
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) return null;
    try {
      final Map<String, dynamic> decoded =
          jsonDecode(resp.body) as Map<String, dynamic>;
      if (decoded['found'] != true) return null;
      return SkipTimes.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}

/// The OP / ED / recap intervals for one episode. Any may be null.
class SkipTimes {
  const SkipTimes({this.op, this.ed, this.recap});

  factory SkipTimes.fromJson(Map<String, dynamic> json) {
    SkipInterval? op;
    SkipInterval? ed;
    SkipInterval? recap;
    final List<dynamic> results =
        json['results'] as List<dynamic>? ?? <dynamic>[];
    for (final dynamic r in results) {
      final Map<String, dynamic> m = r as Map<String, dynamic>;
      final Map<String, dynamic>? interval =
          m['interval'] as Map<String, dynamic>?;
      if (interval == null) continue;
      final SkipInterval parsed = SkipInterval(
        startTime: (interval['startTime'] as num?)?.toDouble() ?? 0,
        endTime: (interval['endTime'] as num?)?.toDouble() ?? 0,
      );
      if (m['skipType'] == 'op') {
        op = parsed;
      } else if (m['skipType'] == 'ed') {
        ed = parsed;
      } else if (m['skipType'] == 'recap') {
        recap = parsed;
      }
    }
    return SkipTimes(op: op, ed: ed, recap: recap);
  }

  final SkipInterval? op;
  final SkipInterval? ed;

  /// Recap segment (0.2.11) — "Previously on…" at the episode
  /// start. Null = AniSkip has no recap data for this episode.
  final SkipInterval? recap;

  bool get hasAny => op != null || ed != null || recap != null;
}

/// One skip segment, in seconds from the episode start.
class SkipInterval {
  const SkipInterval({required this.startTime, required this.endTime});

  final double startTime;
  final double endTime;

  bool contains(double positionSeconds) =>
      positionSeconds >= startTime && positionSeconds < endTime;
}
