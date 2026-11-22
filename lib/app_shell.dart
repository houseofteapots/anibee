import 'package:flutter/material.dart';

import 'models.dart';
import 'services/provider_config.dart';
import 'settings_store.dart';
import 'screens/collection_screen.dart';
import 'screens/detail_screen.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/glass_nav.dart';
import 'widgets/page_route.dart';

/// Root tab shell: 4 tabs under the liquid-glass nav pill.
/// The pill is Positioned directly on the Stack (never wrapped in
/// Transform/Padding — Zeus b90 lesson).
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store, required this.configService});

  final SettingsStore store;
  final ProviderConfigService configService;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  void _openAnime(Anime anime, {bool autoPlay = false}) {
    Navigator.of(context).push(
      SmoothPageRoute<void>(
        builder: (BuildContext context) => DetailScreen(
          anime: anime,
          store: widget.store,
          autoPlay: autoPlay,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          IndexedStack(
            index: _tab,
            children: <Widget>[
              HomeScreen(
                store: widget.store,
                onOpenAnime: _openAnime,
                onOpenSearch: () => setState(() => _tab = 1),
                onWatchNow: (Anime anime) =>
                    _openAnime(anime, autoPlay: true),
              ),
              SearchScreen(onOpenAnime: _openAnime),
              CollectionScreen(
                store: widget.store,
                onOpenAnime: _openAnime,
                onBrowse: () => setState(() => _tab = 1),
              ),
              SettingsScreen(
                store: widget.store,
                configService: widget.configService,
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            // ListenableBuilder so the pill restyles the moment the
            // Navigation Style is tapped in Settings.
            child: ListenableBuilder(
              listenable: widget.store,
              builder: (BuildContext context, Widget? _) => GlassNavBar(
                currentIndex: _tab,
                onTap: (int i) => setState(() => _tab = i),
                accent: accent,
                isDark: isDark,
                navStyle: widget.store.navStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
