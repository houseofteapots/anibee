import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'anilist_service.dart';
import 'miruro_resolver.dart';

/// AniZone (anizone.to) — real on-device resolver (0.2.12).
///
/// Chain: AniList id -> title variants (romaji/english/native) ->
/// `GET /anime?search=<q>` (Laravel page, `items: JSON.parse(...)`)
/// -> title/year/format match -> `GET /anime/{slug}` (episode list,
/// 24 per page, Livewire pagination for long anime) ->
/// `GET /anime/{slug}/{episode}` (`vidstackPlayer(JSON.parse(...))`)
/// -> direct HLS `src` + subtitle files.
///
/// Verified live from the VM 2026-11-23 (Naruto): search returns the
/// series (slug spjuxray, 220 eps), the series page lists episodes,
/// the watch page yields a real master.m3u8 on seiryuu.vid-cdn.xyz
/// (200) with English subtitles. Sub-only — AniZone carries no Dub
/// audio; a Dub request fails honestly instead of silently playing
/// Sub.
///
/// Simplified port of Anivexa's providers/anizone.js: same page
/// shapes, same Livewire continuation, same 0.82 confidence
/// threshold — but a lighter title scorer (exact match + word
/// Jaccard instead of the full alias/romanization scorer) and no
/// server-side cache. Never returns a fake URL: every failure sets
/// [lastError] and returns null.
class AniZoneResolver {
  AniZoneResolver({http.Client? client, AniListService? anilist})
    : _client = client ?? http.Client(),
      _anilist = anilist ?? AniListService();

  final http.Client _client;
  final AniListService _anilist;

  static const String _base = 'https://anizone.to';
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// Confidence floor for the series match (Anivexa: 0.82).
  static const double kMinScore = 0.82;

  /// Title similarity below this is not a candidate at all
  /// (Anivexa: 0.68).
  static const double kMinTitleScore = 0.68;

  String? lastError;

  /// Resolve a playable stream for [anime] episode [episodeNumber].
  /// [subDub] is 'Sub' or 'Dub' (Dub always fails honestly — Sub-only).
  Future<ResolvedStream?> resolve({
    required Anime anime,
    required int episodeNumber,
    required String subDub,
  }) async {
    lastError = null;
    if (subDub == 'Dub') {
      lastError = 'AniZone has subtitles only — no Dub.';
      return null;
    }
    final int? anilistId;
    if (anime.anilistId != null) {
      anilistId = anime.anilistId;
    } else {
      final ({int? id, bool lookupFailed}) detail =
          await _anilist.resolveIdDetailed(anime.title);
      if (detail.lookupFailed) {
        lastError = 'AniList lookup failed — check your connection '
            'and try again.';
        return null;
      }
      anilistId = detail.id;
    }
    if (anilistId == null) {
      lastError = 'Could not find "${anime.title}" on AniList.';
      return null;
    }
    try {
      final AnilistIdentity? identity =
          await _anilist.mediaIdentity(anilistId);
      final List<String> titles = <String>[
        ...?identity?.titles,
        anime.title,
      ];
      final Map<String, String> jar = <String, String>{};
      final _SeriesMatch? match = await _matchSeries(
        titles: titles,
        year: identity?.year ?? (anime.year > 0 ? anime.year : null),
        format: _formatName(identity?.format),
        expectedEpisodes: identity?.episodes ??
            (anime.episodeCount > 0 ? anime.episodeCount : null),
        status: identity?.status,
        episodeNumber: episodeNumber,
        jar: jar,
      );
      if (match == null) return null;
      final int? sourceNumber = await _findEpisodeNumber(
        match.slug,
        episodeNumber,
        jar,
      );
      if (sourceNumber == null) {
        lastError =
            'AniZone has no episode $episodeNumber for "${anime.title}".';
        return null;
      }
      return await _watch(match.slug, sourceNumber, anime, jar);
    } catch (e) {
      lastError ??= 'AniZone failed: $e';
      return null;
    }
  }

  // ------------------------------------------------------------ search

  /// Search AniZone for each title variant (romaji first) and pick
  /// the best-scoring series. Null + [lastError] when nothing is
  /// confident enough — never a guess.
  Future<_SeriesMatch?> _matchSeries({
    required List<String> titles,
    required int? year,
    required String? format,
    required int? expectedEpisodes,
    required String? status,
    required int episodeNumber,
    required Map<String, String> jar,
  }) async {
    final Map<String, AniZoneCandidate> found = {};
    for (final String q in titles) {
      if (q.trim().isEmpty) continue;
      try {
        for (final AniZoneCandidate c in await _search(q, jar)) {
          found.putIfAbsent(c.slug, () => c);
        }
      } catch (_) {
        // One bad search query must not kill the others.
        continue;
      }
      // An exact title hit on the first query is enough — the
      // remaining variants only add duplicates.
      if (found.values.any(
        (c) => normalizeTitle(c.title) == normalizeTitle(titles.first),
      )) {
        break;
      }
    }
    final List<_Scored> scored = <_Scored>[];
    for (final AniZoneCandidate c in found.values) {
      final _Scored? s = _scoreCandidate(
        c,
        titles: titles,
        year: year,
        format: format,
        expectedEpisodes: expectedEpisodes,
        status: status,
        episodeNumber: episodeNumber,
      );
      if (s != null) scored.add(s);
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    if (scored.isEmpty) {
      lastError = 'Could not find "${titles.last}" on AniZone.';
      return null;
    }
    final _Scored best = scored.first;
    final _Scored? runnerUp = scored.length > 1 ? scored[1] : null;
    if (best.score < kMinScore ||
        (runnerUp != null && best.score - runnerUp.score < 0.08)) {
      lastError = 'Could not find "${titles.last}" on AniZone.';
      return null;
    }
    return _SeriesMatch(slug: best.candidate.slug, title: best.candidate.title);
  }

  Future<List<AniZoneCandidate>> _search(
    String query,
    Map<String, String> jar,
  ) async {
    final http.Response resp = await _client
        .get(
          Uri.parse('$_base/anime?search=${Uri.encodeQueryComponent(query)}'),
          headers: _pageHeaders(jar),
        )
        .timeout(const Duration(seconds: 15));
    _storeCookies(resp, jar);
    if (resp.statusCode != 200) {
      throw Exception('AniZone search HTTP ${resp.statusCode}');
    }
    return parseSearchItems(resp.body);
  }

  /// Parse the `items: JSON.parse('...')` block of a search page.
  /// Pure — unit-tested.
  static List<AniZoneCandidate> parseSearchItems(String html) {
    final List<dynamic>? items = _jsonArgument(html, 'items');
    if (items == null) return <AniZoneCandidate>[];
    final List<AniZoneCandidate> out = <AniZoneCandidate>[];
    for (final dynamic raw in items) {
      final Map<String, dynamic>? item = raw as Map<String, dynamic>?;
      if (item == null) continue;
      final String slug = (item['slug'] as String?) ?? '';
      if (!RegExp(r'^[a-z0-9-]+$', caseSensitive: false).hasMatch(slug)) {
        continue;
      }
      final Map<String, dynamic>? titleList =
          item['title_list'] as Map<String, dynamic>?;
      final String title = _pickTitle(titleList) ??
          (item['main_title'] as String?) ??
          '';
      if (title.isEmpty) continue;
      final List<String> titles = <String>{
        if ((item['main_title'] as String?)?.isNotEmpty ?? false)
          item['main_title'] as String,
        ...?titleList?.values.whereType<String>(),
      }.toList();
      out.add(
        AniZoneCandidate(
          slug: slug,
          title: title,
          titles: titles,
          type: _formatName(item['type'] as String?),
          year: (item['start_year'] as num?)?.toInt(),
          episodeCount: (item['episode_count'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return out;
  }

  /// Score one search candidate (simplified Anivexa validate):
  /// title similarity + format + year + episode coverage. Null when
  /// the candidate is rejected outright. Pure — unit-tested.
  static _Scored? _scoreCandidate(
    AniZoneCandidate c,
    {
    required List<String> titles,
    required int? year,
    required String? format,
    required int? expectedEpisodes,
    required String? status,
    required int episodeNumber,
  }) {
    final double titleScore = _titleScore(titles, c);
    if (titleScore < kMinTitleScore) return null;
    if (format != null &&
        format.isNotEmpty &&
        c.type.isNotEmpty &&
        format != c.type) {
      return null;
    }
    if (year != null && c.year != null && year != c.year) return null;
    if (c.episodeCount < episodeNumber) return null;
    double coverage = 0.5;
    if (expectedEpisodes != null && expectedEpisodes >= 1) {
      if (c.episodeCount < 1) return null;
      if (status != 'FINISHED') {
        coverage = 1;
      } else if (expectedEpisodes < 6) {
        coverage = 1;
      } else {
        final int needed = (expectedEpisodes * 0.8).ceil();
        coverage = (c.episodeCount / needed).clamp(0.0, 1.0);
        if (expectedEpisodes >= 6 && coverage < 0.8) return null;
      }
    }
    final double score = titleScore * 0.72 +
        (format != null && format.isNotEmpty && c.type == format
            ? 0.14
            : 0.07) +
        (year != null && c.year == year ? 0.10 : 0.04) +
        coverage * 0.04;
    return _Scored(candidate: c, titleScore: titleScore, score: score);
  }

  /// Best title similarity over all (AniList title × candidate title)
  /// pairs. 1.0 on a normalized exact match, else word-set Jaccard.
  /// Pure — unit-tested.
  static double _titleScore(List<String> titles, AniZoneCandidate c) {
    double best = 0;
    final List<String> cTitles = <String>[c.title, ...c.titles];
    for (final String a in titles) {
      final String na = normalizeTitle(a);
      if (na.isEmpty) continue;
      for (final String b in cTitles) {
        final String nb = normalizeTitle(b);
        if (nb.isEmpty) continue;
        if (na == nb) return 1.0;
        final Set<String> aw = na.split(' ').toSet();
        final Set<String> bw = nb.split(' ').toSet();
        final int inter = aw.intersection(bw).length;
        final int union = aw.union(bw).length;
        final double j = union == 0 ? 0 : inter / union;
        if (j > best) best = j;
      }
    }
    return best;
  }

  // ------------------------------------------------------------ series

  /// Find the requested episode's source number on the series page,
  /// paging through Livewire continuations when the episode is past
  /// the first 24. Null when the episode is not listed.
  Future<int?> _findEpisodeNumber(
    String slug,
    int episodeNumber,
    Map<String, String> jar,
  ) async {
    final http.Response first = await _client
        .get(Uri.parse('$_base/anime/$slug'), headers: _pageHeaders(jar))
        .timeout(const Duration(seconds: 15));
    _storeCookies(first, jar);
    if (first.statusCode != 200) {
      throw Exception('AniZone series HTTP ${first.statusCode}');
    }
    final List<dynamic>? items = _jsonArgument(first.body, 'items');
    if (items == null) throw const FormatException('AniZone page payload');
    final int? found = _episodeNumberIn(items, episodeNumber);
    if (found != null) return found;
    String snapshot = _snapshot(first.body);
    String? cursor = _cursor(first.body);
    bool hasMore = _hasMore(first.body);
    final String csrf = _csrf(first.body);
    if (snapshot.isEmpty || cursor == null || !hasMore || csrf.isEmpty) {
      return null;
    }
    // Livewire continuation: at most 10 more pages (240 episodes).
    for (int page = 0; page < 10 && hasMore && cursor != null; page++) {
      final http.Response resp = await _client
          .post(
            Uri.parse('$_base/livewire/update'),
            headers: <String, String>{
              'User-Agent': _ua,
              'Accept': 'application/json, text/plain, */*',
              'Content-Type': 'application/json',
              'X-Livewire': '',
              'X-CSRF-TOKEN': csrf,
              'X-Requested-With': 'XMLHttpRequest',
              'Origin': _base,
              'Referer': '$_base/anime/$slug',
              if (jar.isNotEmpty) 'Cookie': _cookieHeader(jar),
            },
            body: jsonEncode(<String, Object>{
              'components': <Object>[
                <String, Object>{
                  'snapshot': snapshot,
                  'updates': <String, Object>{},
                  'calls': <Object>[
                    <String, Object>{
                      'path': '',
                      'method': 'loadPage',
                      'params': <Object>[cursor],
                    },
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
      _storeCookies(resp, jar);
      if (resp.statusCode != 200) {
        throw Exception('AniZone Livewire HTTP ${resp.statusCode}');
      }
      final Map<String, dynamic> payload =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final Map<String, dynamic>? component =
          (payload['components'] as List<dynamic>?)?.firstOrNull
              as Map<String, dynamic>?;
      final List<dynamic>? dispatches =
          (component?['effects'] as Map<String, dynamic>?)?['dispatches']
              as List<dynamic>?;
      final Map<String, dynamic>? dispatch = dispatches
          ?.whereType<Map<String, dynamic>>()
          .where((d) => d['name'] == 'items-loaded')
          .firstOrNull;
      final Map<String, dynamic>? params =
          dispatch?['params'] as Map<String, dynamic>?;
      final List<dynamic>? nextItems = params?['items'] as List<dynamic>?;
      if (component?['snapshot'] == null ||
          params == null ||
          nextItems == null) {
        throw const FormatException('AniZone page continuation payload');
      }
      final int? hit = _episodeNumberIn(nextItems, episodeNumber);
      if (hit != null) return hit;
      snapshot = component!['snapshot'] as String;
      cursor = params['nextCursor'] as String?;
      hasMore = params['hasMore'] as bool? ?? false;
    }
    return null;
  }

  static int? _episodeNumberIn(List<dynamic> items, int episodeNumber) {
    for (final dynamic raw in items) {
      final Map<String, dynamic>? item = raw as Map<String, dynamic>?;
      if (item == null) continue;
      final int? n = _episodeNumber(item);
      if (n == episodeNumber && _hasSub(item)) return n;
    }
    return null;
  }

  static int? _episodeNumber(Map<String, dynamic> item) {
    final int? direct = int.tryParse((item['slug'] as String?) ?? '');
    if (direct != null && direct > 0) return direct;
    final String url = (item['url'] as String?) ?? '';
    final RegExpMatch? m = RegExp(r'/(\d+)/?$').firstMatch(url);
    final int? fromUrl = m == null ? null : int.tryParse(m.group(1)!);
    return fromUrl != null && fromUrl > 0 ? fromUrl : null;
  }

  static bool _hasSub(Map<String, dynamic> item) {
    return ((item['videos_count'] as num?)?.toInt() ?? 0) > 0;
  }

  // ------------------------------------------------------------ watch

  Future<ResolvedStream?> _watch(
    String slug,
    int episodeNumber,
    Anime anime,
    Map<String, String> jar,
  ) async {
    final http.Response resp = await _client
        .get(
          Uri.parse('$_base/anime/$slug/$episodeNumber'),
          headers: _pageHeaders(jar, referer: '$_base/anime/$slug'),
        )
        .timeout(const Duration(seconds: 15));
    _storeCookies(resp, jar);
    if (resp.statusCode != 200) {
      lastError = 'AniZone player failed for episode $episodeNumber.';
      return null;
    }
    final Map<String, dynamic>? player = _playerData(resp.body);
    final String? src = player?['src'] as String?;
    if (src == null || src.isEmpty) {
      lastError = 'AniZone player failed for episode $episodeNumber.';
      return null;
    }
    final List<SubtitleInfo> subtitles = <SubtitleInfo>[];
    final List<dynamic> subs =
        player?['subtitles'] as List<dynamic>? ?? <dynamic>[];
    for (final dynamic raw in subs) {
      final Map<String, dynamic>? s = raw as Map<String, dynamic>?;
      final String? file = s?['file'] as String?;
      if (file == null || file.isEmpty) continue;
      subtitles.add(
        SubtitleInfo(
          label: (s?['title'] as String?)?.isNotEmpty ?? false
              ? s!['title'] as String
              : 'English',
          url: _normalizeUrl(file),
        ),
      );
    }
    return ResolvedStream(
      url: _normalizeUrl(src),
      label: 'AniZone Sub',
      source: 'AniZone',
      headers: <String, String>{
        'User-Agent': _ua,
        'Referer': '$_base/',
      },
      subtitles: subtitles,
    );
  }

  // ------------------------------------------------------------ parsing

  Map<String, String> _pageHeaders(
    Map<String, String> jar, {
    String? referer,
  }) {
    return <String, String>{
      'User-Agent': _ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,'
          '*/*;q=0.8',
      'Referer': referer ?? '$_base/',
      if (jar.isNotEmpty) 'Cookie': _cookieHeader(jar),
    };
  }

  static String _cookieHeader(Map<String, String> jar) {
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  static void _storeCookies(
    http.Response resp,
    Map<String, String> jar,
  ) {
    final String? raw = resp.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    // package:http joins multiple Set-Cookie headers with commas;
    // a new cookie starts at a comma followed by `name=`.
    for (final String part in raw.split(RegExp(r',\s*(?=[^;,=\s]+=[^;]*)'))) {
      final RegExpMatch? m =
          RegExp(r'^\s*([^=;\s]+)=([^;]*)').firstMatch(part);
      if (m != null) jar[m.group(1)!] = m.group(2)!;
    }
  }

  /// `name: JSON.parse('...')` block, JS-string-decoded then parsed.
  /// Pure — unit-tested.
  static List<dynamic>? _jsonArgument(String html, String name) {
    final RegExp pattern = RegExp(
      "${RegExp.escape(name)}\\s*:\\s*JSON\\.parse\\('((?:[^'\\\\]|\\\\.)*)'\\)",
      caseSensitive: false,
    );
    final RegExpMatch? m = pattern.firstMatch(html);
    if (m == null) return null;
    try {
      final dynamic decoded = jsonDecode(_decodeJsString(m.group(1)!));
      return decoded as List<dynamic>?;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _playerData(String html) {
    final RegExp pattern = RegExp(
      r"vidstackPlayer\s*\(\s*JSON\.parse\('((?:[^'\\]|\\.)*)'\)\s*\)",
      caseSensitive: false,
    );
    final RegExpMatch? m = pattern.firstMatch(html);
    if (m == null) return null;
    try {
      return jsonDecode(_decodeJsString(m.group(1)!))
          as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Decode a JS single-quoted string literal's escapes (`\/`,
  /// `\uXXXX`, `\\`, `\"`, `\'`, `\n`…). Pure — unit-tested.
  static String _decodeJsString(String raw) {
    final StringBuffer out = StringBuffer();
    int i = 0;
    while (i < raw.length) {
      final String ch = raw[i];
      if (ch != '\\' || i + 1 >= raw.length) {
        out.write(ch);
        i++;
        continue;
      }
      final String next = raw[i + 1];
      if (next == 'u' && i + 6 <= raw.length) {
        final int? code = int.tryParse(raw.substring(i + 2, i + 6), radix: 16);
        if (code != null) {
          out.write(String.fromCharCode(code));
          i += 6;
          continue;
        }
      }
      if (next == '/') {
        out.write('/');
      } else if (next == '\\') {
        out.write('\\');
      } else if (next == '"') {
        out.write('"');
      } else if (next == "'") {
        out.write("'");
      } else if (next == 'n') {
        out.write('\n');
      } else if (next == 't') {
        out.write('\t');
      } else if (next == 'r') {
        out.write('\r');
      } else {
        out.write(next);
      }
      i += 2;
    }
    return out.toString();
  }

  static String _snapshot(String html) {
    final Iterable<RegExpMatch> matches = RegExp(
      r'wire:snapshot="([^"]*)"',
      caseSensitive: false,
    ).allMatches(html);
    for (final RegExpMatch m in matches) {
      final String raw = m.group(1)!;
      if (raw.contains('pages.anime-detail')) {
        return raw
            .replaceAll('&quot;', '"')
            .replaceAll('&amp;', '&')
            .replaceAll('&#039;', "'")
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>');
      }
    }
    return '';
  }

  static String? _cursor(String html) {
    return RegExp(
      r"nextCursor:\s*'([^']+)'",
      caseSensitive: false,
    ).firstMatch(html)?.group(1);
  }

  static bool _hasMore(String html) {
    return RegExp(r'hasMore:\s*true', caseSensitive: false).hasMatch(html);
  }

  static String _csrf(String html) {
    return RegExp(
      r'csrf-token"\s+content="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html)?.group(1) ?? '';
  }

  static String? _pickTitle(Map<String, dynamic>? titleList) {
    if (titleList == null) return null;
    for (final String k in <String>['1', '5', '8']) {
      final String? v = titleList[k] as String?;
      if (v != null && v.isNotEmpty) return v;
    }
    for (final dynamic v in titleList.values) {
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  /// AniList format -> AniZone type token ('TV' -> 'tv', …).
  /// Pure — unit-tested.
  static String _formatName(String? value) {
    final String type = (value ?? '').toLowerCase();
    if (type.contains('special')) return 'special';
    if (type.contains('movie')) return 'movie';
    if (type.contains('ova')) return 'ova';
    if (type.contains('web') || type.contains('ona')) return 'ona';
    if (type.contains('tv')) return 'tv';
    return '';
  }

  static String _normalizeUrl(String value) {
    return value.replaceAll(RegExp(r'\\+/'), '/');
  }
}

class AniZoneCandidate {
  const AniZoneCandidate({
    required this.slug,
    required this.title,
    required this.titles,
    required this.type,
    required this.year,
    required this.episodeCount,
  });

  final String slug;
  final String title;
  final List<String> titles;
  final String type;
  final int? year;
  final int episodeCount;
}

class _Scored {
  const _Scored({
    required this.candidate,
    required this.titleScore,
    required this.score,
  });

  final AniZoneCandidate candidate;
  final double titleScore;
  final double score;
}

class _SeriesMatch {
  const _SeriesMatch({required this.slug, required this.title});

  final String slug;
  final String title;
}
