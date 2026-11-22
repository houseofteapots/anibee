import 'package:flutter/material.dart';

import '../models.dart';
import '../settings_store.dart';
import '../theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/poster.dart';

/// Home: hero banner + Continue Watching + Trending + Top Airing rows.
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
    final List<Anime> trending = catalogue.sublist(1);
    final List<Anime> topAiring = catalogue.reversed.toList();

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
          child: Stack(
            children: <Widget>[
              Positioned(
                right: 16,
                top: 12,
                child: Text(
                  anime.title
                      .split(RegExp(r'\s+'))
                      .take(1)
                      .join()
                      .toUpperCase(),
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withValues(alpha: 0.10),
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
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
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
    );
  }
}
