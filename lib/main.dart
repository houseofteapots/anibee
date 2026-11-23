import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app_shell.dart';
import 'screens/lock_screen.dart';
import 'services/app_services.dart';
import 'services/provider_config.dart';
import 'settings_store.dart';
import 'theme.dart';
import 'widgets/splash_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final SettingsStore store = await SettingsStore.load();
  // Remote provider config: fetched on launch, bundled fallback when
  // offline (see lib/services/provider_config.dart).
  final ProviderConfigService configService =
      await ProviderConfigService.load();
  // M2 real services: AniList, Miruro resolver, Debrid, OAuth.
  // The config service is passed in so MAL token refresh can use the
  // config's client ID (0.2.3: client IDs live in the remote config,
  // never typed in by the user).
  final AppServices services = AppServices.create(configService: configService);
  // 0.2.10: local airing alerts — init once, never prompts here
  // (permission is asked once at first use from the Home airing
  // section). A failed init must never block launch.
  try {
    await services.airingNotifications.init();
  } catch (_) {
    // Notifications are best-effort.
  }
  // 0.2.5: drop download rows the M1 simulation left behind (they
  // claim 'downloaded' but no file was ever saved — tapping them
  // did nothing). Real records + files are untouched.
  await services.downloads.pruneStale(store);
  runApp(
    AniBeeApp(store: store, configService: configService, services: services),
  );
}

class AniBeeApp extends StatelessWidget {
  const AniBeeApp({
    super.key,
    required this.store,
    required this.configService,
    required this.services,
  });

  final SettingsStore store;
  final ProviderConfigService configService;
  final AppServices services;

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
          home: _RootGate(
            store: store,
            configService: configService,
            services: services,
          ),
        );
      },
    );
  }
}

/// Shows the app lock on launch when enabled + a PIN is set.
class _RootGate extends StatefulWidget {
  const _RootGate({
    required this.store,
    required this.configService,
    required this.services,
  });

  final SettingsStore store;
  final ProviderConfigService configService;
  final AppServices services;

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  bool _unlocked = false;

  /// Zeus-style splash (0.2.8): the native launch screen shows the
  /// logo instantly on tap; this Flutter-side hold keeps it up for
  /// ~1s so the splash actually reads, then fades to Home (or the
  /// lock screen). Total feel: ~1-2s, like Zeus.
  bool _showSplash = true;
  double _splashOpacity = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer(const Duration(milliseconds: 1000), () {
        if (!mounted) return;
        setState(() => _splashOpacity = 0);
        Timer(const Duration(milliseconds: 400), () {
          if (mounted) setState(() => _showSplash = false);
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool locked =
        widget.store.appLockEnabled && widget.store.hasPin && !_unlocked;
    final Widget content = locked
        ? LockScreen(
            mode: LockMode.unlock,
            store: widget.store,
            onUnlocked: () => setState(() => _unlocked = true),
          )
        : AppShell(
            store: widget.store,
            configService: widget.configService,
            services: widget.services,
          );
    if (!_showSplash) return content;
    return Stack(
      children: <Widget>[
        content,
        SplashView(opacity: _splashOpacity),
      ],
    );
  }
}
