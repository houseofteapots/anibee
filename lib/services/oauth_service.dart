import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Real OAuth for AniList + MyAnimeList (M2).
///
/// AniList: implicit grant — token arrives in the redirect URL fragment.
/// MAL: Authorization Code + PKCE, **plain** method only (challenge ==
/// verifier) — token exchange + refresh via POST /v1/oauth2/token.
///
/// Client IDs are NOT invented: the user creates them
/// (AniList: anilist.co/settings/developer; MAL: myanimelist.net/apiconfig,
/// App Type iOS, public, no secret) and pastes them in
/// Settings → Accounts. Redirects use the custom scheme `anibee://`
/// (registered in Info.plist) and are intercepted inside the in-app
/// webview — no external browser round-trip.
class OAuthService {
  OAuthService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String anilistRedirect = 'anibee://anilist-auth';
  static const String malRedirect = 'anibee://mal-auth';

  static const String _ua = 'AniBee/0.2.1';

  // ------------------------------------------------------------ AniList

  /// Implicit-grant authorize URL. The access token arrives in the
  /// redirect fragment: anibee://anilist-auth#access_token=...&...
  static String anilistAuthUrl(String clientId) {
    return Uri(
      scheme: 'https',
      host: 'anilist.co',
      path: '/api/v2/oauth/authorize',
      queryParameters: <String, String>{
        'client_id': clientId,
        'response_type': 'token',
        'redirect_uri': anilistRedirect,
      },
    ).toString();
  }

  /// Pull the access token out of an AniList redirect URI fragment.
  /// Pure — unit-tested.
  static String? parseAnilistRedirect(Uri uri) {
    if (uri.scheme != 'anibee' || uri.host != 'anilist-auth') return null;
    final Map<String, String> params = Uri.splitQueryString(uri.fragment);
    final String? token = params['access_token'];
    return token?.isEmpty == true ? null : token;
  }

  // --------------------------------------------------------------- MAL

  /// PKCE verifier: 64 URL-safe chars (43–128 allowed). With the
  /// **plain** method the challenge IS the verifier.
  static String generateVerifier([Random? random]) {
    final Random r = random ?? Random.secure();
    const String chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List<String>.generate(
      64,
      (_) => chars[r.nextInt(chars.length)],
    ).join();
  }

  /// MAL authorize URL (response_type=code, PKCE plain).
  static String malAuthUrl({
    required String clientId,
    required String verifier,
    required String state,
  }) {
    return Uri(
      scheme: 'https',
      host: 'myanimelist.net',
      path: '/v1/oauth2/authorize',
      queryParameters: <String, String>{
        'response_type': 'code',
        'client_id': clientId,
        'state': state,
        'redirect_uri': malRedirect,
        'code_challenge': verifier,
        'code_challenge_method': 'plain',
      },
    ).toString();
  }

  /// Pull the auth code out of a MAL redirect URI query.
  /// Pure — unit-tested.
  static String? parseMalRedirect(Uri uri, String expectedState) {
    if (uri.scheme != 'anibee' || uri.host != 'mal-auth') return null;
    if (uri.queryParameters['state'] != expectedState) return null;
    final String? code = uri.queryParameters['code'];
    return code?.isEmpty == true ? null : code;
  }

  /// Exchange a MAL auth code for access + refresh tokens.
  Future<MalTokens> exchangeMalCode({
    required String clientId,
    required String code,
    required String verifier,
  }) async {
    final http.Response resp = await _client
        .post(
          Uri.parse('https://myanimelist.net/v1/oauth2/token'),
          headers: <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': _ua,
          },
          body: <String, String>{
            'client_id': clientId,
            'grant_type': 'authorization_code',
            'code': code,
            'code_verifier': verifier,
            'redirect_uri': malRedirect,
          },
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw OAuthException('MAL token exchange failed (${resp.statusCode})');
    }
    return MalTokens.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  /// Refresh a MAL access token (access 1h, refresh 1 month).
  Future<MalTokens> refreshMalToken({
    required String clientId,
    required String refreshToken,
  }) async {
    final http.Response resp = await _client
        .post(
          Uri.parse('https://myanimelist.net/v1/oauth2/token'),
          headers: <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': _ua,
          },
          body: <String, String>{
            'client_id': clientId,
            'grant_type': 'refresh_token',
            'refresh_token': refreshToken,
          },
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw OAuthException('MAL token refresh failed (${resp.statusCode})');
    }
    return MalTokens.fromJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
  }

  /// MAL GET /v2/users/@me — display name. Throws on 401.
  Future<String> malMe(String accessToken) async {
    final http.Response resp = await _client
        .get(
          Uri.parse('https://api.myanimelist.net/v2/users/@me'),
          headers: <String, String>{
            'Authorization': 'Bearer $accessToken',
            'User-Agent': _ua,
          },
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw OAuthException('MAL @me failed (${resp.statusCode})');
    }
    final Map<String, dynamic> json =
        jsonDecode(resp.body) as Map<String, dynamic>;
    return json['name'] as String? ?? 'MyAnimeList user';
  }

  /// MAL PUT /v2/anime/{malId}/my_list_status — push a Collection
  /// status ('watching' | 'completed' | 'plan_to_watch'). Best-effort.
  Future<bool> malSaveListStatus(
    String accessToken,
    int malId,
    String status,
  ) async {
    try {
      final http.Response resp = await _client
          .put(
            Uri.parse(
              'https://api.myanimelist.net/v2/anime/$malId/my_list_status',
            ),
            headers: <String, String>{
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/x-www-form-urlencoded',
              'User-Agent': _ua,
            },
            body: <String, String>{'status': status},
          )
          .timeout(const Duration(seconds: 15));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

class MalTokens {
  const MalTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresInSeconds,
  });

  factory MalTokens.fromJson(Map<String, dynamic> json) {
    return MalTokens(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      expiresInSeconds: (json['expires_in'] as num?)?.toInt() ?? 3600,
    );
  }

  final String accessToken;
  final String refreshToken;
  final int expiresInSeconds;

  bool get isValid => accessToken.isNotEmpty && refreshToken.isNotEmpty;
}

class OAuthException implements Exception {
  const OAuthException(this.message);
  final String message;
  @override
  String toString() => 'OAuthException: $message';
}
