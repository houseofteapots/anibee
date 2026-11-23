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
        r' trailer{id site} format episodes seasonYear averageScore genres description}}}';
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

  /// Full detail for one AniList id (includes idMal, episode count rule
  /// inputs, banner). Returns null when the id is unknown.
  Future<Anime?> mediaById(int anilistId) async {
    final String q =
        '{Media(id:$anilistId,type:ANIME){id idMal title{romaji english native}'
        ' coverImage{large extraLarge} bannerImage description status episodes'
        ' trailer{id site} nextAiringEpisode{episode} genres seasonYear format averageScore}}';
    final Map<String, dynamic>? data = await _post(q, <String, Object?>{});
    final Map<String, dynamic>? media =
        data?['Media'] as Map<String, dynamic>?;
    if (media == null) return null;
    return animeFromMedia(media);
  }

  /// Real trailer for one AniList id (0.2.4): AniList's trailer field
  /// ({id, site} — usually YouTube). Returns null when the title has
  /// no trailer or the lookup fails; the detail banner then shows the
  /// poster image only — never the old sample video.
  Future<({String site, String videoId})?> fetchTrailer(
    int anilistId,
  ) async {
    final Map<String, dynamic>? data = await _postSafe(
      '{Media(id:$anilistId,type:ANIME){trailer{id site}}}',
      <String, Object?>{},
    );
    final Map<String, dynamic>? media =
        data?['Media'] as Map<String, dynamic>?;
    final Map<String, dynamic>? trailer =
        media?['trailer'] as Map<String, dynamic>?;
    final String? site = trailer?['site'] as String?;
    final String? id = trailer?['id'] as String?;
    if (site == null || site.isEmpty || id == null || id.isEmpty) {
      return null;
    }
    return (site: site, videoId: id);
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
      await _post(
        mutation,
        <String, Object?>{'id': mediaId, 'status': anilistStatus},
        token: token,
      );
      return true;
    } catch (_) {
      return false;
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
    final Map<String, dynamic>? title =
        m['title'] as Map<String, dynamic>?;
    final String name = _preferredTitle(title);
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
      // 0.2.4: the REAL trailer (YouTube watch URL) when AniList has
      // one; null otherwise — the sample video is gone everywhere.
      trailerUrl: trailerWatchUrl(m['trailer'] as Map<String, dynamic>?),
    );
  }

  static String _preferredTitle(Map<String, dynamic>? t) {
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

/// Lowercase, strip punctuation — title matching for resolveId.
String normalizeTitle(String raw) {
  return raw
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// YouTube watch URL for an AniList trailer object ({id, site}).
/// Only YouTube is playable in-app; any other site (or a missing
/// trailer) returns null — the caller shows the banner image only.
String? trailerWatchUrl(Map<String, dynamic>? trailer) {
  final String? site = trailer?['site'] as String?;
  final String? id = trailer?['id'] as String?;
  if (site != 'youtube' || id == null || id.isEmpty) return null;
  return 'https://www.youtube.com/watch?v=$id';
}

/// Video id from a YouTube watch / youtu.be / embed URL. Null when
/// the URL is not a YouTube link.
String? youtubeVideoIdFromUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  final Uri uri = Uri.tryParse(url) ?? Uri();
  if (uri.host.endsWith('youtube.com')) {
    final String? v = uri.queryParameters['v'];
    if (v != null && v.isNotEmpty) return v;
    // /embed/<id>
    final List<String> segments = uri.pathSegments;
    final int embedIndex = segments.indexOf('embed');
    if (embedIndex >= 0 && embedIndex + 1 < segments.length) {
      return segments[embedIndex + 1];
    }
    return null;
  }
  if (uri.host.endsWith('youtu.be') && uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.first;
  }
  return null;
}

/// YouTube embed URL for the in-app trailer player. Muted + looping
/// with no YT chrome for the inline banner; sound + controls for the
/// fullscreen trailer route.
String youtubeEmbedUrl(
  String videoId, {
  bool muted = true,
  bool controls = false,
}) {
  final String mute = muted ? '1' : '0';
  final String showControls = controls ? '1' : '0';
  return 'https://www.youtube.com/embed/$videoId'
      '?autoplay=1&mute=$mute&loop=1&playlist=$videoId'
      '&controls=$showControls&rel=0&playsinline=1';
}

class AniListException implements Exception {
  const AniListException(this.message);
  final String message;
  @override
  String toString() => 'AniListException: $message';
}
