import 'package:anibee/services/oauth_service.dart';
import 'package:anibee/services/provider_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.3: OAuth client IDs come from the remote provider config
/// (sezkc16/anibee-config providers.json), never from a paste dialog.
/// The login sheet builds its authorize URL from the configured ID;
/// with no ID configured the app shows "setup in progress" instead
/// of asking the user. Redirect parsing is covered by oauth_test.dart.
void main() {
  group('ProviderConfig client IDs', () {
    test('parses anilistClientId and malClientId from JSON', () {
      final ProviderConfig config = ProviderConfig.fromJson(<String, dynamic>{
        'version': 2,
        'anilistClientId': '12345',
        'malClientId': 'abcdef',
      });
      expect(config.anilistClientId, '12345');
      expect(config.malClientId, 'abcdef');
    });

    test('defaults to empty when the fields are absent', () {
      final ProviderConfig config = ProviderConfig.fromJson(<String, dynamic>{
        'version': 1,
      });
      expect(config.anilistClientId, isEmpty);
      expect(config.malClientId, isEmpty);
      expect(ProviderConfig.empty().anilistClientId, isEmpty);
      expect(ProviderConfig.empty().malClientId, isEmpty);
    });
  });

  group('authorize URLs from a configured client ID', () {
    test('AniList URL carries the config client ID', () {
      const String testId = 'test-anilist-id-123';
      final Uri url = Uri.parse(OAuthService.anilistAuthUrl(testId));
      expect(url.host, 'anilist.co');
      expect(url.path, '/api/v2/oauth/authorize');
      expect(url.queryParameters['client_id'], testId);
      expect(url.queryParameters['response_type'], 'token');
      // 0.2.5 PIN flow: no redirect_uri is sent at all (sending one
      // made AniList reject the authorize request).
      expect(url.queryParameters.containsKey('redirect_uri'), isFalse);
    });

    test('MAL URL carries the config client ID + PKCE challenge', () {
      const String testId = 'test-mal-id-456';
      const String verifier =
          'plain-verifier-abcdefghijklmnopqrstuvwxyz0123456789';
      const String state = 'state-1234567890ab';
      final Uri url = Uri.parse(
        OAuthService.malAuthUrl(
          clientId: testId,
          verifier: verifier,
          state: state,
        ),
      );
      expect(url.host, 'myanimelist.net');
      expect(url.queryParameters['client_id'], testId);
      expect(url.queryParameters['code_challenge_method'], 'plain');
      expect(url.queryParameters['code_challenge'], verifier);
      expect(url.queryParameters['state'], state);
      expect(url.queryParameters['redirect_uri'], OAuthService.malRedirect);
    });
  });
}
