import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app_shell.dart';
import 'screens/lock_screen.dart';
import 'settings_store.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final SettingsStore store = await SettingsStore.load();
  runApp(AniBeeApp(store: store));
}

class AniBeeApp extends StatelessWidget {
  const AniBeeApp({super.key, required this.store});

  final SettingsStore store;

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
          home: _RootGate(store: store),
        );
      },
    );
  }
}

/// Shows the app lock on launch when enabled + a PIN is set.
class _RootGate extends StatefulWidget {
  const _RootGate({required this.store});

  final SettingsStore store;

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
    return AppShell(store: widget.store);
  }
}
