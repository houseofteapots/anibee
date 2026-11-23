import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Real OAuth for AniList + MyAnimeList (M2).
///
/// AniList: implicit grant — token arrives in the redirect URL fragment.
/// MAL: Authorization Code + PKCE, **plain** method only (challenge ==
/// verifier) — token exchange + refresh via POST /v1/oauth2/token.
///
/// 0.2.8 (Zeus-mirror): both providers redirect to
/// `http://localhost` — exactly how Zeus's working login on this phone
/// does it (`SyncConfig.signInRedirect`, intercepted by its native
/// WKWebView delegate). The custom `anibee://` scheme is kept ONLY as
/// a fallback parse shape: on 0.2.5–0.2.7 the fragment was stripped
/// between AniList's redirect and the Dart callback for the
/// custom-scheme server redirect, so the token never arrived (the
/// generic "no token returned" toast on every phone test). An http
/// URL is handled routinely by WKWebView, and the redirect is caught
/// three ways in the webview (navigation request, URL change, and
/// resource error — the last one fires when the localhost load itself
/// fails, and still carries the full redirect URL).
///
/// 0.2.9: the token/code extraction is HOST-AGNOSTIC (see
/// [parseAnilistRedirect] / [parseMalRedirect]) — the token is read
/// out of ANY redirect URL the webview reports, whatever its scheme,
/// host or path. That is what finally fixed login on the phone: the
/// user's registered AniList Redirect URL contains a space
/// ("anibee:// anilist-auth"), so AniList redirects to
/// `anibee://%20anilist-auth#access_token=...` and the 0.2.8 exact
/// host gate (`uri.host == 'anilist-auth'`) rejected a token that
/// had actually arrived (0.2.8 phone test, 2026-11-23). The
/// localhost intercept stays as the preferred path, but the
/// registered URL no longer has to match anything exactly.
///
/// Client IDs are NOT invented: the user creates them
/// (AniList: anilist.co/settings/developer; MAL: myanimelist.net/apiconfig,
/// App Type iOS, public, no secret). 0.2.9: the registered Redirect
/// URL no longer has to be `http://localhost` — the token/code is
/// extracted from whatever URL the provider actually redirects to
/// (the user's AniList client has "anibee:// anilist-auth" with a
/// space, and that works now). The manual paste fallback in the
/// login sheet still exists: AniList's PIN page prints the token on
/// screen, and the sheet shows the last redirect URL (copyable) for
/// MAL's code.
class OAuthService {
  OAuthService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String anilistRedirect = 'anibee://anilist-auth';

  /// Zeus's redirect, mirrored in 0.2.8: the registered Redirect URL
  /// on both clients must be exactly this. MAL's legacy custom-scheme
  /// redirect (`anibee://mal-auth`) is kept as a fallback parse shape
  /// only — the authorize URL and the token exchange both send the
  /// localhost redirect now.
  static const String localRedirect = 'http://localhost';
  static const String malRedirect = 'http://localhost';
  static const String legacyMalRedirect = 'anibee://mal-auth';

  static const String _ua = 'AniBee/0.2.1';

  // ------------------------------------------------------------ AniList

  /// Implicit-grant authorize URL. NO redirect_uri (0.2.5, Zeus-proven):
  /// with none sent, AniList answers on its default PIN page and the
  /// token arrives in that URL's fragment:
  /// anilist.co/api/v2/oauth/pin#access_token=...
  static String anilistAuthUrl(String clientId) {
    return Uri(
      scheme: 'https',
      host: 'anilist.co',
      path: '/api/v2/oauth/authorize',
      queryParameters: <String, String>{
        'client_id': clientId,
        'response_type': 'token',
      },
    ).toString();
  }

  /// True for AniList's default PIN page — the answer to an authorize
  /// request sent without a redirect_uri. The login webview intercepts
  /// this URL and returns it to the caller instead of loading it.
  static bool isAnilistPinUrl(Uri uri) {
    return uri.scheme == 'https' &&
        uri.host == 'anilist.co' &&
        uri.path == '/api/v2/oauth/pin';
  }

  /// True for the Zeus-mirror redirect: http://localhost (path '/'
  /// or empty). AniList / MAL redirect here when the client's
  /// registered Redirect URL is exactly this — the webview intercepts
  /// it before the (failing) load. Pure — unit-tested.
  static bool isLocalRedirect(Uri uri) {
    return uri.scheme == 'http' &&
        uri.host == 'localhost' &&
        uri.port == 80 &&
        (uri.path.isEmpty || uri.path == '/');
  }

  /// Pull the access token out of an AniList answer URL — HOST-AGNOSTIC
  /// (0.2.9). The token is read from the fragment (query as fallback)
  /// of ANY URL the webview reports, regardless of scheme, host or
  /// path. Shapes that must all yield the token:
  /// - PIN page (0.2.5): https://anilist.co/api/v2/oauth/pin#access_token=...
  /// - Localhost redirect (0.2.8, Zeus-mirror):
  ///   http://localhost/#access_token=...
  /// - Custom-scheme fallback: anibee://anilist-auth#access_token=...
  /// - The 0.2.8 phone failure: the user's registered Redirect URL
  ///   contains a space ("anibee:// anilist-auth"), so AniList
  ///   redirects to `anibee://%20anilist-auth#access_token=...`.
  ///   The 0.2.8 exact host gate rejected that URL even though the
  ///   token had arrived — there is no host check here any more, on
  ///   purpose. Do NOT re-add one.
  /// A URL with no access_token still returns null. Some webviews
  /// convert the fragment `#` to `?` — the query params are checked
  /// as a fallback (Zeus pattern). Pure — unit-tested.
  static String? parseAnilistRedirect(Uri uri) {
    return _tokenFromFragmentOrQuery(uri);
  }

  static String? _tokenFromFragmentOrQuery(Uri uri) {
    if (uri.fragment.isNotEmpty) {
      final Map<String, String> params = Uri.splitQueryString(uri.fragment);
      final String? token = params['access_token'];
      if (token != null && token.isNotEmpty) return token;
    }
    final String? queryToken = uri.queryParameters['access_token'];
    return queryToken?.isEmpty == true ? null : queryToken;
  }

  /// Pull the access token out of the AniList PIN page's visible
  /// text (0.2.6). The pin page prints the token on screen (the user
  /// is meant to copy it); when the webview fails to capture the
  /// token from the redirect URL fragment — the 0.2.5 phone failure,
  /// where Authorize was tapped and still no token came back — the
  /// body text is the fallback. Returns the longest run of token
  /// characters (>= 100 chars; an AniList access token is a long
  /// JWT-style string) or null. Pure — unit-tested.
  static String? extractTokenFromPinPageText(String? text) {
    if (text == null) return null;
    String raw = text.trim();
    // runJavaScriptReturningResult may return the string JSON-encoded
    // (wrapped in quotes) — unwrap one layer, same as the webview.
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is String) raw = decoded.trim();
      } catch (_) {}
    }
    final RegExp tokenPattern = RegExp(r'[A-Za-z0-9._\-]{100,}');
    String? longest;
    for (final RegExpMatch m in tokenPattern.allMatches(raw)) {
      final String candidate = m.group(0)!;
      if (longest == null || candidate.length > longest.length) {
        longest = candidate;
      }
    }
    return longest;
  }

  /// Human-readable login error for an OAuth error code, in the user's
  /// own words (Roman Hinglish). AniList answers a bad authorize
  /// request with a raw JSON error body — `unsupported_grant_type`
  /// when the redirect URI registered on the client does not exactly
  /// match the one the app sends (`anibee://anilist-auth`). The login
  /// sheet shows this text, never the raw JSON. Pure — unit-tested.
  static String readableOAuthError({
    required String provider,
    required String error,
    String? message,
  }) {
    final String redirect = provider == 'MyAnimeList'
        ? malRedirect
        : anilistRedirect;
    switch (error) {
      case 'unsupported_grant_type':
        // 0.2.5: AniList no longer gets a redirect_uri at all (PIN
        // flow) — telling the user to set one would be wrong. MAL
        // redirects to http://localhost (0.2.8, Zeus-mirror), so its
        // message keeps the redirect hint with the localhost URL.
        if (provider == 'MyAnimeList') {
          return '$provider ne login reject kiya — apne $provider client ki '
              'Redirect URL bilkul $redirect honi chahiye. '
              '$provider → Settings → Developer mein apne client ki '
              'Redirect Url check karo.';
        }
        return 'AniList ne login reject kiya — dobara try karo. AniBee '
            'PIN se login karta hai, redirect URL ki zaroorat nahi hai.';
      case 'invalid_client':
        return '$provider ne client ko pehchana nahi — client ID galat '
            'hai ya client delete ho gaya.';
      case 'access_denied':
        return 'Login cancel kar diya gaya.';
      default:
        final String detail = (message ?? '').trim();
        return detail.isEmpty
            ? '$provider login fail ho gaya ($error).'
            : '$provider login fail ho gaya: $detail';
    }
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

  /// Pull the auth code out of a MAL redirect URI query — HOST-AGNOSTIC
  /// (0.2.9, same fix as AniList). The code is read from the query
  /// of ANY redirect URL, whatever its scheme, host or path: the
  /// Zeus-mirror `http://localhost/?code=...&state=...`, the legacy
  /// `anibee://mal-auth?code=...&state=...`, or a registered
  /// redirect with a stray space / different host. The `state` check
  /// is the CSRF gate and stays — a mismatched state is still
  /// rejected, and a URL with no code still returns null.
  /// Pure — unit-tested.
  static String? parseMalRedirect(Uri uri, String expectedState) {
    if (uri.queryParameters['state'] != expectedState) return null;
    final String? code = uri.queryParameters['code'];
    return code?.isEmpty == true ? null : code;
  }

  /// Pull a MAL auth code (+ state, when present) out of pasted text
  /// (0.2.8 manual fallback): either the full redirect URL
  /// (`http://localhost/?code=...&state=...`, copied from the sheet's
  /// last-URL line) or a bare code. Returns (null, null) when the
  /// text carries no code. Pure — unit-tested.
  static ({String? code, String? state}) extractMalCodeFromText(String? text) {
    if (text == null) return (code: null, state: null);
    final String raw = text.trim();
    if (raw.isEmpty) return (code: null, state: null);
    final Uri? uri = Uri.tryParse(raw);
    if (uri != null && uri.queryParameters.containsKey('code')) {
      final String? code = uri.queryParameters['code'];
      return (
        code: code?.isEmpty == true ? null : code,
        state: uri.queryParameters['state'],
      );
    }
    // Bare code: one run of URL-safe characters, no spaces, no scheme.
    if (RegExp(r'^[A-Za-z0-9\-_]{10,}$').hasMatch(raw)) {
      return (code: raw, state: null);
    }
    return (code: null, state: null);
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
    return MalTokens.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
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
    return MalTokens.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
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
