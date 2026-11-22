import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for secrets (API keys, OAuth tokens, client IDs).
/// M2: keys/tokens used to live in SharedPreferences plaintext — they
/// are migrated here on first load (see SettingsStore.load).
class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String torboxApiKey = 'torbox_api_key';
  static const String realDebridApiKey = 'realdebrid_api_key';
  static const String anilistClientId = 'anilist_client_id';
  static const String anilistAccessToken = 'anilist_access_token';
  static const String malClientId = 'mal_client_id';
  static const String malAccessToken = 'mal_access_token';
  static const String malRefreshToken = 'mal_refresh_token';
  static const String malTokenExpiry = 'mal_token_expiry';

  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Best-effort: a stale secret is removed on next migration pass.
    }
  }
}
