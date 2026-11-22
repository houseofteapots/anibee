import 'package:flutter/material.dart';

import '../settings_store.dart';
import '../theme.dart';
import '../widgets/settings_row.dart';
import 'downloads_screen.dart';
import 'lock_screen.dart';
import 'player_settings_screen.dart';
import 'sources_screen.dart';

/// Settings — the full list, matching the approved mockup:
/// Accounts, Appearance, Player, Servers, Downloads, Debrid, App Lock.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});

  final SettingsStore store;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryText =
        isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;

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
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            SettingsSection(
              title: 'ACCOUNTS',
              children: <Widget>[
                _AccountTile(
                  name: 'AniList',
                  color: const Color(0xFF2F7CF6),
                  label: 'A',
                  status: 'Not synced • Tap to link account',
                  onLogin: () => _showComingSoon(context, 'AniList login'),
                ),
                const SettingsDivider(),
                _AccountTile(
                  name: 'MyAnimeList',
                  color: const Color(0xFFEC5A9E),
                  label: 'MAL',
                  status: 'Not synced • Tap to link account',
                  onLogin: () =>
                      _showComingSoon(context, 'MyAnimeList login'),
                ),
              ],
            ),
            SettingsSection(
              title: 'APPEARANCE',
              children: <Widget>[
                SettingsTile(
                  title: 'Theme',
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
                      fontSize: 15,
                    ),
                  ),
                  showChevron: true,
                  onTap: () => _pickTheme(context),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Accent color',
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
                                    ? Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      )
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
              ],
            ),
            SettingsSection(
              title: 'PLAYER',
              children: <Widget>[
                SettingsTile(
                  title: 'Player settings',
                  showChevron: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          PlayerSettingsScreen(store: store),
                    ),
                  ),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Subtitles',
                  showChevron: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          PlayerSettingsScreen(store: store),
                    ),
                  ),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Skip Intro',
                  trailing: Switch(
                    value: store.skipIntro,
                    onChanged: store.setSkipIntro,
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'SERVERS',
              children: <Widget>[
                SettingsTile(
                  title: 'Preferred server',
                  trailing: Text(
                    store.preferredServer,
                    style: TextStyle(
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondaryLight,
                      fontSize: 15,
                    ),
                  ),
                  showChevron: true,
                  onTap: () => _pickServer(context),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Fallback providers',
                  trailing: Switch(
                    value: store.fallbackProviders,
                    onChanged: store.setFallbackProviders,
                  ),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Sources',
                  showChevron: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
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
                  showChevron: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) =>
                          DownloadsScreen(store: store),
                    ),
                  ),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Download quality',
                  trailing: Text(
                    store.downloadQuality,
                    style: TextStyle(
                      color: isDark
                          ? AppTheme.textSecondaryDark
                          : AppTheme.textSecondaryLight,
                      fontSize: 15,
                    ),
                  ),
                  showChevron: true,
                  onTap: () => _pickQuality(context),
                ),
                const SettingsDivider(),
                SettingsTile(
                  title: 'Wi-Fi only',
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
                  apiKey: store.torboxApiKey,
                  onTap: () => _editDebridKey(
                    context,
                    name: 'TorBox',
                    currentKey: store.torboxApiKey,
                    onSave: store.setTorboxApiKey,
                  ),
                ),
                const SettingsDivider(),
                _DebridTile(
                  name: 'Real-Debrid',
                  apiKey: store.realDebridApiKey,
                  onTap: () => _editDebridKey(
                    context,
                    name: 'Real-Debrid',
                    currentKey: store.realDebridApiKey,
                    onSave: store.setRealDebridApiKey,
                  ),
                ),
              ],
            ),
            SettingsSection(
              title: 'APP LOCK',
              children: <Widget>[
                SettingsTile(
                  title: 'App Lock',
                  trailing: Switch(
                    value: store.appLockEnabled,
                    onChanged: (bool value) =>
                        _toggleAppLock(context, value),
                  ),
                ),
                if (store.appLockEnabled) ...<Widget>[
                  const SettingsDivider(),
                  SettingsTile(
                    title: 'Face ID',
                    trailing: Switch(
                      value: store.faceIdEnabled,
                      onChanged: store.setFaceIdEnabled,
                    ),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    title: 'Change passcode',
                    showChevron: true,
                    onTap: () => _changePasscode(context),
                  ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 0),
              child: Center(
                child: Text(
                  'AniBee 0.1.0 (M1) • Personal build',
                  style: TextStyle(
                    color: isDark
                        ? AppTheme.textSecondaryDark
                        : AppTheme.textSecondaryLight,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature arrives in milestone 2.')),
    );
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
    final TextEditingController controller =
        TextEditingController(text: currentKey ?? '');
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('$name API key'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'Paste your API key',
          ),
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
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => LockScreen(
          mode: LockMode.setup,
          store: store,
        ),
      ),
    );
    if (set == true) {
      await store.setAppLockEnabled(true);
    }
  }

  Future<void> _changePasscode(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => LockScreen(
          mode: LockMode.setup,
          store: store,
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.name,
    required this.color,
    required this.label,
    required this.status,
    required this.onLogin,
  });

  final String name;
  final Color color;
  final String label;
  final String status;
  final VoidCallback onLogin;

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
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(
                    color: isDark
                        ? AppTheme.textSecondaryDark
                        : AppTheme.textSecondaryLight,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }
}

class _DebridTile extends StatelessWidget {
  const _DebridTile({
    required this.name,
    required this.apiKey,
    required this.onTap,
  });

  final String name;
  final String? apiKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool connected = apiKey != null && apiKey!.isNotEmpty;
    return SettingsTile(
      title: name,
      subtitle: connected
          ? 'Connected • key saved'
          : 'Not connected • Tap to add API key',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: connected
              ? AppTheme.success.withValues(alpha: 0.15)
              : (isDark
                  ? const Color(0xFF2A2A38)
                  : const Color(0xFFE8E8EF)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          connected ? 'Connected' : 'Add key',
          style: TextStyle(
            color: connected
                ? AppTheme.success
                : (isDark
                    ? AppTheme.textSecondaryDark
                    : AppTheme.textSecondaryLight),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}
