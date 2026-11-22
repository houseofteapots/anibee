import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app_shell.dart';
import 'screens/lock_screen.dart';
import 'services/provider_config.dart';
import 'settings_store.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final SettingsStore store = await SettingsStore.load();
  // Remote provider config: fetched on launch, bundled fallback when
  // offline (see lib/services/provider_config.dart).
  final ProviderConfigService configService =
      await ProviderConfigService.load();
  runApp(AniBeeApp(store: store, configService: configService));
}

class AniBeeApp extends StatelessWidget {
  const AniBeeApp({super.key, required this.store, required this.configService});

  final SettingsStore store;
  final ProviderConfigService configService;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (BuildContext context, Widget? _) {
        final Color accent = kAccentOptions[store.accentIndex].color;
        return MaterialApp(
          title: 'AniBee',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(accent),
          darkTheme: AppTheme.dark(accent),
          themeMode: store.themeMode,
          home: _RootGate(store: store, configService: configService),
        );
      },
    );
  }
}

/// Shows the app lock on launch when enabled + a PIN is set.
class _RootGate extends StatefulWidget {
  const _RootGate({required this.store, required this.configService});

  final SettingsStore store;
  final ProviderConfigService configService;

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool _unlocked = false;

  @override
  Widget build(BuildContext context) {
    final bool locked =
        widget.store.appLockEnabled && widget.store.hasPin && !_unlocked;
    if (locked) {
      return LockScreen(
        mode: LockMode.unlock,
        store: widget.store,
        onUnlocked: () => setState(() => _unlocked = true),
      );
    }
    return AppShell(store: widget.store, configService: widget.configService);
  }
}
