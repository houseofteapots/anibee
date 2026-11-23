import 'dart:convert';
import 'dart:math' as math;

import 'package:anibee/services/oauth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// M2: AniList (implicit grant) + MAL (Authorization Code + PKCE plain)
/// OAuth — URL building, redirect parsing, token exchange.
/// No client IDs are invented here: the tests use placeholder ids,
/// exactly like the Settings screen does before the user pastes his own.
void main() {
  group('AniList OAuth', () {
    test('auth URL is the implicit grant with NO redirect_uri (PIN flow)', () {
      // 0.2.5: Zeus-proven PIN flow — sending redirect_uri made
      // AniList reject the authorize request with
      // unsupported_grant_type even when the registered redirect
      // matched. The token comes back on the PIN page instead.
      final Uri url = Uri.parse(OAuthService.anilistAuthUrl('client-123'));
      expect(url.scheme, 'https');
      expect(url.host, 'anilist.co');
      expect(url.path, '/api/v2/oauth/authorize');
      expect(url.queryParameters['client_id'], 'client-123');
      expect(url.queryParameters['response_type'], 'token');
      expect(url.queryParameters.containsKey('redirect_uri'), isFalse);
    });

    test('auth URL for client 57814 is exactly the documented URL', () {
      // 0.2.5: PIN flow — client_id + response_type only, no
      // redirect_uri. The URL must be byte-exact (no extra params).
      expect(
        OAuthService.anilistAuthUrl('57814'),
        'https://anilist.co/api/v2/oauth/authorize'
        '?client_id=57814&response_type=token',
      );
    });

    test('readableOAuthError explains unsupported_grant_type', () {
      final String msg = OAuthService.readableOAuthError(
        provider: 'AniList',
        error: 'unsupported_grant_type',
        message: 'The authorization grant type is not supported by the authorization server.',
      );
      // 0.2.5 PIN flow: the app sends no redirect_uri, so the message
      // must NOT tell the user to set one.
      expect(msg, isNot(contains('anibee://anilist-auth')));
      expect(msg, contains('PIN'));
      expect(msg, isNot(contains('unsupported_grant_type')));
      expect(msg, isNot(contains('{')));
      // MAL redirects to http://localhost (0.2.8, Zeus-mirror) —
      // its message keeps the redirect hint with that URL.
      expect(
        OAuthService.readableOAuthError(
          provider: 'MyAnimeList',
          error: 'unsupported_grant_type',
        ),
        contains('http://localhost'),
      );
    });

    test(
      'readableOAuthError covers invalid_client / access_denied / other',
      () {
        expect(
          OAuthService.readableOAuthError(
            provider: 'AniList',
            error: 'invalid_client',
          ),
          contains('client ID'),
        );
        expect(
          OAuthService.readableOAuthError(
            provider: 'AniList',
            error: 'access_denied',
          ),
          contains('cancel'),
        );
        expect(
          OAuthService.readableOAuthError(
            provider: 'MyAnimeList',
            error: 'invalid_request',
            message: 'Missing code_challenge',
          ),
          contains('Missing code_challenge'),
        );
        expect(
          OAuthService.readableOAuthError(
            provider: 'MyAnimeList',
            error: 'invalid_request',
          ),
          contains('invalid_request'),
        );
      },
    );

    test('parseAnilistRedirect pulls the token from the fragment', () {
      expect(
        OAuthService.parseAnilistRedirect(
          Uri.parse(
            'anibee://anilist-auth#access_token=tok-abc&token_type=Bearer&expires_in=31536000',
          ),
        ),
        'tok-abc',
      );
    });

    test('parseAnilistRedirect accepts the PIN page token', () {
      // 0.2.5 PIN flow: the token comes back on AniList's default PIN
      // page — fragment first, with the #-to-? fallback (some webview
      // implementations rewrite # to ?).
      expect(
        OAuthService.parseAnilistRedirect(
          Uri.parse(
            'https://anilist.co/api/v2/oauth/pin#access_token=pin-tok&token_type=Bearer&expires_in=31536000',
          ),
        ),
        'pin-tok',
      );
      expect(
        OAuthService.parseAnilistRedirect(
          Uri.parse(
            'https://anilist.co/api/v2/oauth/pin?access_token=pin-tok2',
          ),
        ),
        'pin-tok2',
      );
      // PIN page without a token, and a wrong host/path, are rejected.
      expect(
        OAuthService.parseAnilistRedirect(
          Uri.parse('https://anilist.co/api/v2/oauth/pin'),
        ),
        isNull,
      );
      expect(
        OAuthService.parseAnilistRedirect(
          Uri.parse('https://anilist.co/api/v2/oauth/other#access_token=x'),
        ),
        isNull,
      );
      expect(
        OAuthService.parseAnilistRedirect(
          Uri.parse('https://evil.example/api/v2/oauth/pin#access_token=x'),
        ),
        isNull,
      );
    });

    test('parseAnilistRedirect rejects wrong scheme / host / empty token', () {
      expect(
        OAuthService.parseAnilistRedirect(
          Uri.parse('anibee://other#access_token=x'),
        ),
        isNull,
      );
      expect(
        OAuthService.parseAnilistRedirect(
          Uri.parse('anibee://anilist-auth#token_type=Bearer'),
        ),
        isNull,
      );
    });

    test('extractTokenFromPinPageText pulls the printed token', () {
      // 0.2.6: the PIN page prints the token on screen — the
      // fallback when the redirect fragment is lost. A realistic
      // JWT-style token (3 dot-separated base64url segments).
      const String token =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
          'eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.'
          'SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
      expect(token.length, greaterThan(100));
      expect(
        OAuthService.extractTokenFromPinPageText(
          'Your authorization PIN is:\n$token\nCopy it into the app.',
        ),
        token,
      );
      // Bare token alone, and JSON-quoted (runJavaScriptReturningResult
      // wraps strings in quotes).
      expect(OAuthService.extractTokenFromPinPageText(token), token);
      expect(
        OAuthService.extractTokenFromPinPageText('"$token"'),
        token,
      );
      // Short strings, empty text, and a page with no token give null.
      expect(
        OAuthService.extractTokenFromPinPageText('Authorize this app?'),
        isNull,
      );
      expect(OAuthService.extractTokenFromPinPageText(''), isNull);
      expect(OAuthService.extractTokenFromPinPageText(null), isNull);
      expect(
        OAuthService.extractTokenFromPinPageText('{"error":"access_denied"}'),
        isNull,
      );
    });

    test('isAnilistPinUrl matches only the real PIN page', () {
      expect(
        OAuthService.isAnilistPinUrl(
          Uri.parse('https://anilist.co/api/v2/oauth/pin'),
        ),
        isTrue,
      );
      expect(
        OAuthService.isAnilistPinUrl(
          Uri.parse('https://anilist.co/api/v2/oauth/pin#access_token=x'),
        ),
        isTrue,
      );
      expect(
        OAuthService.isAnilistPinUrl(
          Uri.parse('https://anilist.co/api/v2/oauth/authorize'),
        ),
        isFalse,
      );
      expect(
        OAuthService.isAnilistPinUrl(
          Uri.parse('http://anilist.co/api/v2/oauth/pin'),
        ),
        isFalse,
      );
      expect(
        OAuthService.isAnilistPinUrl(
          Uri.parse('https://evil.example/api/v2/oauth/pin'),
        ),
        isFalse,
      );
    });
  });

  group('MAL OAuth (PKCE plain)', () {
    test('generateVerifier is 64 URL-safe chars', () {
      final String v = OAuthService.generateVerifier();
      expect(v.length, 64);
      expect(RegExp(r'^[A-Za-z0-9\-._~]{64}$').hasMatch(v), isTrue);
      // Seeded Random is deterministic (used by tests only).
      expect(
        OAuthService.generateVerifier(math.Random(42)),
        OAuthService.generateVerifier(math.Random(42)),
      );
    });

    test('auth URL carries code_challenge == verifier (plain)', () {
      const String verifier = 'verifier-abc-123';
      final Uri url = Uri.parse(
        OAuthService.malAuthUrl(
          clientId: 'mal-client-9',
          verifier: verifier,
          state: 'state-xyz',
        ),
      );
      expect(url.host, 'myanimelist.net');
      expect(url.path, '/v1/oauth2/authorize');
      expect(url.queryParameters['response_type'], 'code');
      expect(url.queryParameters['client_id'], 'mal-client-9');
      expect(url.queryParameters['code_challenge'], verifier);
      expect(url.queryParameters['code_challenge_method'], 'plain');
      expect(url.queryParameters['redirect_uri'], 'http://localhost');
      expect(url.queryParameters['state'], 'state-xyz');
    });

    test('parseMalRedirect checks state and pulls the code', () {
      expect(
        OAuthService.parseMalRedirect(
          Uri.parse('anibee://mal-auth?code=code-1&state=state-xyz'),
          'state-xyz',
        ),
        'code-1',
      );
      // Wrong state = rejected (CSRF protection).
      expect(
        OAuthService.parseMalRedirect(
          Uri.parse('anibee://mal-auth?code=code-1&state=attacker'),
          'state-xyz',
        ),
        isNull,
      );
      expect(
        OAuthService.parseMalRedirect(
          Uri.parse('anibee://mal-auth?state=state-xyz'),
          'state-xyz',
        ),
        isNull,
      );
    });

    test('exchangeMalCode posts the code + verifier, parses tokens', () async {
      final OAuthService svc = OAuthService(
        client: MockClient((http.Request req) async {
          expect(req.url.toString(), 'https://myanimelist.net/v1/oauth2/token');
          final Map<String, String> body = Uri.splitQueryString(req.body);
          expect(body['grant_type'], 'authorization_code');
          expect(body['client_id'], 'mal-client-9');
          expect(body['code'], 'code-1');
          expect(body['code_verifier'], 'verifier-abc-123');
          expect(body['redirect_uri'], 'http://localhost');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'access_token': 'at-1',
              'refresh_token': 'rt-1',
              'expires_in': 3600,
              'token_type': 'Bearer',
            }),
            200,
          );
        }),
      );
      final MalTokens tokens = await svc.exchangeMalCode(
        clientId: 'mal-client-9',
        code: 'code-1',
        verifier: 'verifier-abc-123',
      );
      expect(tokens.isValid, isTrue);
      expect(tokens.accessToken, 'at-1');
      expect(tokens.refreshToken, 'rt-1');
      expect(tokens.expiresInSeconds, 3600);
    });

    test('exchangeMalCode throws on a bad code', () async {
      final OAuthService svc = OAuthService(
        client: MockClient((_) async => http.Response('bad', 400)),
      );
      expect(
        () => svc.exchangeMalCode(clientId: 'x', code: 'bad', verifier: 'v'),
        throwsA(isA<OAuthException>()),
      );
    });

    test('malMe returns the display name', () async {
      final OAuthService svc = OAuthService(
        client: MockClient((http.Request req) async {
          expect(
            req.url.toString(),
            'https://api.myanimelist.net/v2/users/@me',
          );
          expect(req.headers['Authorization'], 'Bearer at-1');
          return http.Response(
            jsonEncode(<String, dynamic>{'name': 'SureshKC'}),
            200,
          );
        }),
      );
      expect(await svc.malMe('at-1'), 'SureshKC');
    });
  });

  group('MalTokens.fromJson', () {
    test('parses + isValid requires both tokens', () {
      final MalTokens t = MalTokens.fromJson(<String, dynamic>{
        'access_token': 'a',
        'refresh_token': 'r',
        'expires_in': 3600,
      });
      expect(t.isValid, isTrue);
      expect(
        MalTokens.fromJson(<String, dynamic>{
          'access_token': 'a',
          'refresh_token': '',
          'expires_in': 3600,
        }).isValid,
        isFalse,
      );
    });
  });

  group('0.2.8 Zeus-mirror localhost redirect', () {
    test('isLocalRedirect matches http://localhost only', () {
      expect(
        OAuthService.isLocalRedirect(Uri.parse('http://localhost/')),
        isTrue,
      );
      expect(
        OAuthService.isLocalRedirect(Uri.parse('http://localhost')),
        isTrue,
      );
      expect(
        OAuthService.isLocalRedirect(
          Uri.parse('http://localhost/?code=abc&state=s'),
        ),
        isTrue,
      );
      expect(
        OAuthService.isLocalRedirect(
          Uri.parse('http://localhost:8080/?code=abc'),
        ),
        isFalse,
      );
      expect(
        OAuthService.isLocalRedirect(
          Uri.parse('https://localhost/?code=abc'),
        ),
        isFalse,
      );
      expect(
        OAuthService.isLocalRedirect(
          Uri.parse('https://anilist.co/api/v2/oauth/pin'),
        ),
        isFalse,
      );
    });

    test('parseAnilistRedirect takes the token from the localhost fragment', () {
      expect(
        OAuthService.parseAnilistRedirect(
          Uri.parse('http://localhost/#access_token=tok-123'),
        ),
        'tok-123',
      );
      // Query-form fallback (some webviews convert # to ?).
      expect(
        OAuthService.parseAnilistRedirect(
          Uri.parse('http://localhost/?access_token=tok-456'),
        ),
        'tok-456',
      );
      // Empty localhost hit carries no token.
      expect(
        OAuthService.parseAnilistRedirect(Uri.parse('http://localhost/')),
        isNull,
      );
    });

    test('parseMalRedirect accepts localhost and the legacy scheme', () {
      expect(
        OAuthService.parseMalRedirect(
          Uri.parse('http://localhost/?code=code-9&state=state-xyz'),
          'state-xyz',
        ),
        'code-9',
      );
      // Legacy anibee:// shape still parses (fallback for a client
      // whose registered redirect still matches it).
      expect(
        OAuthService.parseMalRedirect(
          Uri.parse('anibee://mal-auth?code=code-1&state=state-xyz'),
          'state-xyz',
        ),
        'code-1',
      );
      // Wrong state is still rejected on the localhost shape.
      expect(
        OAuthService.parseMalRedirect(
          Uri.parse('http://localhost/?code=code-9&state=attacker'),
          'state-xyz',
        ),
        isNull,
      );
    });

    test('extractMalCodeFromText pulls code + state from a pasted URL', () {
      final ({String? code, String? state}) fromUrl =
          OAuthService.extractMalCodeFromText(
            'http://localhost/?code=code-7&state=state-abc',
          );
      expect(fromUrl.code, 'code-7');
      expect(fromUrl.state, 'state-abc');
      // Bare code: no state attached (the sheet supplies its own).
      final ({String? code, String? state}) bare =
          OAuthService.extractMalCodeFromText('code-plain-12345');
      expect(bare.code, 'code-plain-12345');
      expect(bare.state, isNull);
      // Junk carries no code.
      expect(
        OAuthService.extractMalCodeFromText('hello world'),
        (code: null, state: null),
      );
      expect(OAuthService.extractMalCodeFromText(null), (code: null, state: null));
    });
  });
}
