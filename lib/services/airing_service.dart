import 'anilist_service.dart';

/// One upcoming airing episode (0.2.10): which anime, which
/// episode, and exactly when it airs (UTC).
class AiringEntry {
  const AiringEntry({
    required this.anilistId,
    required this.title,
    required this.episode,
    required this.airingAt,
    this.posterUrl,
    this.episodeCount = 0,
  });

  /// Parse one AniList Media object. Null when it has no id/title
  /// or no next airing episode — only airing titles are entries.
  static AiringEntry? fromMedia(Map<String, dynamic> m) {
    final int? id = (m['id'] as num?)?.toInt();
    final Map<String, dynamic>? next =
        m['nextAiringEpisode'] as Map<String, dynamic>?;
    if (id == null || next == null) return null;
    final int? airingAt = (next['airingAt'] as num?)?.toInt();
    final int? episode = (next['episode'] as num?)?.toInt();
    if (airingAt == null || episode == null) return null;
    final Map<String, dynamic>? title = m['title'] as Map<String, dynamic>?;
    final String name = AniListService.preferredTitle(title);
    if (name.isEmpty || name == 'Unknown') return null;
    final Map<String, dynamic>? cover =
        m['coverImage'] as Map<String, dynamic>?;
    return AiringEntry(
      anilistId: id,
      title: name,
      episode: episode,
      airingAt: DateTime.fromMillisecondsSinceEpoch(
        airingAt * 1000,
        isUtc: true,
      ),
      posterUrl: cover?['large'] as String?,
      episodeCount: (m['episodes'] as num?)?.toInt() ?? 0,
    );
  }

  final int anilistId;
  final String title;
  final int episode;
  final DateTime airingAt;
  final String? posterUrl;
  final int episodeCount;
}

/// Live countdown text for an airing episode (pure — unit-tested):
/// "in 2d 4h", "in 3h 12m", "in 45m", "in 1m", "Airing now".
String formatAiringCountdown(DateTime airingAt, {DateTime? now}) {
  final Duration left = airingAt.difference(now ?? DateTime.now());
  if (left <= Duration.zero) return 'Airing now';
  if (left.inDays > 0) {
    return 'in ${left.inDays}d ${left.inHours % 24}h';
  }
  if (left.inHours > 0) {
    return 'in ${left.inHours}h ${left.inMinutes % 60}m';
  }
  if (left.inMinutes > 0) return 'in ${left.inMinutes}m';
  return 'in ${left.inSeconds}s';
}

/// Keep only future airings, soonest first, capped (pure —
/// unit-tested). The cap keeps the Home row and the notification
/// schedule sane (20).
List<AiringEntry> sortAiringEntries(
  List<AiringEntry> entries, {
  DateTime? now,
  int limit = 20,
}) {
  final DateTime at = now ?? DateTime.now();
  final List<AiringEntry> upcoming = entries
      .where((AiringEntry e) => e.airingAt.isAfter(at))
      .toList()
    ..sort((AiringEntry a, AiringEntry b) => a.airingAt.compareTo(b.airingAt));
  return upcoming.length > limit ? upcoming.sublist(0, limit) : upcoming;
}

/// Upcoming airing episodes (0.2.10) — AniList GraphQL
/// `nextAiringEpisode { airingAt, timeUntilAiring, episode }`.
///
/// Sources, in order:
/// 1. Logged in ([token]): the user's AniList list (CURRENT /
///    PLANNING / REPEATING) — only followed titles air here, and
///    only these get notifications.
/// 2. Not logged in, but [followedIds] (Continue Watching AniList
///    ids): those titles by id.
/// 3. Neither: currently-airing popular titles (public query) so
///    the Home row still shows something before login.
///
/// Empty on any failure — the caller hides the Home row.
class AiringService {
  AiringService({required this.anilist});

  final AniListService anilist;

  static const String _mediaFields =
      'id title{romaji english} coverImage{large} episodes '
      'nextAiringEpisode{airingAt timeUntilAiring episode}';

  Future<List<AiringEntry>> fetchAiring({
    String? token,
    List<int>? followedIds,
  }) async {
    final List<AiringEntry> entries;
    if (token != null && token.isNotEmpty) {
      entries = await _fetchUserAiring(token);
    } else if (followedIds != null && followedIds.isNotEmpty) {
      entries = await _fetchAiringForIds(followedIds);
    } else {
      entries = await _fetchTrendingAiring();
    }
    return sortAiringEntries(entries);
  }

  Future<List<AiringEntry>> _fetchUserAiring(String token) async {
    try {
      final ({int id, String name}) v = await anilist.viewer(token);
      const String q =
          r'query($id:Int){MediaListCollection(userId:$id,type:ANIME,'
          r'status_in:[CURRENT,PLANNING,REPEATING])'
          r'{lists{entries{media{';
      final Map<String, dynamic>? data = await anilist.queryGraphQL(
        '$q $_mediaFields}}}}}',
        <String, Object?>{'id': v.id},
        token: token,
      );
      final List<dynamic> lists =
          (data?['MediaListCollection'] as Map<String, dynamic>?)?['lists']
                  as List<dynamic>? ??
              <dynamic>[];
      final List<AiringEntry> out = <AiringEntry>[];
      for (final dynamic list in lists) {
        final List<dynamic> es =
            (list as Map<String, dynamic>)['entries'] as List<dynamic>? ??
            <dynamic>[];
        for (final dynamic e in es) {
          final Map<String, dynamic>? media =
              (e as Map<String, dynamic>)['media'] as Map<String, dynamic>?;
          if (media == null) continue;
          final AiringEntry? entry = AiringEntry.fromMedia(media);
          if (entry != null) out.add(entry);
        }
      }
      return out;
    } catch (_) {
      return <AiringEntry>[];
    }
  }

  Future<List<AiringEntry>> _fetchAiringForIds(List<int> ids) async {
    const String q =
        r'query($ids:[Int]){Page(perPage:50){media(id_in:$ids,type:ANIME){';
    final Map<String, dynamic>? data = await anilist.queryGraphQL(
      '$q $_mediaFields}}}',
      <String, Object?>{'ids': ids},
    );
    return _parsePage(data);
  }

  Future<List<AiringEntry>> _fetchTrendingAiring() async {
    const String q =
        r'query{Page(perPage:20){media(type:ANIME,status:RELEASING,'
        r'sort:POPULARITY_DESC){';
    final Map<String, dynamic>? data = await anilist.queryGraphQL(
      '$q $_mediaFields}}}',
      <String, Object?>{},
    );
    return _parsePage(data);
  }

  List<AiringEntry> _parsePage(Map<String, dynamic>? data) {
    final List<dynamic> media =
        (data?['Page'] as Map<String, dynamic>?)?['media']
                as List<dynamic>? ??
            <dynamic>[];
    return media
        .map(
          (dynamic e) =>
              AiringEntry.fromMedia(e as Map<String, dynamic>),
        )
        .whereType<AiringEntry>()
        .toList();
  }
}
