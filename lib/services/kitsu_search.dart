import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

/// Kitsu search fallback (0.2.15) — the second metadata source for the
/// Search screen.
///
/// WHY: AniList's `search:` GraphQL query returns an EMPTY media list
/// on the user's phone ("noblesse" → "AniList: ok · 0 from AniList",
/// raw == mapped == 0 — the call succeeds, AniList just gives nothing
/// back), and the VM cannot test AniList live (graphql.anilist.co is
/// Cloudflare-blocked from the VM). Kitsu (`kitsu.io/api/edge/anime`)
/// is public, keyless, and VERIFIED LIVE from the VM for the exact
/// titles the user reported missing — "noblesse" → Noblesse,
/// "black clover" → the TV series AND the "Sword of the Wizard King"
/// movie, "the garden of words" → the movie — each with a DIRECT
/// `anilist/anime` mapping in the same response (`include=mappings`),
/// so no extra lookup is needed to play them.
///
/// Mapping rules (never fake a result): an entry is shown ONLY when
/// Kitsu maps it to a real AniList id; entries without one are
/// DROPPED and counted (see [parseSearchResults]), never shown as
/// playable. Jikan was tried first and rejected — it times out from
/// the VM (http 000 in 20 s) and rate-limits hard (3 req/s); Kitsu
/// answered in ~1 s with HTTP 200.
class KitsuSearch {
  static const String _host = 'kitsu.io';
  static const String _path = '/api/edge/anime';

  /// One Kitsu title search. Returns the mapped results, how many
  /// entries were dropped for having no AniList id, and whether the
  /// call itself failed (non-200 / timeout / bad body). Never throws.
  /// [client] is injectable for tests; when omitted a fresh client
  /// is created and closed.
  static Future<({List<Anime> results, int dropped, bool failed})> search(
    String query, {
    http.Client? client,
  }) async {
    final http.Client c = client ?? http.Client();
    try {
      final Uri uri = Uri.https(_host, _path, <String, String>{
        'filter[text]': query.trim(),
        'page[limit]': '20',
        'include': 'mappings',
      });
      final http.Response resp = await c
          .get(
            uri,
            headers: <String, String>{
              'Accept': 'application/vnd.api+json',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        return (results: <Anime>[], dropped: 0, failed: true);
      }
      final Map<String, dynamic> json =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final ({List<Anime> results, int dropped}) parsed =
          parseSearchResults(json);
      return (results: parsed.results, dropped: parsed.dropped, failed: false);
    } catch (_) {
      return (results: <Anime>[], dropped: 0, failed: true);
    } finally {
      if (client == null) c.close();
    }
  }

  /// Pure mapper: a Kitsu search response → playable results +
  /// dropped count. A response with no `data` list parses to empty
  /// (never throws) — a wrong-shaped payload is an empty result,
  /// not a crash.
  static ({List<Anime> results, int dropped}) parseSearchResults(
    Map<String, dynamic> json,
  ) {
    final List<dynamic> data =
        json['data'] is List ? json['data'] as List<dynamic> : <dynamic>[];
    // `included` carries the mappings: id -> {externalSite: externalId}.
    final Map<String, Map<String, String>> mappings =
        <String, Map<String, String>>{};
    final List<dynamic> included = json['included'] is List
        ? json['included'] as List<dynamic>
        : <dynamic>[];
    for (final dynamic m in included) {
      if (m is! Map<String, dynamic> || m['type'] != 'mappings') continue;
      final Map<String, dynamic>? attrs =
          m['attributes'] as Map<String, dynamic>?;
      final String? site = attrs?['externalSite'] as String?;
      final Object? extId = attrs?['externalId'];
      final String? id = m['id'] as String?;
      if (site == null || extId == null || id == null) continue;
      mappings
          .putIfAbsent(id, () => <String, String>{})[site] = extId.toString();
    }
    final List<Anime> results = <Anime>[];
    int dropped = 0;
    for (final dynamic e in data) {
      if (e is! Map<String, dynamic>) {
        dropped++;
        continue;
      }
      final Map<String, String> entryMappings = <String, String>{};
      final Map<String, dynamic>? rels =
          e['relationships'] as Map<String, dynamic>?;
      final List<dynamic> relData =
          (rels?['mappings'] as Map<String, dynamic>?)?['data']
                  as List<dynamic>? ??
              <dynamic>[];
      for (final dynamic r in relData) {
        if (r is! Map<String, dynamic>) continue;
        final Map<String, String>? mm = mappings[r['id'] as String?];
        if (mm != null) entryMappings.addAll(mm);
      }
      final Anime? anime = animeFromKitsu(e, entryMappings);
      if (anime == null) {
        dropped++;
        continue;
      }
      results.add(anime);
    }
    return (results: results, dropped: dropped);
  }

  /// One Kitsu entry → [Anime]. Null when it has no AniList id (not
  /// playable — the resolvers play by AniList id) or no usable title.
  /// Pure — unit-tested. Mirrors [AniListService.animeFromMedia]:
  /// same `anilist-<id>` key, same 0–5 rating scale (Kitsu's
  /// `averageRating` is 0–100, sent as a STRING, e.g. "69.23"),
  /// same purple gradient, movies forced to 1 episode.
  static Anime? animeFromKitsu(
    Map<String, dynamic> entry,
    Map<String, String> mappings,
  ) {
    final int? anilistId = int.tryParse(mappings['anilist/anime'] ?? '');
    if (anilistId == null) return null;
    final Map<String, dynamic> attrs =
        entry['attributes'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final String title = _kitsuTitle(attrs);
    if (title.isEmpty) return null;
    final Map<String, dynamic>? poster =
        attrs['posterImage'] as Map<String, dynamic>?;
    final String? posterUrl = poster?['large'] as String? ??
        poster?['medium'] as String? ??
        poster?['original'] as String?;
    // Kitsu sends averageRating as a string ("69.23"), not a number.
    final Object? avgRaw = attrs['averageRating'];
    final double? avg = avgRaw is num
        ? avgRaw.toDouble()
        : (avgRaw is String ? double.tryParse(avgRaw) : null);
    final String startDate = attrs['startDate'] as String? ?? '';
    final int year = startDate.length >= 4
        ? int.tryParse(startDate.substring(0, 4)) ?? 0
        : 0;
    final String showType =
        (attrs['showType'] as String? ?? '').toLowerCase();
    int episodes = (attrs['episodeCount'] as num?)?.toInt() ?? 0;
    if (showType == 'movie' && episodes <= 0) episodes = 1;
    return Anime(
      id: 'anilist-$anilistId',
      anilistId: anilistId,
      malId: int.tryParse(mappings['myanimelist/anime'] ?? ''),
      title: title,
      rating: avg != null ? avg / 20.0 : 0,
      year: year,
      episodeCount: episodes,
      genres: const <String>[],
      synopsis: (attrs['synopsis'] as String? ?? '').trim(),
      posterUrl: posterUrl,
      gradient: const <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    );
  }

  static String _kitsuTitle(Map<String, dynamic> attrs) {
    final String canonical =
        (attrs['canonicalTitle'] as String? ?? '').trim();
    if (canonical.isNotEmpty) return canonical;
    final Map<String, dynamic>? titles =
        attrs['titles'] as Map<String, dynamic>?;
    for (final String key in <String>['en', 'en_jp', 'en_us', 'ja_jp']) {
      final String t = (titles?[key] as String? ?? '').trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }
}
