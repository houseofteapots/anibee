import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../settings_store.dart';
import 'miruro_resolver.dart';

/// One HLS media-playlist segment: its URI (as written in the
/// playlist) + duration seconds.
class HlsSegment {
  const HlsSegment({required this.uri, required this.duration});

  final String uri;
  final double duration;
}

/// One parsed HLS media playlist: segments in order, plus the
/// encryption-key and init-map URIs it references (null when absent).
class HlsMediaPlaylist {
  const HlsMediaPlaylist({
    required this.segments,
    required this.keyUris,
    required this.mapUris,
  });

  final List<HlsSegment> segments;

  /// Distinct EXT-X-KEY URIs in first-seen order (AES-128 keys).
  final List<String> keyUris;

  /// Distinct EXT-X-MAP URIs in first-seen order (fMP4 init segments).
  final List<String> mapUris;
}

/// One parsed HLS master-playlist variant.
class HlsVariant {
  const HlsVariant({
    required this.uri,
    required this.bandwidth,
    required this.height,
  });

  final String uri;
  final int bandwidth;

  /// Vertical resolution (0 when the playlist gives no RESOLUTION).
  final int height;
}

/// Real offline downloads (0.2.5) — replaces the M1 simulation that
/// only animated a timer and saved NO file (tapping a "downloaded"
/// episode did nothing, and leaving the detail screen cancelled the
/// timer, freezing progress at ~50-70% — exactly what the user
/// reported on the phone).
///
/// How it works:
/// - HLS streams (.m3u8, Miruro/Anikoto): fetch the master playlist,
///   pick the variant matching Settings → Download quality, fetch the
///   media playlist, download every segment to the app documents
///   dir, download any AES-128 keys / init maps alongside, and write
///   a LOCAL playlist.m3u8 with relative URIs. mpv opens the local
///   playlist offline. Subtitles are downloaded too.
/// - Direct files (TorBox / Real-Debrid links): single-file download
///   with HTTP Range resume.
/// - Resume: progress is persisted per segment (index + durations)
///   in the store's download record. An interrupted download — app
///   killed, backgrounded, network hiccup — resumes by skipping the
///   segments already on disk; a fresh resolve that returns the same
///   segment list reuses them by index. Nothing here is tied to any
///   screen's lifetime: the service lives in AppServices, so leaving
///   the detail screen can no longer stall a download.
/// - Each segment is retried (3 attempts) before the download is
///   marked 'failed'; the record is kept so the user can retry.
class DownloadService {
  // ignore: prefer_initializing_formals — the parameter name
  // (baseDirOverride) is public for tests; the field is private.
  DownloadService({http.Client? client, Directory? baseDirOverride})
    : _client = client ?? http.Client(),
      _baseDirOverride = baseDirOverride;

  final http.Client _client;
  final Directory? _baseDirOverride;

  static const int _maxSegmentAttempts = 3;
  static const Duration _retryDelay = Duration(seconds: 1);

  final Set<String> _active = <String>{};
  final Set<String> _cancelled = <String>{};

  bool get isBusy => _active.isNotEmpty;

  /// True while this episode's download is running.
  bool isActive(String key) => _active.contains(key);

  Future<Directory> _downloadsDir() async {
    if (_baseDirOverride != null) {
      final Directory dir = Directory('${_baseDirOverride.path}/downloads');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${docs.path}/downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _sanitizeKey(String key) {
    return key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  Future<Directory> _dirFor(String key) async {
    final Directory base = await _downloadsDir();
    final Directory dir = Directory('${base.path}/${_sanitizeKey(key)}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ---------------------------------------------------------- pure helpers

  /// Resolve a playlist-relative URI against its playlist URL.
  static String resolveUrl(String baseUrl, String ref) {
    if (ref.startsWith('http://') || ref.startsWith('https://')) return ref;
    return Uri.parse(baseUrl).resolve(ref).toString();
  }

  static bool isPlaylistBody(String body) =>
      body.trimLeft().startsWith('#EXTM3U');

  static bool isMasterPlaylist(String body) =>
      body.contains('#EXT-X-STREAM-INF');

  /// Parse master-playlist variants (URI = the line after each
  /// #EXT-X-STREAM-INF). Pure — unit-tested.
  static List<HlsVariant> parseMasterPlaylist(String body) {
    final List<HlsVariant> variants = <HlsVariant>[];
    final List<String> lines = body.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;
      int bandwidth = 0;
      int height = 0;
      final RegExpMatch? bw = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      if (bw != null) bandwidth = int.tryParse(bw.group(1)!) ?? 0;
      final RegExpMatch? res = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line);
      if (res != null) height = int.tryParse(res.group(1)!) ?? 0;
      String? uri;
      for (int j = i + 1; j < lines.length; j++) {
        final String next = lines[j].trim();
        if (next.isEmpty) continue;
        if (!next.startsWith('#')) uri = next;
        break;
      }
      if (uri != null) {
        variants.add(
          HlsVariant(uri: uri, bandwidth: bandwidth, height: height),
        );
      }
    }
    return variants;
  }

  /// Pick the variant for a quality setting ('1080p' / '720p' /
  /// '480p'): the highest variant whose height fits the cap; when
  /// no variant reports a resolution, the highest-bandwidth one.
  static HlsVariant? pickVariant(List<HlsVariant> variants, String quality) {
    if (variants.isEmpty) return null;
    final int cap =
        int.tryParse(quality.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1080;
    final List<HlsVariant> withRes = variants
        .where((HlsVariant v) => v.height > 0)
        .toList();
    if (withRes.isNotEmpty) {
      withRes.sort(
        (HlsVariant a, HlsVariant b) => a.height.compareTo(b.height),
      );
      HlsVariant chosen = withRes.first;
      for (final HlsVariant v in withRes) {
        if (v.height <= cap) chosen = v;
      }
      return chosen;
    }
    final List<HlsVariant> sorted = List<HlsVariant>.of(
      variants,
    )..sort((HlsVariant a, HlsVariant b) => a.bandwidth.compareTo(b.bandwidth));
    return sorted.last;
  }

  /// Parse an HLS media playlist: segments (URI + #EXTINF duration)
  /// plus distinct key / init-map URIs. Pure — unit-tested.
  static HlsMediaPlaylist parseMediaPlaylist(String body) {
    final List<HlsSegment> segments = <HlsSegment>[];
    final List<String> keyUris = <String>[];
    final List<String> mapUris = <String>[];
    double pendingDuration = 0;
    for (final String raw in body.split('\n')) {
      final String line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-KEY')) {
        final RegExpMatch? m = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (m != null && !keyUris.contains(m.group(1)!)) {
          keyUris.add(m.group(1)!);
        }
        continue;
      }
      if (line.startsWith('#EXT-X-MAP')) {
        final RegExpMatch? m = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (m != null && !mapUris.contains(m.group(1)!)) {
          mapUris.add(m.group(1)!);
        }
        continue;
      }
      if (line.startsWith('#EXTINF:')) {
        final String num = line
            .substring('#EXTINF:'.length)
            .split(',')
            .first
            .trim();
        pendingDuration = double.tryParse(num) ?? 0;
        continue;
      }
      if (line.startsWith('#')) continue;
      segments.add(HlsSegment(uri: line, duration: pendingDuration));
      pendingDuration = 0;
    }
    return HlsMediaPlaylist(
      segments: segments,
      keyUris: keyUris,
      mapUris: mapUris,
    );
  }

  /// Rewrite a media playlist so every remote URI points at a local
  /// file in the same dir: segments -> [segmentFile] (by index),
  /// EXT-X-KEY URIs -> [keyFile] (by key URI), EXT-X-MAP URIs ->
  /// [mapFile] (by map URI). All other lines pass through verbatim.
  /// Pure — unit-tested.
  static String buildLocalPlaylist(
    String body, {
    required String Function(int index, String uri) segmentFile,
    required String Function(String uri) keyFile,
    required String Function(String uri) mapFile,
  }) {
    final StringBuffer out = StringBuffer();
    int segmentIndex = -1;
    for (final String raw in body.split('\n')) {
      final String line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-KEY')) {
        final RegExpMatch? m = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (m != null) {
          out.writeln(
            line.replaceAll('"${m.group(1)!}"', '"${keyFile(m.group(1)!)}"'),
          );
        } else {
          out.writeln(line);
        }
        continue;
      }
      if (line.startsWith('#EXT-X-MAP')) {
        final RegExpMatch? m = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (m != null) {
          out.writeln(
            line.replaceAll('"${m.group(1)!}"', '"${mapFile(m.group(1)!)}"'),
          );
        } else {
          out.writeln(line);
        }
        continue;
      }
      if (line.startsWith('#')) {
        out.writeln(line);
        continue;
      }
      segmentIndex++;
      out.writeln(segmentFile(segmentIndex, line));
    }
    return out.toString();
  }

  // ------------------------------------------------------------- downloads

  /// Start (or resume) downloading an episode's resolved stream.
  /// No-op when this episode is already downloading. Throws nothing:
  /// failures mark the download 'failed' (record kept for retry).
  Future<void> startDownload({
    required Anime anime,
    required Episode episode,
    required ResolvedStream stream,
    required SettingsStore store,
  }) async {
    final String key = '${anime.id}:${episode.number}';
    if (_active.contains(key)) return;
    _active.add(key);
    _cancelled.remove(key);
    try {
      await store.setDownloadStatus(key, 'downloading');
      final Map<String, dynamic>? existing = store.downloadRecordFor(key);
      final bool isHls =
          stream.url.toLowerCase().contains('.m3u8') ||
          stream.url.toLowerCase().contains('m3u8');
      if (isHls) {
        await _downloadHls(
          key: key,
          anime: anime,
          episode: episode,
          stream: stream,
          store: store,
          existing: existing,
        );
      } else {
        await _downloadFile(
          key: key,
          anime: anime,
          episode: episode,
          stream: stream,
          store: store,
          existing: existing,
        );
      }
    } catch (_) {
      // A failed download keeps its record (partial segments stay on
      // disk) so the next tap resumes instead of starting over.
      await store.setDownloadStatus(key, 'failed');
    } finally {
      _active.remove(key);
    }
  }

  /// Cancel an in-progress download. The partial files stay on disk
  /// (resume on the next tap); the caller removes the record when
  /// the user explicitly deletes the download.
  void cancelDownload(String key) {
    _cancelled.add(key);
  }

  /// Delete a download entirely: files + record + status/progress.
  Future<void> removeDownload(String key, SettingsStore store) async {
    cancelDownload(key);
    // Give a running loop a moment to notice the cancel flag before
    // the dir is deleted under it.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final Directory dir = await _dirFor(key);
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
    await store.removeDownloadRecord(key);
    await store.removeDownload(key);
  }

  /// True when this episode has a complete local file.
  bool isDownloaded(String key, SettingsStore store) {
    if (store.downloadStatus[key] != 'downloaded') return false;
    final Map<String, dynamic>? record = store.downloadRecordFor(key);
    final String? path = record?['localPath'] as String?;
    if (path == null || path.isEmpty) return false;
    return File(path).existsSync();
  }

  /// A local playable stream for a downloaded episode (offline):
  /// file:// playlist (HLS) or file (direct), local subtitles.
  /// Null when the episode isn't fully downloaded.
  ResolvedStream? localStreamFor(String key, SettingsStore store) {
    if (!isDownloaded(key, store)) return null;
    final Map<String, dynamic>? record = store.downloadRecordFor(key);
    final String? path = record?['localPath'] as String?;
    if (path == null) return null;
    final List<SubtitleInfo> subs = <SubtitleInfo>[];
    final List<dynamic>? savedSubs = record?['subtitles'] as List<dynamic>?;
    if (savedSubs != null) {
      for (final dynamic s in savedSubs) {
        final Map<String, dynamic> m = s as Map<String, dynamic>;
        final String? subPath = m['path'] as String?;
        final String label = m['label'] as String? ?? 'Subtitle';
        if (subPath != null && File(subPath).existsSync()) {
          subs.add(SubtitleInfo(label: label, url: 'file://$subPath'));
        }
      }
    }
    return ResolvedStream(
      url: 'file://$path',
      label: 'Offline',
      source: 'Offline',
      subtitles: subs,
    );
  }

  /// Prune stale download state left by the M1 simulation (rows that
  /// claim 'downloaded'/'downloading' but have no record and no file
  /// on disk). Runs once at app start — those rows could never play.
  Future<void> pruneStale(SettingsStore store) async {
    for (final String key in store.downloadStatus.keys.toList()) {
      final String? status = store.downloadStatus[key];
      final Map<String, dynamic>? record = store.downloadRecordFor(key);
      final String? path = record?['localPath'] as String?;
      final bool hasFile =
          path != null && path.isNotEmpty && File(path).existsSync();
      if (status == 'downloaded' && !hasFile) {
        await store.removeDownloadRecord(key);
        await store.removeDownload(key);
      } else if (status == 'downloading' && record == null) {
        // Simulated in-progress download (timer-based, no file):
        // drop it so the button offers a real download again.
        await store.removeDownload(key);
      }
    }
  }

  Future<http.Response> _getWithRetry(
    String url,
    Map<String, String> headers,
  ) async {
    Object? lastError;
    for (int attempt = 0; attempt < _maxSegmentAttempts; attempt++) {
      try {
        final http.Response res = await _client.get(
          Uri.parse(url),
          headers: headers,
        );
        if (res.statusCode >= 200 && res.statusCode < 300) return res;
        lastError = 'HTTP ${res.statusCode}';
      } catch (e) {
        lastError = e;
      }
      if (attempt + 1 < _maxSegmentAttempts) {
        await Future<void>.delayed(_retryDelay);
      }
    }
    throw Exception('GET $url failed: $lastError');
  }

  Future<void> _downloadHls({
    required String key,
    required Anime anime,
    required Episode episode,
    required ResolvedStream stream,
    required SettingsStore store,
    required Map<String, dynamic>? existing,
  }) async {
    final Directory dir = await _dirFor(key);
    // 1. Master (or media) playlist.
    final http.Response masterRes = await _getWithRetry(
      stream.url,
      stream.headers,
    );
    final String masterBody = utf8.decode(masterRes.bodyBytes);
    String mediaUrl = stream.url;
    String mediaBody = masterBody;
    if (isMasterPlaylist(masterBody)) {
      final List<HlsVariant> variants = parseMasterPlaylist(masterBody);
      final HlsVariant? chosen = pickVariant(variants, store.downloadQuality);
      if (chosen == null) throw Exception('No stream variants found');
      mediaUrl = resolveUrl(stream.url, chosen.uri);
      final http.Response mediaRes = await _getWithRetry(
        mediaUrl,
        stream.headers,
      );
      mediaBody = utf8.decode(mediaRes.bodyBytes);
    }
    if (!isPlaylistBody(mediaBody)) {
      throw Exception('Stream is not an HLS playlist');
    }
    final HlsMediaPlaylist playlist = parseMediaPlaylist(mediaBody);
    if (playlist.segments.isEmpty) throw Exception('Playlist has no segments');

    // 2. Resume check: same segment list (count + durations) as the
    //    persisted record -> reuse on-disk segments by index. A
    //    different list (new encode / quality change) -> start fresh.
    final List<double> durations = playlist.segments
        .map((HlsSegment s) => s.duration)
        .toList();
    final List<dynamic>? oldDurations =
        existing?['segmentDurations'] as List<dynamic>?;
    final List<int> done = <int>[];
    final bool resumable =
        existing != null &&
        existing['kind'] == 'hls' &&
        oldDurations != null &&
        oldDurations.length == durations.length &&
        _durationsMatch(
          oldDurations.map((dynamic d) => (d as num).toDouble()).toList(),
          durations,
        );
    if (!resumable) {
      // Fresh download: clear any partial files from another encode.
      for (final FileSystemEntity e in dir.listSync()) {
        if (e is File &&
            (e.path.endsWith('.ts') ||
                e.path.endsWith('.m4s') ||
                e.path.endsWith('.key') ||
                e.path.endsWith('.mp4'))) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } else {
      final List<dynamic>? oldDone = existing['doneSegments'] as List<dynamic>?;
      if (oldDone != null) {
        for (final dynamic i in oldDone) {
          final int idx = (i as num).toInt();
          if (idx < 0 || idx >= playlist.segments.length) continue;
          final File f = File(
            '${dir.path}/${_segmentFile(idx, playlist.segments[idx].uri)}',
          );
          if (await f.exists() && await f.length() > 0) {
            done.add(idx);
          }
        }
      }
    }

    final Map<String, dynamic> record = <String, dynamic>{
      'animeId': anime.id,
      'anilistId': anime.anilistId,
      'title': anime.title,
      'posterUrl': anime.posterUrl,
      'episodeCount': anime.episodeCount,
      'episode': episode.number,
      'episodeTitle': episode.title,
      'kind': 'hls',
      'streamUrl': stream.url,
      'headers': stream.headers,
      'quality': store.downloadQuality,
      'localPath': '${dir.path}/playlist.m3u8',
      'totalSegments': playlist.segments.length,
      'doneSegments': done,
      'segmentDurations': durations,
    };
    await store.setDownloadRecord(key, record);
    await store.setDownloadProgress(
      key,
      playlist.segments.isEmpty ? 0 : done.length / playlist.segments.length,
    );

    // 3. Keys + init maps (once each, up front).
    final Map<String, String> keyFiles = <String, String>{};
    for (int i = 0; i < playlist.keyUris.length; i++) {
      final String uri = playlist.keyUris[i];
      final String name = 'key$i.key';
      final File f = File('${dir.path}/$name');
      if (!await f.exists() || await f.length() == 0) {
        final http.Response res = await _getWithRetry(
          resolveUrl(mediaUrl, uri),
          stream.headers,
        );
        await f.writeAsBytes(res.bodyBytes);
      }
      keyFiles[uri] = name;
    }
    final Map<String, String> mapFiles = <String, String>{};
    for (int i = 0; i < playlist.mapUris.length; i++) {
      final String uri = playlist.mapUris[i];
      final String name = 'init$i.mp4';
      final File f = File('${dir.path}/$name');
      if (!await f.exists() || await f.length() == 0) {
        final http.Response res = await _getWithRetry(
          resolveUrl(mediaUrl, uri),
          stream.headers,
        );
        await f.writeAsBytes(res.bodyBytes);
      }
      mapFiles[uri] = name;
    }

    // 4. Segments, one at a time (sequential = resumable + gentle on
    //    the CDN). Cancel / failure stops the loop; the record keeps
    //    what's done so the next tap resumes.
    for (int i = 0; i < playlist.segments.length; i++) {
      if (_cancelled.contains(key)) return;
      if (done.contains(i)) continue;
      final HlsSegment seg = playlist.segments[i];
      final String name = _segmentFile(i, seg.uri);
      final File f = File('${dir.path}/$name');
      final http.Response res = await _getWithRetry(
        resolveUrl(mediaUrl, seg.uri),
        stream.headers,
      );
      await f.writeAsBytes(res.bodyBytes);
      done.add(i);
      record['doneSegments'] = done;
      await store.setDownloadRecord(key, record);
      await store.setDownloadProgress(
        key,
        done.length / playlist.segments.length,
      );
    }
    if (_cancelled.contains(key)) return;

    // 5. Local playlist + subtitles, then mark complete.
    final String localPlaylist = buildLocalPlaylist(
      mediaBody,
      segmentFile: (int index, String uri) => _segmentFile(index, uri),
      keyFile: (String uri) => keyFiles[uri] ?? uri,
      mapFile: (String uri) => mapFiles[uri] ?? uri,
    );
    await File('${dir.path}/playlist.m3u8').writeAsString(localPlaylist);
    record['subtitles'] = await _downloadSubtitles(dir: dir, stream: stream);
    await store.setDownloadRecord(key, record);
    await store.setDownloadStatus(key, 'downloaded');
  }

  static String _segmentFile(int index, String uri) {
    final String path = uri.split('?').first;
    final String ext = path.endsWith('.m4s')
        ? '.m4s'
        : path.endsWith('.mp4')
        ? '.mp4'
        : '.ts';
    return 'seg${index.toString().padLeft(6, '0')}$ext';
  }

  static bool _durationsMatch(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.5) return false;
    }
    return true;
  }

  /// Download the stream's subtitle tracks next to the video
  /// (best-effort: a failed track is skipped, the video still
  /// downloads). Returns [{label, path}] for the record.
  Future<List<Map<String, String>>> _downloadSubtitles({
    required Directory dir,
    required ResolvedStream stream,
  }) async {
    final List<Map<String, String>> saved = <Map<String, String>>[];
    for (int i = 0; i < stream.subtitles.length; i++) {
      final SubtitleInfo info = stream.subtitles[i];
      final String lower = info.url.toLowerCase().split('?').first;
      final String ext = lower.endsWith('.srt')
          ? '.srt'
          : lower.endsWith('.ass')
          ? '.ass'
          : '.vtt';
      final String name = 'sub$i$ext';
      final File f = File('${dir.path}/$name');
      try {
        final http.Response res = await _getWithRetry(info.url, stream.headers);
        await f.writeAsBytes(res.bodyBytes);
        saved.add(<String, String>{'label': info.label, 'path': f.path});
      } catch (_) {
        // Best-effort only.
      }
    }
    return saved;
  }

  Future<void> _downloadFile({
    required String key,
    required Anime anime,
    required Episode episode,
    required ResolvedStream stream,
    required SettingsStore store,
    required Map<String, dynamic>? existing,
  }) async {
    final Directory dir = await _dirFor(key);
    final String lower = stream.url.toLowerCase().split('?').first;
    final String ext = lower.endsWith('.mkv')
        ? '.mkv'
        : lower.endsWith('.webm')
        ? '.webm'
        : lower.endsWith('.mp4')
        ? '.mp4'
        : '.bin';
    final String name = 'episode$ext';
    final File f = File('${dir.path}/$name');
    int downloaded = 0;
    final bool resumable =
        existing != null &&
        existing['kind'] == 'file' &&
        existing['streamUrl'] == stream.url &&
        await f.exists();
    if (resumable) downloaded = await f.length();
    final Map<String, dynamic> record = <String, dynamic>{
      'animeId': anime.id,
      'anilistId': anime.anilistId,
      'title': anime.title,
      'posterUrl': anime.posterUrl,
      'episodeCount': anime.episodeCount,
      'episode': episode.number,
      'episodeTitle': episode.title,
      'kind': 'file',
      'streamUrl': stream.url,
      'headers': stream.headers,
      'quality': store.downloadQuality,
      'localPath': f.path,
      'bytesDownloaded': downloaded,
    };
    await store.setDownloadRecord(key, record);

    // Range-resume, STREAMED to disk (never the whole file in
    // memory): ask for the missing tail. A server that ignores Range
    // answers 200 with the whole file — restart from 0 then.
    final int total = await _streamFileToDisk(
      url: stream.url,
      headers: stream.headers,
      file: f,
      downloaded: downloaded,
    );
    downloaded = await f.length();
    record['bytesDownloaded'] = downloaded;
    record['totalBytes'] = total;
    await store.setDownloadRecord(key, record);
    await store.setDownloadProgress(
      key,
      total > 0 ? (downloaded / total).clamp(0.0, 1.0) : 0,
    );
    if (_cancelled.contains(key)) return;
    record['subtitles'] = await _downloadSubtitles(dir: dir, stream: stream);
    await store.setDownloadRecord(key, record);
    await store.setDownloadStatus(key, 'downloaded');
  }

  /// Stream one HTTP GET to [file] (append when resuming a 206).
  /// Retries the whole request up to [_maxSegmentAttempts] times.
  /// Returns the total file size when known (Content-Length +
  /// resume offset), else -1.
  Future<int> _streamFileToDisk({
    required String url,
    required Map<String, String> headers,
    required File file,
    required int downloaded,
  }) async {
    Object? lastError;
    for (int attempt = 0; attempt < _maxSegmentAttempts; attempt++) {
      try {
        final http.Request req = http.Request('GET', Uri.parse(url));
        req.headers.addAll(headers);
        if (downloaded > 0) {
          req.headers['Range'] = 'bytes=$downloaded-';
        }
        final http.StreamedResponse res = await _client.send(req);
        if (res.statusCode != 200 && res.statusCode != 206) {
          throw Exception('HTTP ${res.statusCode}');
        }
        final bool append = res.statusCode == 206 && downloaded > 0;
        final int total = res.contentLength != null && res.contentLength! > 0
            ? (append ? downloaded + res.contentLength! : res.contentLength!)
            : -1;
        final IOSink sink = file.openWrite(
          mode: append ? FileMode.append : FileMode.write,
        );
        try {
          await sink.addStream(res.stream);
          await sink.flush();
        } finally {
          await sink.close();
        }
        return total;
      } catch (e) {
        lastError = e;
        if (attempt + 1 < _maxSegmentAttempts) {
          await Future<void>.delayed(_retryDelay);
        }
      }
    }
    throw Exception('GET $url failed: $lastError');
  }
}
