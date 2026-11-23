import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

/// AniList GraphQL — metadata, search, lists, progress sync.
/// Public queries need no key; user sync needs an OAuth token (M2).
/// Endpoint: https://graphql.anilist.co (30 req/min, no key).
class AniListService {
  AniListService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String graphqlUrl = 'https://graphql.anilist.co';
  static const String _ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) AniBee/0.2.1';

  /// Search AniList by title. Returns Anime objects with anilistId,
  /// poster, rating, year, episode count, genres, synopsis (HTML
  /// stripped) and MAL id when present.
  Future<List<Anime>> searchAnime(String query, {int page = 1}) async {
    const String q =
        r'query($p:Int,$n:Int,$q:String){Page(page:$p,perPage:$n)'
        r'{pageInfo{hasNextPage}media(search:$q,type:ANIME,isAdult:false)'
        r'{id idMal title{romaji english}coverImage{large extraLarge}'
        r' format episodes seasonYear averageScore genres description}}}';
    final Map<String, dynamic>? data = await _postSafe(q, <String, Object?>{
      'p': page,
      'n': 20,
      'q': query.trim(),
    });
    final List<dynamic> media =
        (data?['Page'] as Map<String, dynamic>?)?['media'] as List<dynamic>? ??
        <dynamic>[];
    return media
        .map((dynamic e) => animeFromMedia(e as Map<String, dynamic>))
        .whereType<Anime>()
        .toList();
  }

  /// Popular anime movies for the Home MOVIES row (0.2.9): AniList
  /// MOVIE-format entries by popularity, 12 per page. A movie is
  /// one "episode" — the API sometimes reports episodes 0/null, so
  /// those are forced to 1 here (Detail/player treat a movie like
  /// any single-episode title). Empty on any failure — the caller
  /// falls back to the bundled list.
  Future<List<Anime>> fetchMovies() async {
    const String q =
        r'query($p:Int,$n:Int){Page(page:$p,perPage:$n)'
        r'{media(type:ANIME,format:MOVIE,sort:POPULARITY_DESC)'
        r'{id idMal title{romaji english}coverImage{large extraLarge}'
        r' format episodes seasonYear averageScore genres description}}}';
    final Map<String, dynamic>? data = await _postSafe(q, <String, Object?>{
      'p': 1,
      'n': 12,
    });
    final List<dynamic> media =
        (data?['Page'] as Map<String, dynamic>?)?['media'] as List<dynamic>? ??
        <dynamic>[];
    return media
        .map((dynamic e) => animeFromMedia(e as Map<String, dynamic>))
        .whereType<Anime>()
        .map(
          (Anime a) => a.episodeCount <= 0 ? a.copyWith(episodeCount: 1) : a,
        )
        .toList();
  }

  /// Per-episode thumbnails for one AniList id (0.2.9): the
  /// `streamingEpisodes` field carries a thumbnail per episode
  /// (titles like "Episode 1"). Returns episode number →
  /// thumbnail URL, only for entries that actually have one.
  /// Empty on any failure — the caller falls back to the anime
  /// poster per episode. [episodeCount] bounds the order-fallback
  /// for unnumbered entries; 0 = no bound.
  Future<Map<int, String>> fetchEpisodeThumbnails(
    int anilistId, {
    int episodeCount = 0,
  }) async {
    const String q =
        r'query($id:Int){Media(id:$id,type:ANIME)'
        r'{streamingEpisodes{title thumbnail url site}}}';
    final Map<String, dynamic>? data = await _postSafe(q, <String, Object?>{
      'id': anilistId,
    });
    final List<dynamic> eps =
        (data?['Media'] as Map<String, dynamic>?)?['streamingEpisodes']
                as List<dynamic>? ??
            <dynamic>[];
    return matchEpisodeThumbnails(
      eps.map((dynamic e) => e as Map<String, dynamic>).toList(),
      episodeCount: episodeCount,
    );
  }

  /// Match AniList `streamingEpisodes` entries to episode numbers.
  /// Pure — unit-tested. Numbered titles ("Episode 1", "Ep. 12",
  /// "12") map to that number; unnumbered entries fill the lowest
  /// unclaimed episode numbers in list order (AniList usually
  /// returns them in episode order). Entries without a thumbnail
  /// are skipped (→ null, poster fallback); out-of-range numbers
  /// are ignored; the first entry wins a duplicate number.
  static Map<int, String> matchEpisodeThumbnails(
    List<Map<String, dynamic>> streaming, {
    int episodeCount = 0,
  }) {
    final Map<int, String> byNumber = <int, String>{};
    final List<String> unnumbered = <String>[];
    for (final Map<String, dynamic> entry in streaming) {
      final String? thumb = entry['thumbnail'] as String?;
      if (thumb == null || thumb.isEmpty) continue;
      final int? number = _episodeNumberFromTitle(
        entry['title'] as String? ?? '',
      );
      if (number != null && number > 0) {
        if (episodeCount > 0 && number > episodeCount) continue;
        byNumber.putIfAbsent(number, () => thumb);
      } else {
        unnumbered.add(thumb);
      }
    }
    if (unnumbered.isNotEmpty && episodeCount > 0) {
      int next = 1;
      for (final String thumb in unnumbered) {
        while (next <= episodeCount && byNumber.containsKey(next)) {
          next++;
        }
        if (next > episodeCount) break;
        byNumber[next] = thumb;
        next++;
      }
    }
    return byNumber;
  }

  /// "Episode 1" → 1, "Ep. 12" → 12, "12" → 12, anything else → null.
  static int? _episodeNumberFromTitle(String title) {
    final RegExpMatch? m = RegExp(
      r'(?:episode|ep\.?)\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(title);
    if (m != null) return int.tryParse(m.group(1)!);
    return int.tryParse(title.trim());
  }

  /// Full detail for one AniList id (includes idMal, episode count rule
  /// inputs, banner). Returns null when the id is unknown.
  Future<Anime?> mediaById(int anilistId) async {
    final String q =
        '{Media(id:$anilistId,type:ANIME){id idMal title{romaji english native}'
        ' coverImage{large extraLarge} bannerImage description status episodes'
        ' nextAiringEpisode{episode} genres seasonYear format averageScore}}';
    final Map<String, dynamic>? data = await _post(q, <String, Object?>{});
    final Map<String, dynamic>? media = data?['Media'] as Map<String, dynamic>?;
    if (media == null) return null;
    return animeFromMedia(media);
  }

  /// Season chain for an anime (0.2.8): seasons are separate AniList
  /// entries linked by SEQUEL/PREQUEL relations (e.g. My Hero Academia
  /// S1 → S2 → S3…). Walks the relations both ways from [anilistId]
  /// and returns the ordered chain, current entry included. Only TV /
  /// TV_SHORT entries with at least one episode count as seasons
  /// (movies, specials, OVAs are not seasons). Returns an empty list
  /// on any failure — the detail screen then shows no selector and
  /// the episode list stays as-is. Each hop is one public GraphQL
  /// query; the walk caps at 12 hops per direction.
  Future<List<SeasonInfo>> fetchSeasons(int anilistId) async {
    try {
      final Map<int, SeasonNode> byId = <int, SeasonNode>{};
      // Walk PREQUELs back to the first season, then SEQUELs forward.
      int? current = anilistId;
      int hops = 0;
      while (current != null && hops < 12 && !byId.containsKey(current)) {
        final SeasonNode? node = await _seasonRelations(current);
        if (node == null) break;
        byId[current] = node;
        current = node.prequelId;
        hops++;
      }
      final List<int> ordered = <int>[];
      int? first = anilistId;
      while (byId[first]?.prequelId != null) {
        first = byId[first]!.prequelId;
      }
      current = first;
      hops = 0;
      while (current != null && hops < 12) {
        final SeasonNode? node = byId[current];
        if (node == null) {
          final SeasonNode? fetched = await _seasonRelations(current);
          if (fetched == null) break;
          byId[current] = fetched;
        }
        ordered.add(current);
        current = byId[current]!.sequelId;
        hops++;
      }
      return buildSeasonChain(anilistId, byId);
    } catch (_) {
      return <SeasonInfo>[];
    }
  }

  /// One hop of the season walk: this entry's own season info plus
  /// the ids of its TV PREQUEL / SEQUEL neighbours (null when none).
  /// Null on any failure (the caller treats it as the end of the chain).
  Future<SeasonNode?> _seasonRelations(int anilistId) async {
    final String q =
        '{Media(id:$anilistId,type:ANIME){id title{romaji english} format'
        ' episodes seasonYear relations{edges{relationType node{id'
        ' title{romaji english} format episodes seasonYear}}}}}';
    final Map<String, dynamic>? data = await _postSafe(q, <String, Object?>{});
    final Map<String, dynamic>? media = data?['Media'] as Map<String, dynamic>?;
    if (media == null) return null;
    final Map<String, dynamic>? title = media['title'] as Map<String, dynamic>?;
    final String name = preferredTitle(title);
    final String format = media['format'] as String? ?? '';
    final int episodes = (media['episodes'] as num?)?.toInt() ?? 0;
    final int? year = (media['seasonYear'] as num?)?.toInt();
    int? prequelId;
    int? sequelId;
    final List<dynamic> edges =
        (media['relations'] as Map<String, dynamic>?)?['edges']
            as List<dynamic>? ??
        <dynamic>[];
    for (final dynamic edge in edges) {
      final Map<String, dynamic> e = edge as Map<String, dynamic>;
      final Map<String, dynamic>? node = e['node'] as Map<String, dynamic>?;
      if (node == null) continue;
      // Record the neighbour whatever its format: a movie can sit
      // between two TV seasons in the relation graph, and the walk
      // passes through it — buildSeasonChain drops non-TV entries
      // from the displayed chain.
      final int? nodeId = (node['id'] as num?)?.toInt();
      if (nodeId == null) continue;
      if (e['relationType'] == 'PREQUEL') {
        prequelId ??= nodeId;
      } else if (e['relationType'] == 'SEQUEL') {
        sequelId ??= nodeId;
      }
    }
    return SeasonNode(
      info: SeasonInfo(
        id: (media['id'] as num).toInt(),
        title: name,
        format: format,
        episodes: episodes,
        year: year,
      ),
      prequelId: prequelId,
      sequelId: sequelId,
    );
  }

  /// Order a walked season map into the chain, current entry included.
  /// Pure — unit-tested. Entries that are not TV seasons or have no
  /// episodes are dropped; a chain of fewer than two entries means
  /// "no selector" (the caller shows nothing).
  static List<SeasonInfo> buildSeasonChain(
    int currentId,
    Map<int, SeasonNode> byId,
  ) {
    int? first = currentId;
    final Set<int> seen = <int>{};
    while (byId[first]?.prequelId != null && !seen.contains(first)) {
      seen.add(first!);
      first = byId[first]!.prequelId;
    }
    final List<SeasonInfo> chain = <SeasonInfo>[];
    int? id = first;
    seen.clear();
    while (id != null && !seen.contains(id)) {
      seen.add(id);
      final SeasonNode? node = byId[id];
      if (node == null) break;
      final SeasonInfo info = node.info;
      if ((info.format == 'TV' || info.format == 'TV_SHORT') &&
          info.episodes > 0) {
        chain.add(info);
      }
      id = node.sequelId;
    }
    if (chain.length < 2) return <SeasonInfo>[];
    return chain;
  }

  /// Resolve an AniList id for a catalogue title (titles without a
  /// stored anilistId). Normalized exact match first, then a contains
  /// match, else the first result. Null when nothing matches.
  Future<int?> resolveId(String title) async {
    final List<Anime> results = await searchAnime(title);
    if (results.isEmpty) return null;
    final String norm = normalizeTitle(title);
    for (final Anime a in results) {
      if (normalizeTitle(a.title) == norm && a.anilistId != null) {
        return a.anilistId;
      }
    }
    for (final Anime a in results) {
      final String n = normalizeTitle(a.title);
      if ((n.contains(norm) || norm.contains(n)) && a.anilistId != null) {
        return a.anilistId;
      }
    }
    return results.first.anilistId;
  }

  /// Logged-in viewer (name + id). Throws on 401 / network failure.
  Future<({int id, String name})> viewer(String token) async {
    const String q = '{Viewer{id name}}';
    final Map<String, dynamic>? data = await _post(
      q,
      <String, Object?>{},
      token: token,
    );
    final Map<String, dynamic>? viewer =
        data?['Viewer'] as Map<String, dynamic>?;
    if (viewer == null) throw const AniListException('No viewer in response');
    return (
      id: (viewer['id'] as num).toInt(),
      name: viewer['name'] as String? ?? 'AniList user',
    );
  }

  /// Push a Collection status to the user's AniList list
  /// ('CURRENT' | 'COMPLETED' | 'PLANNING'). Best-effort: failures are
  /// swallowed so a list tap never breaks the local Collection.
  Future<bool> saveListEntry(
    String token,
    int mediaId,
    String anilistStatus,
  ) async {
    const String mutation =
        r'mutation($id:Int,$status:MediaListStatus){SaveMediaListEntry'
        r'(mediaId:$id,status:$status){id status}}';
    try {
      await _post(mutation, <String, Object?>{
        'id': mediaId,
        'status': anilistStatus,
      }, token: token);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Run a raw GraphQL query (feature services, e.g. airing).
  /// Returns decoded `data`, or null on any failure — never throws.
  Future<Map<String, dynamic>?> queryGraphQL(
    String query,
    Map<String, Object?> variables, {
    String? token,
  }) async {
    try {
      return await _post(query, variables, token: token);
    } catch (_) {
      return null;
    }
  }

  /// Search must never throw: on any failure (rate limit, network,
  /// bad body) it returns an empty list and the search screen falls
  /// back to the local catalogue.
  Future<Map<String, dynamic>?> _postSafe(
    String query,
    Map<String, Object?> variables,
  ) async {
    try {
      return await _post(query, variables);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _post(
    String query,
    Map<String, Object?> variables, {
    String? token,
  }) async {
    final http.Response resp = await _client
        .post(
          Uri.parse(graphqlUrl),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': _ua,
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode(<String, Object>{
            'query': query,
            'variables': variables,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 429) {
      throw const AniListException('Rate limited — try again in a minute');
    }
    if (resp.statusCode != 200) {
      throw AniListException('AniList HTTP ${resp.statusCode}');
    }
    final Map<String, dynamic> decoded =
        jsonDecode(resp.body) as Map<String, dynamic>;
    if (decoded['errors'] != null) {
      final List<dynamic> errors = decoded['errors'] as List<dynamic>;
      final String message = errors.isNotEmpty
          ? (errors.first as Map<String, dynamic>)['message'] as String? ??
                'AniList error'
          : 'AniList error';
      throw AniListException(message);
    }
    return decoded['data'] as Map<String, dynamic>?;
  }

  /// Map one AniList Media object to an [Anime]. Null when the media
  /// has no usable id/title. Pure — unit-tested.
  static Anime? animeFromMedia(Map<String, dynamic> m) {
    final int? id = (m['id'] as num?)?.toInt();
    final Map<String, dynamic>? title = m['title'] as Map<String, dynamic>?;
    final String name = preferredTitle(title);
    if (id == null || name.isEmpty || name == 'Unknown') return null;
    final Map<String, dynamic>? cover =
        m['coverImage'] as Map<String, dynamic>?;
    final String? poster =
        cover?['extraLarge'] as String? ?? cover?['large'] as String?;
    final int? score = (m['averageScore'] as num?)?.toInt();
    final int episodes = (m['episodes'] as num?)?.toInt() ?? 0;
    final int year = (m['seasonYear'] as num?)?.toInt() ?? 0;
    final List<String> genres =
        (m['genres'] as List<dynamic>?)
            ?.map((dynamic e) => e as String)
            .toList() ??
        <String>[];
    return Anime(
      id: 'anilist-$id',
      anilistId: id,
      malId: (m['idMal'] as num?)?.toInt(),
      title: name,
      rating: score != null ? score / 20.0 : 0,
      year: year,
      episodeCount: episodes,
      genres: genres,
      synopsis: cleanDescription(m['description'] as String?),
      posterUrl: poster,
      gradient: const <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    );
  }

  static String preferredTitle(Map<String, dynamic>? t) {
    if (t == null) return 'Unknown';
    final String? english = t['english'] as String?;
    if (english != null && english.isNotEmpty) return english;
    final String? romaji = t['romaji'] as String?;
    if (romaji != null && romaji.isNotEmpty) return romaji;
    final String? native = t['native'] as String?;
    if (native != null && native.isNotEmpty) return native;
    return 'Unknown';
  }

  /// Strip HTML tags + collapse whitespace. Pure — unit-tested.
  static String cleanDescription(String? raw) {
    if (raw == null) return '';
    return raw
        .replaceAll(RegExp('<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

/// One season in a season chain (0.2.8): a separate AniList entry
/// linked by SEQUEL/PREQUEL relations. The label is positional
/// ("Season 1", "Season 2"…) — AniList has no season number field.
class SeasonInfo {
  const SeasonInfo({
    required this.id,
    required this.title,
    required this.format,
    required this.episodes,
    this.year,
  });

  final int id;
  final String title;
  final String format;
  final int episodes;
  final int? year;
}

/// One hop of the season walk: the entry's own info plus its TV
/// PREQUEL / SEQUEL neighbour ids.
class SeasonNode {
  const SeasonNode({required this.info, this.prequelId, this.sequelId});

  final SeasonInfo info;
  final int? prequelId;
  final int? sequelId;
}

/// Lowercase, strip punctuation — title matching for resolveId.
String normalizeTitle(String raw) {
  return raw
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class AniListException implements Exception {
  const AniListException(this.message);
  final String message;
  @override
  String toString() => 'AniListException: $message';
}
