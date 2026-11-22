import '../models.dart';
import '../settings_store.dart';
import 'anilist_service.dart';
import 'debrid_service.dart';
import 'miruro_resolver.dart';
import 'oauth_service.dart';
import 'provider_config.dart';

/// All M2 services, created once in main() and passed down through
/// AppShell so screens never construct their own clients.
class AppServices {
  AppServices({
    required this.anilist,
    required this.miruro,
    required this.debrid,
    required this.oauth,
    this.configService,
  });

  factory AppServices.create({ProviderConfigService? configService}) {
    final AniListService anilist = AniListService();
    return AppServices(
      anilist: anilist,
      miruro: MiruroResolver(anilist: anilist),
      debrid: DebridService(),
      oauth: OAuthService(),
      configService: configService,
    );
  }

  final AniListService anilist;
  final MiruroResolver miruro;
  final DebridService debrid;
  final OAuthService oauth;

  /// Remote config (OAuth client IDs live here in 0.2.3).
  final ProviderConfigService? configService;

  /// Resolve a playable stream for an episode.
  /// [debrid] is null (Miruro/Anikoto) or 'torbox' / 'realdebrid'.
  /// Returns null when nothing resolved — [miruro.lastError] /
  /// the debrid path carries the reason.
  Future<ResolvedStream?> resolveEpisode({
    required Anime anime,
    required int episode,
    required String subDub,
    required SettingsStore store,
    String? debrid,
    void Function(String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (debrid == 'torbox' && store.torboxApiKey != null) {
      return this.debrid.resolveEpisode(
        service: 'torbox',
        apiKey: store.torboxApiKey!,
        title: anime.title,
        episode: episode,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    }
    if (debrid == 'realdebrid' && store.realDebridApiKey != null) {
      return this.debrid.resolveEpisode(
        service: 'realdebrid',
        apiKey: store.realDebridApiKey!,
        title: anime.title,
        episode: episode,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    }
    return miruro.resolve(
      anime: anime,
      episodeNumber: episode,
      subDub: subDub,
    );
  }

  /// Push a Collection status to AniList + MAL (best-effort, never
  /// throws). Resolves the MAL id via AniList when the catalogue entry
  /// doesn't carry one. Called when the user changes My List status
  /// or starts/finishes an anime.
  Future<void> pushListStatus({
    required SettingsStore store,
    required Anime anime,
    required String status, // 'watching' | 'finished' | 'plan'
  }) async {
    if (store.anilistConnected && anime.anilistId != null) {
      final String anilistStatus = switch (status) {
        'finished' => 'COMPLETED',
        'plan' => 'PLANNING',
        _ => 'CURRENT',
      };
      await anilist.saveListEntry(
        store.anilistToken!,
        anime.anilistId!,
        anilistStatus,
      );
    }
    if (store.malConnected) {
      int? malId = anime.malId;
      if (malId == null && anime.anilistId != null) {
        try {
          final Anime? detail = await anilist.mediaById(anime.anilistId!);
          malId = detail?.malId;
        } catch (_) {
          malId = null;
        }
      }
      if (malId != null) {
        final String malStatus = switch (status) {
          'finished' => 'completed',
          'plan' => 'plan_to_watch',
          _ => 'watching',
        };
        await _malWithRefresh(store, (String token) async {
          await oauth.malSaveListStatus(token, malId!, malStatus);
        });
      }
    }
  }

  /// Run a MAL call with a fresh token (refresh when expired).
  /// Returns false when no usable token exists.
  Future<bool> _malWithRefresh(
    SettingsStore store,
    Future<void> Function(String token) call,
  ) async {
    String? token = store.malAccessToken;
    if (token == null || token.isEmpty) return false;
    final DateTime? expiry = store.malTokenExpiry;
    if (expiry != null &&
        DateTime.now().isAfter(expiry.subtract(const Duration(minutes: 5)))) {
      final String? refresh = store.malRefreshToken;
      // 0.2.3: the MAL client ID comes from the remote config now
      // (never typed in by the user).
      final String clientId =
          configService?.config.malClientId ?? '';
      if (refresh == null || clientId.isEmpty) return false;
      try {
        final MalTokens tokens = await oauth.refreshMalToken(
          clientId: clientId,
          refreshToken: refresh,
        );
        if (!tokens.isValid) return false;
        await store.setMalSession(
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          expiry: DateTime.now().add(
            Duration(seconds: tokens.expiresInSeconds),
          ),
          username: store.malUsername,
        );
        token = tokens.accessToken;
      } catch (_) {
        return false;
      }
    }
    try {
      await call(token);
      return true;
    } catch (_) {
      return false;
    }
  }
}
