import 'package:flutter/material.dart';

import '../models.dart';
import '../settings_store.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/poster.dart';

/// Home: hero banner + Continue Watching + Trending + Popular + Top
/// Airing rows — the full 39-title catalogue, every card with a real
/// poster. Continue Watching stays here only (never in Collection).
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.onOpenAnime,
  });

  final SettingsStore store;
  final ValueChanged<Anime> onOpenAnime;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = Theme.of(context).colorScheme.primary;
    final List<Anime> catalogue = mockCatalogue();
    final Anime featured = catalogue.first;
    final List<Anime> continueWatching = catalogue
        .where((Anime a) => a.currentEpisode != null)
        .toList();
    final List<Anime> trending = catalogue.sublist(1, 13);
    final List<Anime> popular = catalogue.sublist(13, 25);
    final List<Anime> topAiring = catalogue.sublist(25).reversed.toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
          child: Row(
            children: <Widget>[
              const AppLogo(size: 28, borderRadius: 8),
              const SizedBox(width: 10),
              Text.rich(
                TextSpan(
                  children: <TextSpan>[
                    TextSpan(
                      text: 'Ani',
                      style: TextStyle(
                        color: isDark
                            ? AppTheme.textPrimaryDark
                            : AppTheme.textPrimaryLight,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    TextSpan(
                      text: 'Bee',
                      style: TextStyle(
                        color: accent,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  Icons.notifications_outlined,
                  color: isDark
                      ? AppTheme.textSecondaryDark
                      : AppTheme.textSecondaryLight,
                ),
                onPressed: () {},
              ),
            ],
          ),
        ),
        _HeroBanner(
          anime: featured,
          accent: accent,
          onTap: () => onOpenAnime(featured),
        ),
        const SizedBox(height: 28),
        AnimeRow(
          title: 'Continue Watching',
          items: continueWatching,
          onTapAnime: onOpenAnime,
        ),
        const SizedBox(height: 28),
        AnimeRow(
          title: 'Trending Now',
          items: trending,
          onTapAnime: onOpenAnime,
        ),
        const SizedBox(height: 28),
        AnimeRow(
          title: 'Popular',
          items: popular,
          onTapAnime: onOpenAnime,
        ),
        const SizedBox(height: 28),
        AnimeRow(
          title: 'Top Airing',
          items: topAiring,
          onTapAnime: onOpenAnime,
        ),
      ],
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.anime,
    required this.accent,
    required this.onTap,
  });

  final Anime anime;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: anime.gradient,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // Real poster as the hero art (gradient underneath while
                // it loads / if offline).
                PosterArt(
                  anime: anime,
                  borderRadius: 0,
                  showTitle: false,
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.black.withValues(alpha: 0.25),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.72),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        anime.title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ep ${anime.currentEpisode ?? 1} • '
                        'New Episode • 24min',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          ElevatedButton.icon(
                            onPressed: onTap,
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 20,
                            ),
                            label: const Text(
                              'Play',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
