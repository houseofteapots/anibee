import 'package:flutter/material.dart';

import 'models.dart';
import 'services/app_services.dart';
import 'services/provider_config.dart';
import 'settings_store.dart';
import 'screens/collection_screen.dart';
import 'screens/detail_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/glass_nav.dart';
import 'widgets/page_route.dart';

/// Root tab shell: 4 tabs under the liquid-glass nav pill.
/// The pill is Positioned directly on the Stack (never wrapped in
/// Transform/Padding — Zeus b90 lesson).
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.store,
    required this.configService,
    required this.services,
  });

  final SettingsStore store;
  final ProviderConfigService configService;
  final AppServices services;

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
          services: widget.services,
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
              _TabFade(
                active: _tab == 0,
                child: HomeScreen(
                  store: widget.store,
                  onOpenAnime: _openAnime,
                  onOpenSearch: () => setState(() => _tab = 1),
                  onWatchNow: (Anime anime) =>
                      _openAnime(anime, autoPlay: true),
                ),
              ),
              _TabFade(
                active: _tab == 1,
                child: SearchScreen(
                  onOpenAnime: _openAnime,
                  anilist: widget.services.anilist,
                ),
              ),
              _TabFade(
                active: _tab == 2,
                child: CollectionScreen(
                  store: widget.store,
                  onOpenAnime: _openAnime,
                  onBrowse: () => setState(() => _tab = 1),
                ),
              ),
              _TabFade(
                active: _tab == 3,
                child: DownloadsScreen(store: widget.store, embedded: true),
              ),
              _TabFade(
                active: _tab == 4,
                child: SettingsScreen(
                  store: widget.store,
                  configService: widget.configService,
                  services: widget.services,
                ),
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

/// Fade + slight rise when a tab becomes active: tab switches feel
/// smooth instead of snapping (IndexedStack alone swaps instantly).
/// State is preserved — IndexedStack keeps every tab alive; this only
/// animates the incoming tab's opacity on activation.
class _TabFade extends StatefulWidget {
  const _TabFade({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.015),
    end: Offset.zero,
  ).animate(_fade);

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant _TabFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
