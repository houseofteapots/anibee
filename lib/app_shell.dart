import 'package:flutter/material.dart';

import 'models.dart';
import 'player/trailer_player.dart';
import 'screens/full_player_screen.dart';
import 'services/app_services.dart';
import 'services/miruro_resolver.dart';
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

  /// Play a completed download offline (0.2.5): rebuild the anime
  /// from the download record, open the local file in the full
  /// player. Episode switches inside the player prefer the local
  /// file when that episode is downloaded, else resolve online.
  void _playOffline(String key) {
    final Map<String, dynamic>? record = widget.store.downloadRecordFor(key);
    if (record == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download not found — please download it again.'),
        ),
      );
      return;
    }
    final String status = widget.store.downloadStatus[key] ?? '';
    if (status == 'downloading') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Still downloading — please wait.')),
      );
      return;
    }
    if (status == 'failed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Download failed — re-download it from the episode list.',
          ),
        ),
      );
      return;
    }
    final Anime anime = Anime(
      id: record['animeId'] as String? ?? '',
      anilistId: (record['anilistId'] as num?)?.toInt(),
      title: record['title'] as String? ?? 'Unknown',
      rating: 0,
      year: 0,
      episodeCount: (record['episodeCount'] as num?)?.toInt() ?? 0,
      genres: const <String>[],
      synopsis: '',
      gradient: const <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
      posterUrl: record['posterUrl'] as String?,
    );
    final List<Episode> episodes = mockEpisodes(anime);
    final int epNum = (record['episode'] as num?)?.toInt() ?? 1;
    final Episode initial = episodes.firstWhere(
      (Episode e) => e.number == epNum,
      orElse: () => episodes.first,
    );
    final ResolvedStream? local = widget.services.downloads.localStreamFor(
      key,
      widget.store,
    );
    if (local == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download file not found — please download it again.'),
        ),
      );
      return;
    }
    final TrailerPlayer trailer = TrailerPlayer();
    Navigator.of(context)
        .push(
          SmoothPageRoute<void>(
            builder: (BuildContext context) => FullPlayerScreen(
              trailer: trailer,
              store: widget.store,
              anime: anime,
              episodes: episodes,
              initialEpisode: initial,
              stream: local,
              onEpisodeChanged: (Episode ep) =>
                  widget.store.markProgress(anime, ep.number),
              resolver: widget.services.miruro,
              anilist: widget.services.anilist,
              subDub: 'Sub',
              onResolveEpisode: (Episode episode) async {
                final String k = '${anime.id}:${episode.number}';
                final ResolvedStream? offline = widget.services.downloads
                    .localStreamFor(k, widget.store);
                if (offline != null) return offline;
                return widget.services.resolveEpisode(
                  anime: anime,
                  episode: episode.number,
                  subDub: 'Sub',
                  store: widget.store,
                );
              },
            ),
          ),
        )
        .then((_) => trailer.dispose());
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
                child: DownloadsScreen(
                  store: widget.store,
                  services: widget.services,
                  onPlayDownload: _playOffline,
                  embedded: true,
                ),
              ),
              _TabFade(
                active: _tab == 4,
                child: SettingsScreen(
                  store: widget.store,
                  configService: widget.configService,
                  services: widget.services,
                  onPlayDownload: _playOffline,
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
