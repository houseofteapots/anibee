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
    test('auth URL is the implicit grant with the anibee redirect', () {
      final Uri url = Uri.parse(OAuthService.anilistAuthUrl('client-123'));
      expect(url.scheme, 'https');
      expect(url.host, 'anilist.co');
      expect(url.path, '/api/v2/oauth/authorize');
      expect(url.queryParameters['client_id'], 'client-123');
      expect(url.queryParameters['response_type'], 'token');
      expect(
        url.queryParameters['redirect_uri'],
        'anibee://anilist-auth',
      );
    });

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

    test('parseAnilistRedirect rejects wrong scheme / host / empty token',
        () {
      expect(
        OAuthService.parseAnilistRedirect(
          Uri.parse('https://anilist.co/api/v2/oauth/pin#access_token=x'),
        ),
        isNull,
      );
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
  });

  group('MAL OAuth (PKCE plain)', () {
    test('generateVerifier is 64 URL-safe chars', () {
      final String v = OAuthService.generateVerifier();
      expect(v.length, 64);
      expect(
        RegExp(r'^[A-Za-z0-9\-._~]{64}$').hasMatch(v),
        isTrue,
      );
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
      expect(url.queryParameters['redirect_uri'], 'anibee://mal-auth');
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
          expect(body['redirect_uri'], 'anibee://mal-auth');
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
        () => svc.exchangeMalCode(
          clientId: 'x',
          code: 'bad',
          verifier: 'v',
        ),
        throwsA(isA<OAuthException>()),
      );
    });

    test('malMe returns the display name', () async {
      final OAuthService svc = OAuthService(
        client: MockClient((http.Request req) async {
          expect(req.url.toString(), 'https://api.myanimelist.net/v2/users/@me');
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
}
