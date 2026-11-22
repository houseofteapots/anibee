import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'miruro_resolver.dart';

/// TorBox + Real-Debrid — real API clients (M2).
///
/// Flow per episode: Nyaa RSS (public, no key) finds the torrent for
/// "`<title> <episode>`" -> the debrid service resolves a direct,
/// playable link:
/// - TorBox: checkcached (hash) -> if cached, requestdl; else
///   createtorrent + poll mylist until downloaded, then requestdl.
/// - Real-Debrid: addMagnet -> selectFiles (all, REQUIRED) -> poll
///   info until downloaded -> unrestrict/link.
/// Keys come only from the user's Settings entry — never hardcoded.
class DebridService {
  DebridService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String torboxApiBase = 'https://api.torbox.app/v1/api';
  static const String realDebridApiBase =
      'https://api.real-debrid.com/rest/1.0';
  static const String _ua = 'AniBee/0.2.1';

  // ------------------------------------------------------------ verify

  /// TorBox GET /user/me. Returns the account name on success.
  Future<String?> verifyTorbox(String apiKey) async {
    try {
      final http.Response resp = await _client
          .get(
            Uri.parse('$torboxApiBase/user/me'),
            headers: _bearer(apiKey),
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;
      final Map<String, dynamic> json =
          jsonDecode(resp.body) as Map<String, dynamic>;
      if (json['success'] != true) return null;
      final Map<String, dynamic>? data =
          json['data'] as Map<String, dynamic>?;
      return data?['username'] as String? ??
          data?['email'] as String? ??
          'TorBox';
    } catch (_) {
      return null;
    }
  }

  /// Real-Debrid GET /user. Returns the account name on success.
  Future<String?> verifyRealDebrid(String token) async {
    try {
      final http.Response resp = await _client
          .get(
            Uri.parse('$realDebridApiBase/user'),
            headers: _bearer(token),
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;
      final Map<String, dynamic> json =
          jsonDecode(resp.body) as Map<String, dynamic>;
      return json['username'] as String? ?? 'Real-Debrid';
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _bearer(String key) => <String, String>{
    'Authorization': 'Bearer $key',
    'User-Agent': _ua,
    'Accept': 'application/json',
  };

  // ------------------------------------------------------- Nyaa RSS

  /// Search Nyaa (anime subcategory, most-seeded first) for an episode
  /// torrent. Returns candidates sorted by seeders desc.
  Future<List<NyaaTorrent>> searchNyaa(String title, int episode) async {
    final String q = Uri.encodeComponent('$title $episode');
    final Uri uri = Uri.parse(
      'https://nyaa.si/?page=rss&q=$q&c=1_2&s=seeders&o=desc',
    );
    try {
      final http.Response resp = await _client
          .get(uri, headers: <String, String>{'User-Agent': _ua})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return <NyaaTorrent>[];
      return parseNyaaRss(resp.body);
    } catch (_) {
      return <NyaaTorrent>[];
    }
  }

  /// Parse a Nyaa RSS feed into torrents. Pure — unit-tested.
  static List<NyaaTorrent> parseNyaaRss(String xml) {
    final List<NyaaTorrent> out = <NyaaTorrent>[];
    final RegExp itemRe = RegExp(
      r'<item>(.*?)</item>',
      dotAll: true,
    );
    for (final RegExpMatch item in itemRe.allMatches(xml)) {
      final String body = item.group(1)!;
      final String? title = _tag(body, 'title');
      final String? hash = _tag(body, 'nyaa:infoHash');
      final int seeders =
          int.tryParse(_tag(body, 'nyaa:seeders') ?? '') ?? 0;
      if (title == null || hash == null || hash.isEmpty) continue;
      out.add(
        NyaaTorrent(
          title: _unescape(title),
          infoHash: hash.toLowerCase(),
          seeders: seeders,
          magnet:
              'magnet:?xt=urn:btih:$hash&dn=${Uri.encodeComponent(title)}',
        ),
      );
    }
    out.sort((a, b) => b.seeders.compareTo(a.seeders));
    return out;
  }

  static String? _tag(String xml, String name) {
    final RegExpMatch? m = RegExp(
      '<$name>(.*?)</$name>',
      dotAll: true,
    ).firstMatch(xml);
    if (m == null) return null;
    // Strip CDATA wrappers (replaceAll does NOT substitute $1 — the
    // group reference is literal there, so use replaceAllMapped).
    return m.group(1)!.replaceAllMapped(
      RegExp(r'<!\[CDATA\[(.*?)\]\]>'),
      (Match c) => c.group(1) ?? '',
    );
  }

  static String _unescape(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .trim();
  }

  // ---------------------------------------------------- resolve episode

  /// Resolve a playable direct link for an episode via the configured
  /// debrid service. [service] is 'torbox' or 'realdebrid'.
  /// [onProgress] reports human status for the resolving dialog.
  /// Returns null when nothing could be resolved (caller shows the
  /// error state). [isCancelled] lets the UI abort a long poll.
  Future<ResolvedStream?> resolveEpisode({
    required String service,
    required String apiKey,
    required String title,
    required int episode,
    void Function(String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;
    onProgress?.call('Searching torrents…');
    final List<NyaaTorrent> candidates = await searchNyaa(title, episode);
    if (candidates.isEmpty) return null;
    for (final NyaaTorrent torrent in candidates.take(3)) {
      if (cancelled()) return null;
      try {
        final ResolvedStream? stream = service == 'torbox'
            ? await _resolveTorbox(
                apiKey,
                torrent,
                onProgress: onProgress,
                isCancelled: isCancelled,
              )
            : await _resolveRealDebrid(
                apiKey,
                torrent,
                onProgress: onProgress,
                isCancelled: isCancelled,
              );
        if (stream != null) return stream;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<ResolvedStream?> _resolveTorbox(
    String apiKey,
    NyaaTorrent torrent, {
    void Function(String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    // 1. Cached? (fast path — cached torrents finish in seconds.)
    onProgress?.call('Checking TorBox cache…');
    final bool cached = await _torboxIsCached(apiKey, torrent.infoHash);
    // 2. Add the magnet either way; cached ones complete almost instantly.
    onProgress?.call(cached ? 'Cached — adding to TorBox…' : 'Adding to TorBox…');
    final int? torrentId = await _torboxCreate(apiKey, torrent.magnet);
    if (torrentId == null) return null;
    final int? fileId = await _torboxPollDownloaded(
      apiKey,
      torrentId,
      maxSeconds: cached ? 60 : 300,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (fileId == null) return null;
    // 3. Direct link (valid ~3h).
    onProgress?.call('Getting play link…');
    final String? url = await _torboxRequestDl(apiKey, torrentId, fileId);
    if (url == null) return null;
    return ResolvedStream(
      url: url,
      label: 'TorBox ${torrent.title}',
      source: 'TorBox',
      headers: <String, String>{'User-Agent': _ua},
    );
  }

  /// TorBox checkcached with format=list returns a list of cached
  /// entries (empty = not cached). The entries carry file names/sizes
  /// only — torrent/file ids come from mylist after adding.
  Future<bool> _torboxIsCached(String apiKey, String hash) async {
    try {
      final http.Response resp = await _client
          .get(
            Uri.parse(
              '$torboxApiBase/torrents/checkcached?hash=$hash&format=list&list_files=true',
            ),
            headers: _bearer(apiKey),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return false;
      final Map<String, dynamic> json =
          jsonDecode(resp.body) as Map<String, dynamic>;
      if (json['success'] != true) return false;
      final List<dynamic> data = json['data'] as List<dynamic>? ?? <dynamic>[];
      return data.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<int?> _torboxCreate(String apiKey, String magnet) async {
    final http.Response resp = await _client
        .post(
          Uri.parse('$torboxApiBase/torrents/createtorrent'),
          headers: <String, String>{
            ..._bearer(apiKey),
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: <String, String>{'magnet': magnet},
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200 && resp.statusCode != 201) return null;
    final Map<String, dynamic> json =
        jsonDecode(resp.body) as Map<String, dynamic>;
    if (json['success'] != true) return null;
    final Map<String, dynamic>? data = json['data'] as Map<String, dynamic>?;
    return (data?['torrent_id'] as num?)?.toInt();
  }

  Future<int?> _torboxPollDownloaded(
    String apiKey,
    int torrentId, {
    int maxSeconds = 300,
    void Function(String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    // Poll mylist every 5s; most anime episodes are cached.
    final int ticks = (maxSeconds / 5).round();
    for (int i = 0; i < ticks; i++) {
      if (isCancelled?.call() ?? false) return null;
      try {
        final http.Response resp = await _client
            .get(
              Uri.parse('$torboxApiBase/torrents/mylist?id=$torrentId'),
              headers: _bearer(apiKey),
            )
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          final Map<String, dynamic> json =
              jsonDecode(resp.body) as Map<String, dynamic>;
          final Map<String, dynamic>? data =
              json['data'] as Map<String, dynamic>?;
          final String? status = data?['download_state'] as String?;
          final num? progress = data?['progress'] as num?;
          if (status == 'downloaded' || status == 'download_finished') {
            final List<dynamic> files =
                data?['files'] as List<dynamic>? ?? <dynamic>[];
            // Largest video file.
            Map<String, dynamic>? best;
            int bestSize = -1;
            for (final dynamic f in files) {
              final Map<String, dynamic> file = f as Map<String, dynamic>;
              final String name = file['name'] as String? ?? '';
              if (!name.endsWith('.mkv') && !name.endsWith('.mp4')) continue;
              final int size = (file['size'] as num?)?.toInt() ?? 0;
              if (size > bestSize) {
                bestSize = size;
                best = file;
              }
            }
            if (best != null) return (best['id'] as num?)?.toInt();
            if (files.isNotEmpty) {
              return ((files.first as Map<String, dynamic>)['id'] as num?)
                  ?.toInt();
            }
            return null;
          }
          if (status == 'failed' || status == 'download_failed') {
            return null;
          }
          onProgress?.call(
            'Downloading ${progress != null ? '${(progress * 100).round()}%' : '…'}',
          );
        }
      } catch (_) {
        // Retry next tick.
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    return null;
  }

  Future<String?> _torboxRequestDl(
    String apiKey,
    int torrentId,
    int fileId,
  ) async {
    final http.Request req = http.Request(
      'GET',
      Uri.parse(
        '$torboxApiBase/torrents/requestdl?token=$apiKey&torrent_id=$torrentId&file_id=$fileId&redirect=true',
      ),
    )..followRedirects = false;
    final http.StreamedResponse resp = await _client
        .send(req)
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode == 302 || resp.statusCode == 301) {
      return resp.headers['location'];
    }
    if (resp.statusCode == 200) {
      final String body = await resp.stream.bytesToString();
      try {
        final Map<String, dynamic> json =
            jsonDecode(body) as Map<String, dynamic>;
        return json['data'] as String?;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<ResolvedStream?> _resolveRealDebrid(
    String token,
    NyaaTorrent torrent, {
    void Function(String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call('Adding to Real-Debrid…');
    final String? id = await _rdAddMagnet(token, torrent.magnet);
    if (id == null) return null;
    await _rdSelectFiles(token, id);
    onProgress?.call('Waiting for download…');
    final String? link = await _rdPollDownloaded(
      token,
      id,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (link == null) return null;
    onProgress?.call('Getting play link…');
    final String? url = await _rdUnrestrict(token, link);
    if (url == null) return null;
    return ResolvedStream(
      url: url,
      label: 'Real-Debrid ${torrent.title}',
      source: 'Real-Debrid',
      headers: <String, String>{'User-Agent': _ua},
    );
  }

  Future<String?> _rdAddMagnet(String token, String magnet) async {
    final http.Response resp = await _client
        .post(
          Uri.parse('$realDebridApiBase/torrents/addMagnet'),
          headers: <String, String>{
            ..._bearer(token),
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: <String, String>{'magnet': magnet},
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 201) return null;
    final Map<String, dynamic> json =
        jsonDecode(resp.body) as Map<String, dynamic>;
    return json['id'] as String?;
  }

  Future<void> _rdSelectFiles(String token, String id) async {
    try {
      await _client
          .post(
            Uri.parse('$realDebridApiBase/torrents/selectFiles/$id'),
            headers: <String, String>{
              ..._bearer(token),
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: <String, String>{'files': 'all'},
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // selectFiles failure surfaces as a poll timeout below.
    }
  }

  Future<String?> _rdPollDownloaded(
    String token,
    String id, {
    void Function(String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    for (int i = 0; i < 60; i++) {
      if (isCancelled?.call() ?? false) return null;
      try {
        final http.Response resp = await _client
            .get(
              Uri.parse('$realDebridApiBase/torrents/info/$id'),
              headers: _bearer(token),
            )
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          final Map<String, dynamic> json =
              jsonDecode(resp.body) as Map<String, dynamic>;
          final String? status = json['status'] as String?;
          if (status == 'downloaded') {
            final List<dynamic> links =
                json['links'] as List<dynamic>? ?? <dynamic>[];
            if (links.isEmpty) return null;
            return links.first as String;
          }
          if (status == 'error' ||
              status == 'dead' ||
              status == 'magnet_error') {
            return null;
          }
          final num? progress = json['progress'] as num?;
          onProgress?.call(
            'Downloading ${progress != null ? '${progress.round()}%' : '…'}',
          );
        }
      } catch (_) {
        // Retry next tick.
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    return null;
  }

  Future<String?> _rdUnrestrict(String token, String link) async {
    final http.Response resp = await _client
        .post(
          Uri.parse('$realDebridApiBase/unrestrict/link'),
          headers: <String, String>{
            ..._bearer(token),
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: <String, String>{'link': link},
        )
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return null;
    final Map<String, dynamic> json =
        jsonDecode(resp.body) as Map<String, dynamic>;
    return json['download'] as String?;
  }
}

class NyaaTorrent {
  const NyaaTorrent({
    required this.title,
    required this.infoHash,
    required this.seeders,
    required this.magnet,
  });

  final String title;
  final String infoHash;
  final int seeders;
  final String magnet;
}
