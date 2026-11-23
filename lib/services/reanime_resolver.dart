import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'anilist_service.dart';
import 'flixcloud_decrypt.dart';
import 'miruro_resolver.dart';

/// ReAnime (reanime.to / reanime.cz) — real on-device resolver.
///
/// Chain: AniList id -> `GET /api/flix/{anilistId}/{episode}` (public
/// JSON API, HD-1/HD-2 sub/dub flixcloud embed links) -> flixcloud
/// embed page -> [decryptFlixcloudEmbed] (static WASM parse + mini
/// interpreter + PBKDF2/AES, no server) -> master.m3u8 URL.
///
/// The old `/api/watch/{slug}/{ep}` endpoint is gone (404 since the
/// .to -> .cz move); the flix endpoint is the one that matters and
/// only needs the AniList id, so no title search is needed at all.
///
/// Verified live from the VM 2026-11-23: the flix API returns real
/// embed links, and the decrypt is verified against the JS reference
/// on a real embed (see test/flixcloud_decrypt_test.dart).
///
/// Token API 410 — investigated live 2026-11-23 (0.2.12): the Dart
/// port derives the IDENTICAL token to the Anivexa JS reference on
/// the same saved embed HTML, with identical headers, yet the token
/// call 410s from Dart's http.Client (and curl) while the JS
/// reference (node fetch) succeeds 3/3 from the same VM IP. Adding
/// the browser fetch headers (Sec-Fetch-Mode, Accept-Language,
/// Accept-Encoding) does NOT fix it, and HTTP/2 does not either
/// (curl --http2 still 410s). No session cookie is involved (the
/// embed sets none). The gate is transport-level — a browser-like
/// TLS fingerprint — not a code bug, not the IP alone, and not
/// token expiry (an immediate Dart call on a fresh embed 410s).
/// The user's phone failure so far was the AniList dialog (item 4),
/// never the token step, so ReAnime stays selectable: the phone
/// (residential IP, real iOS) is the verdict. If it 410s on the
/// phone too, hide ReAnime from the picker until the flow can be
/// fixed (e.g. a platform HTTP stack) — never fake it.
class ReAnimeResolver {
  ReAnimeResolver({http.Client? client, AniListService? anilist})
    : _client = client ?? http.Client(),
      _anilist = anilist ?? AniListService();

  final http.Client _client;
  final AniListService _anilist;

  static const String _flixApi = 'https://reanime.to';
  static const String _flixcloud = 'https://flixcloud.cc';
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  String? lastError;

  /// Resolve a playable stream for [anime] episode [episodeNumber].
  /// [subDub] is 'Sub' or 'Dub'. Returns null when nothing resolved.
  Future<ResolvedStream?> resolve({
    required Anime anime,
    required int episodeNumber,
    required String subDub,
  }) async {
    lastError = null;
    final int? anilistId;
    if (anime.anilistId != null) {
      anilistId = anime.anilistId;
    } else {
      // 0.2.12: honest failure — a dead AniList lookup (network /
      // rate limit) must not be reported as "title not on AniList".
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
    final String? embedUrl = await _pickEmbed(
      anilistId,
      episodeNumber,
      subDub,
    );
    if (embedUrl == null) return null;
    try {
      final http.Response embedResp = await _client
          .get(
            Uri.parse(embedUrl),
            headers: <String, String>{
              'User-Agent': _ua,
              'Referer': '$_flixApi/',
              'Accept': 'text/html,application/xhtml+xml',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (embedResp.statusCode != 200) {
        lastError = 'ReAnime embed failed (${embedResp.statusCode}).';
        return null;
      }
      final FlixcloudStream stream = await decryptFlixcloudEmbed(
        embedHtml: embedResp.body,
        fetchTokenJson: (String token) async {
          final http.Response resp = await _client
              .get(
                Uri.parse('$_flixcloud/api/m3u8/$token'),
                headers: <String, String>{
                  'User-Agent': _ua,
                  'Referer': '$_flixApi/',
                  'Accept': 'application/json',
                },
              )
              .timeout(const Duration(seconds: 12));
          if (resp.statusCode != 200) {
            throw FlixcloudException(
              'Token API ${resp.statusCode}: ${resp.body.length > 120 ? resp.body.substring(0, 120) : resp.body}',
            );
          }
          return jsonDecode(resp.body) as Map<String, dynamic>;
        },
      );
      final String serverName =
          embedUrl.contains('v=1') ? 'HD-1' : 'HD-2';
      return ResolvedStream(
        url: stream.url,
        label: 'ReAnime $serverName $subDub',
        source: 'ReAnime',
        headers: <String, String>{
          'User-Agent': _ua,
          'Referer': '$_flixcloud/',
        },
        subtitles: stream.subtitles,
      );
    } on FlixcloudException catch (e) {
      lastError = 'ReAnime decrypt failed: ${e.message}';
      return null;
    } catch (_) {
      lastError ??= 'ReAnime resolve failed for episode $episodeNumber.';
      return null;
    }
  }

  /// Fetch the flix server list and pick the best embed URL for
  /// [subDub]. Null when the API fails or has no matching server.
  Future<String?> _pickEmbed(
    int anilistId,
    int episode,
    String subDub,
  ) async {
    List<dynamic> servers;
    try {
      final http.Response resp = await _client
          .get(
            Uri.parse('$_flixApi/api/flix/$anilistId/$episode'),
            headers: <String, String>{
              'User-Agent': _ua,
              'Accept': 'application/json, */*',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) {
        lastError = 'ReAnime flix API failed (${resp.statusCode}).';
        return null;
      }
      final Map<String, dynamic> data =
          jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] != true) {
        lastError = 'ReAnime has no servers for episode $episode.';
        return null;
      }
      servers = data['servers'] as List<dynamic>? ?? <dynamic>[];
    } catch (_) {
      lastError = 'ReAnime is unreachable right now.';
      return null;
    }
    final String? link = pickServerLink(servers, subDub);
    if (link == null) {
      lastError = 'ReAnime has no $subDub server for episode $episode.';
    }
    return link;
  }

  /// Best embed link for [subDub] out of a flix `/api/flix` server
  /// list: HD-2 first, then HD-1. Pure — unit-tested.
  static String? pickServerLink(List<dynamic> servers, String subDub) {
    final List<String> wantedTypes = subDub == 'Dub'
        ? <String>['dub', 's-dub']
        : <String>['sub', 's-sub'];
    const Map<String, int> order = <String, int>{'HD-2': 0, 'HD-1': 1};
    final List<Map<String, dynamic>> matching = <Map<String, dynamic>>[];
    for (final dynamic s in servers) {
      final Map<String, dynamic> server = s as Map<String, dynamic>;
      if (!wantedTypes.contains(server['dataType'])) continue;
      final String? link = server['dataLink'] as String?;
      if (link == null || link.isEmpty) continue;
      matching.add(server);
    }
    if (matching.isEmpty) return null;
    matching.sort(
      (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (order[a['serverName']] ?? 9) -
          (order[b['serverName']] ?? 9),
    );
    return matching.first['dataLink'] as String?;
  }
}
