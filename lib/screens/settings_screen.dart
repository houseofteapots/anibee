import 'package:flutter/material.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

import '../services/app_services.dart';
import '../services/oauth_service.dart';
import '../services/provider_config.dart';
import '../settings_store.dart';
import '../theme.dart';
import '../widgets/oauth_webview.dart';
import '../widgets/page_route.dart';
import '../widgets/reicon_icon.dart';
import '../widgets/settings_row.dart';
import 'downloads_screen.dart';
import 'lock_screen.dart';
import 'player_settings_screen.dart';
import 'sources_screen.dart';

/// Settings — the full list, matching the approved mockup:
/// Accounts, Appearance, Player, Servers, Downloads, Debrid, App Lock.
/// Every row carries a matching Reicon icon (reicon.dev, MIT).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    required this.configService,
    required this.services,
    this.onPlayDownload,
  });

  final SettingsStore store;
  final ProviderConfigService configService;
  final AppServices services;

  /// Tapping a downloaded row plays the local file (wired from
  /// AppShell, which owns the player navigation).
  final ValueChanged<String>? onPlayDownload;

  /// Row icons: white in dark mode, accent in light mode — full
  /// contrast on the tinted tile (the M1.1 icons rendered dark-on-dark
  /// because the Reicon colour never reached the stroke; see
  /// ReiconIcon's colorFilter fix).
  Widget _icon(String pathData, BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return ReiconIcon(
      pathData,
      size: 18,
      color: isDark ? Colors.white : Theme.of(context).colorScheme.primary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryText = isDark
        ? AppTheme.textPrimaryDark
        : AppTheme.textPrimaryLight;

    return ListenableBuilder(
      listenable: store,
      builder: (BuildContext context, Widget? _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: 110),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
              child: Text(
                'Settings',
                style: TextStyle(
                  color: primaryText,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            // 0.2.4: rebuilds when the provider config refreshes, so
            // the "Login setup in progress" status flips to
            // "Not connected • Tap to log in" the moment the OAuth
            // client IDs land in anibee-config — no restart needed.
            ListenableBuilder(
              listenable: configService,
              builder: (BuildContext context, Widget? _) {
                return SettingsSection(
                  title: 'ACCOUNTS',
                  children: <Widget>[
                    _AccountTile(
                      name: 'AniList',
                      color: const Color(0xFF2F7CF6),
                      icon: Reicon.outline.userCircle,
                      status: store.anilistConnected
                          ? 'Connected as ${store.anilistUsername ?? 'AniList user'}'
                          : configService.config.anilistClientId.isEmpty
                          ? 'Login setup in progress'
                          : 'Not connected • Tap to log in',
                      buttonLabel: store.anilistConnected ? 'Logout' : 'Login',
                      onButton: () => store.anilistConnected
                          ? _logoutAccount(context, 'AniList')
                          : _loginAnilist(context),
                    ),
                    const SettingsDivider(),
                    _AccountTile(
                      name: 'MyAnimeList',
                      color: const Color(0xFFEC5A9E),
                      icon: Reicon.outline.star,
                      status: store.malConnected
                          ? 'Connected as ${store.malUsername ?? 'MAL user'}'
                          : configService.config.malClientId.isEmpty
                          ? 'Login setup in progress'
                          : 'Not connected • Tap to log in',
                      buttonLabel: store.malConnected ? 'Logout' : 'Login',
                      onButton: () => store.malConnected
                          ? _logoutAccount(context, 'MyAnimeList')
                          : _loginMal(context),
                    ),
                  ],
                );
              },
            ),
            SettingsSection(
              title: 'APPEARANCE',
              children: <Widget>[
                SettingsTile(
                  title: 'Theme',
                  leading: _icon(Reicon.outline.moon, context),
                  trailing: Text(
                    switch (store.themeMode) {
                      ThemeMode.dark => 'Dark',
                      ThemeMode.light => 'Light',
                      ThemeMode.system => 'System',
                    },
                    style: TextStyle(
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondaryLight,
                      fontSize: 14,
                    ),
                  ),
                  showChevron: true,
                  onTap: () => _pickTheme(context),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Accent color',
                  leading: _icon(Reicon.outline.palette, context),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (int i = 0; i < kAccentOptions.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: InkWell(
                            onTap: () => store.setAccentIndex(i),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: kAccentOptions[i].color,
                                shape: BoxShape.circle,
                                border: i == store.accentIndex
                                    ? Border.all(color: Colors.white, width: 2)
                                    : null,
                              ),
                              child: i == store.accentIndex
                                  ? const Icon(
                                      Icons.check_rounded,
                                      size: 14,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Navigation Style',
                  leading: _icon(Reicon.outline.layout, context),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _NavStylePill(
                        label: 'Liquid Glass',
                        selected: store.navStyle == 'glass',
                        onTap: () => store.setNavStyle('glass'),
                      ),
                      const SizedBox(width: 6),
                      _NavStylePill(
                        label: 'Blurry',
                        selected: store.navStyle == 'blurry',
                        onTap: () => store.setNavStyle('blurry'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'PLAYER',
              children: <Widget>[
                SettingsTile(
                  title: 'Player settings',
                  leading: _icon(Reicon.outline.play, context),
                  showChevron: true,
                  onTap: () => Navigator.of(context).push(
                    SmoothPageRoute<void>(
                      builder: (BuildContext context) =>
                          PlayerSettingsScreen(store: store),
                    ),
                  ),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Subtitles',
                  leading: _icon(Reicon.outline.subtitle, context),
                  showChevron: true,
                  onTap: () => Navigator.of(context).push(
                    SmoothPageRoute<void>(
                      builder: (BuildContext context) =>
                          PlayerSettingsScreen(store: store),
                    ),
                  ),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Skip Intro',
                  leading: _icon(Reicon.outline.fastForward, context),
                  trailing: Switch(
                    value: store.skipIntro,
                    onChanged: store.setSkipIntro,
                  ),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Autoplay next episode',
                  subtitle: 'Plays the next episode when one ends',
                  leading: _icon(Reicon.outline.arrowRight, context),
                  trailing: Switch(
                    value: store.autoplayNext,
                    onChanged: store.setAutoplayNext,
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'SERVERS',
              children: <Widget>[
                SettingsTile(
                  title: 'Preferred server',
                  leading: _icon(Reicon.outline.server, context),
                  trailing: Text(
                    store.preferredServer,
                    style: TextStyle(
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondaryLight,
                      fontSize: 14,
                    ),
                  ),
                  showChevron: true,
                  onTap: () => _pickServer(context),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Fallback providers',
                  leading: _icon(Reicon.outline.refresh, context),
                  trailing: Switch(
                    value: store.fallbackProviders,
                    onChanged: store.setFallbackProviders,
                  ),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Sources',
                  leading: _icon(Reicon.outline.globe, context),
                  showChevron: true,
                  onTap: () => Navigator.of(context).push(
                    SmoothPageRoute<void>(
                      builder: (BuildContext context) =>
                          SourcesScreen(store: store),
                    ),
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'DOWNLOADS',
              children: <Widget>[
                SettingsTile(
                  title: 'Downloads',
                  leading: _icon(Reicon.outline.download, context),
                  showChevron: true,
                  onTap: () => Navigator.of(context).push(
                    SmoothPageRoute<void>(
                      builder: (BuildContext context) => DownloadsScreen(
                        store: store,
                        services: services,
                        onPlayDownload: onPlayDownload,
                      ),
                    ),
                  ),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Download quality',
                  leading: _icon(Reicon.outline.film, context),
                  trailing: Text(
                    store.downloadQuality,
                    style: TextStyle(
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondaryLight,
                      fontSize: 14,
                    ),
                  ),
                  showChevron: true,
                  onTap: () => _pickQuality(context),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Wi-Fi only',
                  leading: _icon(Reicon.outline.wifi, context),
                  trailing: Switch(
                    value: store.wifiOnly,
                    onChanged: store.setWifiOnly,
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'DEBRID',
              children: <Widget>[
                _DebridTile(
                  name: 'TorBox',
                  icon: Reicon.outline.key,
                  apiKey: store.torboxApiKey,
                  verified: store.torboxVerified,
                  account: store.torboxAccount,
                  onTap: () => _editDebridKey(
                    context,
                    name: 'TorBox',
                    currentKey: store.torboxApiKey,
                    onSave: (String? key) async {
                      await store.setTorboxApiKey(key);
                      if (!context.mounted) return;
                      await _verifyDebrid(context, 'TorBox', key);
                    },
                  ),
                ),
                const SettingsDivider(),
                _DebridTile(
                  name: 'Real-Debrid',
                  icon: Reicon.outline.key,
                  apiKey: store.realDebridApiKey,
                  verified: store.realDebridVerified,
                  account: store.realDebridAccount,
                  onTap: () => _editDebridKey(
                    context,
                    name: 'Real-Debrid',
                    currentKey: store.realDebridApiKey,
                    onSave: (String? key) async {
                      await store.setRealDebridApiKey(key);
                      if (!context.mounted) return;
                      await _verifyDebrid(context, 'Real-Debrid', key);
                    },
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'APP LOCK',
              children: <Widget>[
                SettingsTile(
                  title: 'App Lock',
                  leading: _icon(Reicon.outline.lock, context),
                  trailing: Switch(
                    value: store.appLockEnabled,
                    onChanged: (bool value) => _toggleAppLock(context, value),
                  ),
                ),
                if (store.appLockEnabled) ...<Widget>[
                  const SettingsDivider(),
                  SettingsTile(
                    title: 'Face ID',
                    leading: _icon(Reicon.outline.shieldCheck, context),
                    trailing: Switch(
                      value: store.faceIdEnabled,
                      onChanged: store.setFaceIdEnabled,
                    ),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    title: 'Change passcode',
                    leading: _icon(Reicon.outline.fingerprint, context),
                    showChevron: true,
                    onTap: () => _changePasscode(context),
                  ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ReiconIcon(
                      Reicon.outline.infoCircle,
                      size: 14,
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondaryLight,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'AniBee 0.2.1 (M2) • Personal build',
                      style: TextStyle(
                        color: isDark
                            ? AppTheme.textSecondaryDark
                            : AppTheme.textSecondaryLight,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Center(
                child: ListenableBuilder(
                  listenable: configService,
                  builder: (BuildContext context, Widget? _) {
                    return Text(
                      'Provider config v${configService.version} '
                      '• ${configService.source.name}',
                      style: TextStyle(
                        color: isDark
                            ? AppTheme.textSecondaryDark
                            : AppTheme.textSecondaryLight,
                        fontSize: 11,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------- accounts

  /// AniList login (0.2.3): one tap opens the bottom-sheet webview
  /// with AniList's own authorize page — no client ID dialog anywhere.
  /// The client ID comes from the remote provider config (set by the
  /// app developer); until it is configured, the button shows a
  /// "setup in progress" state instead of asking the user for it.
  /// Implicit grant — the token comes back in the redirect fragment.
  Future<void> _loginAnilist(BuildContext context) async {
    // 0.2.4: pick up client IDs the moment they land in the remote
    // config — no rebuild, no restart. A failed refresh keeps the
    // last-good config, so login still works with what we have.
    try {
      await configService.refresh();
    } catch (_) {}
    if (!context.mounted) return;
    final String clientId = configService.config.anilistClientId;
    if (clientId.isEmpty) {
      _snack(context, 'AniList login is being set up — please try again soon.');
      return;
    }
    if (!context.mounted) return;
    final Uri? redirect = await showOAuthLogin(
      context: context,
      title: 'Log in to AniList',
      authUrl: OAuthService.anilistAuthUrl(clientId),
      redirectScheme: 'anibee',
      domain: 'anilist.co',
      subtitle: 'Sign in to AniList to sync what you watch.',
    );
    if (redirect == null) return;
    final String? token = OAuthService.parseAnilistRedirect(redirect);
    if (token == null) {
      if (!context.mounted) return;
      // The provider may have redirected with an error instead of a
      // token (fragment: #error=unsupported_grant_type&...): show the
      // readable reason, not the generic "no token" line.
      final String? error = Uri.splitQueryString(
        redirect.fragment,
      )['error'];
      if (error != null && error.isNotEmpty) {
        _snack(
          context,
          OAuthService.readableOAuthError(
            provider: 'AniList',
            error: error,
          ),
        );
      } else if (OAuthService.isAnilistPinUrl(redirect)) {
        // 0.2.6: Authorize was tapped and AniList reached the PIN
        // page but no token arrived — name the step so the user
        // knows it got that far instead of a generic failure.
        _snack(
          context,
          'AniList login complete hua lekin token nahi mila — dobara try karo.',
        );
      } else {
        _snack(context, 'AniList login failed — no token returned.');
      }
      return;
    }
    try {
      final ({int id, String name}) viewer = await services.anilist.viewer(
        token,
      );
      await store.setAnilistSession(token, viewer.name);
      if (!context.mounted) return;
      _snack(context, 'Connected to AniList as ${viewer.name}.');
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, 'AniList login failed: $e');
    }
  }

  /// MAL login (0.2.3): one tap opens the bottom-sheet webview with
  /// MAL's own authorize page. Client ID from the remote provider
  /// config; "setup in progress" until it is configured. Authorization
  /// Code + PKCE plain.
  Future<void> _loginMal(BuildContext context) async {
    // 0.2.4: same remote-config refresh as AniList (see above).
    try {
      await configService.refresh();
    } catch (_) {}
    if (!context.mounted) return;
    final String clientId = configService.config.malClientId;
    if (clientId.isEmpty) {
      _snack(
        context,
        'MyAnimeList login is being set up — please try again soon.',
      );
      return;
    }
    if (!context.mounted) return;
    final String verifier = OAuthService.generateVerifier();
    final String state = OAuthService.generateVerifier().substring(0, 16);
    final Uri? redirect = await showOAuthLogin(
      context: context,
      title: 'Log in to MyAnimeList',
      authUrl: OAuthService.malAuthUrl(
        clientId: clientId,
        verifier: verifier,
        state: state,
      ),
      redirectScheme: 'anibee',
      domain: 'myanimelist.net',
      subtitle: 'Sign in to MyAnimeList to sync what you watch.',
    );
    if (redirect == null) return;
    final String? code = OAuthService.parseMalRedirect(redirect, state);
    if (code == null) {
      if (!context.mounted) return;
      final String? error = redirect.queryParameters['error'];
      if (error != null && error.isNotEmpty) {
        _snack(
          context,
          OAuthService.readableOAuthError(
            provider: 'MyAnimeList',
            error: error,
          ),
        );
      } else {
        _snack(context, 'MyAnimeList login failed — no code returned.');
      }
      return;
    }
    try {
      final MalTokens tokens = await services.oauth.exchangeMalCode(
        clientId: clientId,
        code: code,
        verifier: verifier,
      );
      if (!tokens.isValid) {
        if (!context.mounted) return;
        _snack(context, 'MyAnimeList login failed — bad token response.');
        return;
      }
      final String name = await services.oauth.malMe(tokens.accessToken);
      await store.setMalSession(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        expiry: DateTime.now().add(Duration(seconds: tokens.expiresInSeconds)),
        username: name,
      );
      if (!context.mounted) return;
      _snack(context, 'Connected to MyAnimeList as $name.');
    } catch (e) {
      if (!context.mounted) return;
      _snack(context, 'MyAnimeList login failed: $e');
    }
  }

  Future<void> _logoutAccount(BuildContext context, String name) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Log out of $name?'),
        content: const Text('Your local lists stay on this device.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (name == 'AniList') {
      await store.setAnilistSession(null, null);
    } else {
      await store.setMalSession();
    }
    if (!context.mounted) return;
    _snack(context, 'Logged out of $name.');
  }

  // ------------------------------------------------------------ debrid

  /// Verify a saved Debrid key with a real API call and store the
  /// verified state — "Connected" means the key actually works.
  Future<void> _verifyDebrid(
    BuildContext context,
    String name,
    String? key,
  ) async {
    if (key == null || key.isEmpty) return;
    _snack(context, 'Verifying $name…');
    final String? account = name == 'TorBox'
        ? await services.debrid.verifyTorbox(key)
        : await services.debrid.verifyRealDebrid(key);
    if (!context.mounted) return;
    if (account != null) {
      if (name == 'TorBox') {
        await store.setTorboxVerified(true, account);
      } else {
        await store.setRealDebridVerified(true, account);
      }
      if (!context.mounted) return;
      _snack(context, '$name connected as $account.');
    } else {
      if (name == 'TorBox') {
        await store.setTorboxVerified(false, null);
      } else {
        await store.setRealDebridVerified(false, null);
      }
      if (!context.mounted) return;
      _snack(
        context,
        '$name key did not verify — check the key and try again.',
      );
    }
  }

  Future<void> _pickTheme(BuildContext context) async {
    final ThemeMode? picked = await showDialog<ThemeMode>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('Theme'),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(ThemeMode.dark),
            child: const Text('Dark'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(ThemeMode.light),
            child: const Text('Light'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(ThemeMode.system),
            child: const Text('System'),
          ),
        ],
      ),
    );
    if (picked != null) await store.setThemeMode(picked);
  }

  Future<void> _pickServer(BuildContext context) async {
    final String? picked = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('Preferred server'),
        children: <Widget>[
          for (final s in store.sources.where((s) => s.enabled))
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(s.name),
              child: Text(s.name),
            ),
        ],
      ),
    );
    if (picked != null) await store.setPreferredServer(picked);
  }

  Future<void> _pickQuality(BuildContext context) async {
    final String? picked = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('Download quality'),
        children: <Widget>[
          for (final String q in <String>['480p', '720p', '1080p'])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(q),
              child: Text(q),
            ),
        ],
      ),
    );
    if (picked != null) await store.setDownloadQuality(picked);
  }

  Future<void> _editDebridKey(
    BuildContext context, {
    required String name,
    required String? currentKey,
    required Future<void> Function(String?) onSave,
  }) async {
    final TextEditingController controller = TextEditingController(
      text: currentKey ?? '',
    );
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('$name API key'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Paste your API key'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null) {
      await onSave(result.isEmpty ? null : result.trim());
    }
  }

  Future<void> _toggleAppLock(BuildContext context, bool enable) async {
    if (!enable) {
      await store.setAppLockEnabled(false);
      return;
    }
    if (store.hasPin) {
      await store.setAppLockEnabled(true);
      return;
    }
    final bool? set = await Navigator.of(context).push<bool>(
      SmoothPageRoute<bool>(
        builder: (BuildContext context) =>
            LockScreen(mode: LockMode.setup, store: store),
      ),
    );
    if (set == true) {
      await store.setAppLockEnabled(true);
    }
  }

  Future<void> _changePasscode(BuildContext context) async {
    await Navigator.of(context).push(
      SmoothPageRoute<void>(
        builder: (BuildContext context) =>
            LockScreen(mode: LockMode.setup, store: store),
      ),
    );
  }
}

/// Small pill for the Navigation Style choice (Liquid Glass / Blurry).
class _NavStylePill extends StatelessWidget {
  const _NavStylePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? accent
              : (isDark ? const Color(0xFF2A2A38) : const Color(0xFFE8E8EF)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : (isDark
                      ? AppTheme.textSecondaryDark
                      : AppTheme.textSecondaryLight),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.name,
    required this.color,
    required this.icon,
    required this.status,
    required this.buttonLabel,
    required this.onButton,
  });

  final String name;
  final Color color;
  final String icon;
  final String status;
  final String buttonLabel;
  final VoidCallback onButton;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: ReiconIcon(icon, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  style: TextStyle(
                    color: isDark
                        ? AppTheme.textPrimaryDark
                        : AppTheme.textPrimaryLight,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(
                    color: isDark
                        ? AppTheme.textSecondaryDark
                        : AppTheme.textSecondaryLight,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onButton,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

class _DebridTile extends StatelessWidget {
  const _DebridTile({
    required this.name,
    required this.icon,
    required this.apiKey,
    required this.verified,
    required this.account,
    required this.onTap,
  });

  final String name;
  final String icon;
  final String? apiKey;

  /// True only when the key passed a real API verify call.
  final bool verified;
  final String? account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool hasKey = apiKey != null && apiKey!.isNotEmpty;
    return SettingsTile(
      title: name,
      leading: ReiconIcon(
        icon,
        size: 18,
        color: isDark ? Colors.white : Theme.of(context).colorScheme.primary,
      ),
      subtitle: verified
          ? 'Connected${account != null ? ' as $account' : ''}'
          : hasKey
          ? 'Key saved • not verified — tap to retry'
          : 'Not connected • Tap to add API key',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: verified
              ? AppTheme.success.withValues(alpha: 0.15)
              : (isDark ? const Color(0xFF2A2A38) : const Color(0xFFE8E8EF)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          verified ? 'Connected' : 'Add key',
          style: TextStyle(
            color: verified
                ? AppTheme.success
                : (isDark
                      ? AppTheme.textSecondaryDark
                      : AppTheme.textSecondaryLight),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}
