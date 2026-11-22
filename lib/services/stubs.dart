import 'provider_config.dart';

/// M1 service stubs.
/// No real network calls happen in milestone 1 — the UI shell runs on mock
/// data (see models.dart). Milestone 2 wires these up, one at a time.
///
/// SOURCES ARCHITECTURE (user-decided 2026-11-23 01:25): BUILT-IN, Anilili
/// style. Miruro + Anikoto resolvers are compiled into the app in Dart
/// (lib/services/miruro_resolver.dart, anikoto_resolver.dart in M2) — no
/// plugin import needed. Resolve happens ON-DEVICE (see Miruro notes
/// below). .cs3 plugin import is a FUTURE extra option only — do NOT
/// build it in milestone 1.
///
/// MIRURO — no official API; reverse-engineered SvelteKit endpoints.
/// Resolve MUST happen on-device: Cloudflare blocks datacenter IPs, so a
/// server-side fetch gets 403. Mirrors + endpoints now live in the REMOTE
/// provider config (see provider_config.dart): mirror rotation + provider
/// fallback live there, so a domain change is fixed by one JSON edit,
/// no app update.
/// Endpoints (relative to a mirror origin):
/// - GET `/api/search/browse?q=<query>&limit=8&type=ANIME`
///     -> `{data, next_cursor, has_more}`
/// - GET `/api/sources?id=<id>&n=<episodeNumber>`
///     -> `{episodeNumber, tracks, config, providerOrder}`
/// - GET `/info/<id>/<slug>/__data.json` -> detail + episodes
/// - GET `/watch/<id>/<slug>/__data.json?ep=<number>` -> media + sourcesData
/// Route-data (__data.json) responses need the SvelteKit decoder even when
/// Content-Type is application/json.
class MiruroService {
  MiruroService(this.configService);

  final ProviderConfigService configService;

  /// Search the Miruro catalogue. M2.
  Future<List<Map<String, dynamic>>> search(String query) async {
    // TODO(m2): GET endpointUrl('miruro', 'search', params: {'q': query})
    // on the live mirror, SvelteKit decode. On failure, mark the mirror
    // failed (rotation) and retry the next mirror; if all fail, the
    // caller falls back to the next provider in configService.fallbackOrder().
    return <Map<String, dynamic>>[];
  }

  /// Fresh episode sources (m3u8 + subtitles). M2.
  Future<Map<String, dynamic>?> episodeSources({
    required String id,
    required int episode,
  }) async {
    // TODO(m2): GET endpointUrl('miruro', 'sources',
    //   params: {'id': id, 'episode': episode.toString()}).
    return null;
  }
}

/// AniList GraphQL — metadata, search, lists, progress sync.
/// Public queries need no key; user sync needs an OAuth token (M2).
/// Endpoint: https://graphql.anilist.co
class AniListService {
  Future<List<Map<String, dynamic>>> trending() async {
    // TODO(m2): Page { media(type: ANIME, sort: TRENDING_DESC) { ... } }
    return <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>?> detail(int anilistId) async {
    // TODO(m2): Media(id: $id) { title, description, episodes, trailer { ... } }
    return null;
  }
}

/// MyAnimeList — lists + progress sync. Needs OAuth (client id) in M2.
/// Endpoint: https://api.myanimelist.net/v2
class MyAnimeListService {
  Future<bool> login() async {
    // TODO(m2): OAuth flow, token stored in secure storage.
    return false;
  }
}

/// AniSkip — Skip Intro / Skip Outro timestamps.
/// GET `https://api.aniskip.com/v2/skip-times?malId=<id>`
///     `&episodeNumber=<n>&episodeLength=<seconds>`
/// -> `{ results: [{ skipType: 'op'|'ed', interval: {startTime, endTime} }] }`
/// VERIFIED LIVE (2026-11-23): e.g. Demon Slayer MAL 38000 ep 1 OP 5.6-95.6s.
/// Note: some titles have NO segments in the DB — a data-coverage gap,
/// not an app bug.
class AniSkipService {
  Future<List<Map<String, dynamic>>> skipTimes({
    required int malId,
    required int episode,
    required double episodeLength,
  }) async {
    // TODO(m2): GET api.aniskip.com/v2/skip-times.
    return <Map<String, dynamic>>[];
  }
}

/// Debrid — TorBox + Real-Debrid.
/// M1: Settings UI only (API key entry + connected state). The user connects
/// his own paid account later. M2: resolve cached links via the debrid APIs
/// and move keys to secure storage (flutter_secure_storage).
class DebridService {
  static const String torboxApiBase = 'https://api.torbox.app/v1/api';
  static const String realDebridApiBase =
      'https://api.real-debrid.com/rest/1.0';
}
