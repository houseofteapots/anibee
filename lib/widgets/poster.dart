import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// Real cover art (M1.1): the anime's poster from the network (AniList CDN
/// or TMDB), cached in Flutter's in-memory ImageCache, with the gradient
/// art as the local fallback while loading or when offline / on error.
class PosterArt extends StatelessWidget {
  const PosterArt({
    super.key,
    required this.anime,
    this.borderRadius = 12,
    this.showTitle = true,
  });

  final Anime anime;
  final double borderRadius;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final String initials = anime.title
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .take(2)
        .map((String w) => w[0])
        .join()
        .toUpperCase();
    final String? url = anime.posterUrl;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: anime.gradient,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (url != null)
              Image.network(
                url,
                fit: BoxFit.cover,
                // While the poster loads (or if it fails), the gradient
                // underneath shows — never a blank tile.
                loadingBuilder:
                    (BuildContext context, Widget child,
                        ImageChunkEvent? progress) {
                  if (progress == null) return child;
                  return const SizedBox.shrink();
                },
                errorBuilder: (BuildContext context, Object error,
                    StackTrace? stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
            if (url == null)
              Positioned(
                right: 8,
                top: 8,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
              ),
            if (showTitle)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.transparent,
                        Colors.black.withValues(alpha: url == null ? 0 : 0.55),
                      ],
                    ),
                  ),
                  child: Text(
                    anime.title.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One poster card: art + title + optional Continue Watching progress.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.anime,
    required this.width,
    this.onTap,
  });

  final Anime anime;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: width,
              height: width * 1.35,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.08),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: PosterArt(anime: anime),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              anime.title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark
                    ? AppTheme.textPrimaryDark
                    : AppTheme.textPrimaryLight,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (anime.currentEpisode != null) ...<Widget>[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: anime.progress,
                  minHeight: 4,
                  backgroundColor: isDark
                      ? const Color(0xFF2A2A38)
                      : const Color(0xFFD5D5DE),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ep ${anime.currentEpisode} • '
                '${anime.minutesLeft ?? 0}min left',
                style: TextStyle(
                  color: isDark
                      ? AppTheme.textSecondaryDark
                      : AppTheme.textSecondaryLight,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A titled horizontal poster row ("Trending Now" + See All).
class AnimeRow extends StatelessWidget {
  const AnimeRow({
    super.key,
    required this.title,
    required this.items,
    required this.onTapAnime,
  });

  final String title;
  final List<Anime> items;
  final ValueChanged<Anime> onTapAnime;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  color: isDark
                      ? AppTheme.textPrimaryDark
                      : AppTheme.textPrimaryLight,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'See All',
                style: TextStyle(
                  color: isDark
                      ? AppTheme.textSecondaryDark
                      : AppTheme.textSecondaryLight,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int index) {
              final Anime anime = items[index];
              return PosterCard(
                anime: anime,
                width: 128,
                onTap: () => onTapAnime(anime),
              );
            },
          ),
        ),
      ],
    );
  }
}
