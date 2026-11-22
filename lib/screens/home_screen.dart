import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

import '../models.dart';
import '../settings_store.dart';
import '../theme.dart';
import '../widgets/poster.dart';
import '../widgets/reicon_icon.dart';

/// Home — Anilili layout (ref anilili-home-reference.jpg), AniBee
/// branding (name, Frost Glass dark design, Settings accent color).
///
/// Header (AniBee wordmark + bell + search) -> genre chips -> hero
/// carousel (EP badge, page indicator, meta, title, genre pill,
/// Details / Watch Now, dots) -> Continue Watching (long-press hint +
/// cards) -> NEWEST / POPULAR / TRENDING / TOP RATED tab bar -> poster
/// grid with score badges. Genre chips + tabs filter the grid.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.onOpenAnime,
    required this.onOpenSearch,
    required this.onWatchNow,
  });

  final SettingsStore store;
  final ValueChanged<Anime> onOpenAnime;

  /// Header search icon jumps to the Search tab.
  final VoidCallback onOpenSearch;

  /// Hero "Watch Now" opens the Detail screen straight into the player.
  final ValueChanged<Anime> onWatchNow;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<String> _tabs = <String>[
    'NEWEST',
    'POPULAR',
    'TRENDING',
    'TOP RATED',
  ];

  final PageController _pageController = PageController();
  Timer? _autoTimer;
  int _page = 0;
  String _genre = 'All';
  int _tab = 2; // TRENDING, like the reference.

  @override
  void initState() {
    super.initState();
    _autoTimer = Timer.periodic(const Duration(seconds: 5), (Timer t) {
      if (!mounted) return;
      final int next = (_page + 1) % _heroItems.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  List<Anime> get _catalogue => mockCatalogue();

  List<Anime> get _heroItems => _catalogue.sublist(0, 6);

  List<String> get _genres {
    final List<String> out = <String>['All'];
    for (final Anime a in _catalogue) {
      for (final String g in a.genres) {
        if (!out.contains(g)) out.add(g);
      }
    }
    return out.take(13).toList();
  }

  List<Anime> get _gridItems {
    List<Anime> list;
    switch (_tab) {
      case 0: // NEWEST
        list = List<Anime>.of(_catalogue)
          ..sort((Anime a, Anime b) => b.year.compareTo(a.year));
      case 1: // POPULAR
        list = _catalogue.sublist(13, 25);
      case 3: // TOP RATED
        list = List<Anime>.of(_catalogue)
          ..sort((Anime a, Anime b) => b.rating.compareTo(a.rating));
      case 2: // TRENDING
      default:
        list = _catalogue.sublist(1, 13);
    }
    if (_genre != 'All') {
      list = list.where((Anime a) => a.genres.contains(_genre)).toList();
    }
    return list;
  }

  List<Anime> get _continueWatching =>
      _catalogue.where((Anime a) => a.currentEpisode != null).toList();

  Future<void> _showListSheet(Anime anime) async {
    final Color accent = Theme.of(context).colorScheme.primary;
    final String? current = widget.store.statusOf(anime);
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF17171F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  anime.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final (String value, String label) in <(String, String)>[
                ('watching', 'Move to Watching'),
                ('finished', 'Move to Finished'),
                ('plan', 'Move to To Be Watched'),
              ])
                ListTile(
                  title: Text(
                    label,
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: current == value
                      ? Icon(Icons.check_rounded, color: accent)
                      : null,
                  onTap: () => Navigator.of(context).pop(value),
                ),
              ListTile(
                title: const Text(
                  'Remove from list',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () => Navigator.of(context).pop(''),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    if (picked.isEmpty) {
      await widget.store.setListStatus(anime.id, null);
    } else {
      await widget.store.setListStatus(anime.id, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = Theme.of(context).colorScheme.primary;
    final Color primaryText = isDark
        ? AppTheme.textPrimaryDark
        : AppTheme.textPrimaryLight;
    final Color secondaryText = isDark
        ? AppTheme.textSecondaryDark
        : AppTheme.textSecondaryLight;
    final Color card = isDark ? AppTheme.cardDark : AppTheme.cardLight;

    final List<Anime> gridItems = _gridItems;
    final List<Anime> cw = _continueWatching;

    // Header + genre chips are PINNED: they stay fixed at the top
    // while only the content below scrolls (Anilili home behaviour).
    return Column(
      children: <Widget>[
        // Header: AniBee wordmark left, bell + search right.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 56, 16, 12),
          child: Row(
            children: <Widget>[
              Text.rich(
                TextSpan(
                  children: <TextSpan>[
                    TextSpan(
                      text: 'Ani',
                      style: TextStyle(
                        color: primaryText,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    TextSpan(
                      text: 'Bee',
                      style: TextStyle(
                        color: accent,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                icon: ReiconIcon(
                  Reicon.outline.bell,
                  size: 24,
                  color: secondaryText,
                ),
                tooltip: 'Notifications',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No notifications yet'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              IconButton(
                icon: ReiconIcon(
                  Reicon.outline.search,
                  size: 24,
                  color: secondaryText,
                ),
                tooltip: 'Search',
                onPressed: widget.onOpenSearch,
              ),
            ],
          ),
        ),
        // Genre chips.
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _genres.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) {
              final String genre = _genres[index];
              final bool selected = genre == _genre;
              return InkWell(
                onTap: () => setState(() => _genre = genre),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? accent : card,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    genre,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : (isDark
                                ? AppTheme.textSecondaryDark
                                : AppTheme.textSecondaryLight),
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 110),
            children: <Widget>[
              // Hero carousel.
              SizedBox(
                height: 360,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _heroItems.length,
                  onPageChanged: (int i) => setState(() => _page = i),
                  itemBuilder: (BuildContext context, int index) {
                    final Anime anime = _heroItems[index];
                    return _HeroPage(
                      anime: anime,
                      index: index,
                      total: _heroItems.length,
                      accent: accent,
                      onDetails: () => widget.onOpenAnime(anime),
                      onWatchNow: () => widget.onWatchNow(anime),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              // Carousel dots.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (int i = 0; i < _heroItems.length; i++)
                    Container(
                      width: i == _page ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _page
                            ? accent
                            : (isDark
                                  ? const Color(0xFF3A3A48)
                                  : const Color(0xFFD5D5DE)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              // Continue Watching.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Continue Watching',
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  'Long-press a title to remove it or move it on your anime list',
                  style: TextStyle(color: secondaryText, fontSize: 12),
                ),
              ),
              SizedBox(
                height: 172,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cw.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final Anime anime = cw[index];
                    return _ContinueWatchingCard(
                      anime: anime,
                      onTap: () => widget.onOpenAnime(anime),
                      onLongPress: () => _showListSheet(anime),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              // NEWEST / POPULAR / TRENDING / TOP RATED tab bar.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    for (int i = 0; i < _tabs.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: i == 0 ? 0 : 3,
                            right: i == _tabs.length - 1 ? 0 : 3,
                          ),
                          child: InkWell(
                            onTap: () => setState(() => _tab = i),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: i == _tab ? accent : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _tabs[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: i == _tab
                                      ? Colors.white
                                      : secondaryText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Poster grid with score badges.
              if (gridItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No $_genre titles here yet',
                      style: TextStyle(color: secondaryText, fontSize: 14),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.66,
                        ),
                    itemCount: gridItems.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Anime anime = gridItems[index];
                      return _GridCard(
                        anime: anime,
                        onTap: () => widget.onOpenAnime(anime),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroPage extends StatelessWidget {
  const _HeroPage({
    required this.anime,
    required this.index,
    required this.total,
    required this.accent,
    required this.onDetails,
    required this.onWatchNow,
  });

  final Anime anime;
  final int index;
  final int total;
  final Color accent;
  final VoidCallback onDetails;
  final VoidCallback onWatchNow;

  @override
  Widget build(BuildContext context) {
    final String epBadge = anime.nextEpisode != null
        ? 'EP ${anime.nextEpisode} ${(anime.nextEpisodeIn ?? '').toUpperCase()}'
        : 'EP ${anime.currentEpisode ?? anime.episodeCount}';
    final String durationMin = mockEpisodes(anime).first.duration
        .split(':')
        .first;
    final String meta =
        'TV  •  ★ ${anime.rating.toStringAsFixed(1)}  •  $durationMin min';
    final String genrePill = anime.genres.take(3).join('  •  ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            PosterArt(anime: anime, borderRadius: 0, showTitle: false),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.black.withValues(alpha: 0.30),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.78),
                  ],
                  stops: const <double>[0.0, 0.35, 0.6, 1.0],
                ),
              ),
            ),
            // EP badge top-left.
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.schedule_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      epBadge,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Page indicator top-right.
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}/$total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            // Title block, centered at the bottom.
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                children: <Widget>[
                  Text(
                    meta,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    anime.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      genrePill,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      ElevatedButton.icon(
                        onPressed: onDetails,
                        icon: const Icon(Icons.info_outline_rounded, size: 18),
                        label: const Text(
                          'Details',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.55),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: onWatchNow,
                        icon: const Icon(
                          Icons.play_arrow_rounded,
                          size: 20,
                          color: Colors.black,
                        ),
                        label: const Text(
                          'Watch Now',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
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
    );
  }
}

class _ContinueWatchingCard extends StatelessWidget {
  const _ContinueWatchingCard({
    required this.anime,
    required this.onTap,
    required this.onLongPress,
  });

  final Anime anime;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 150,
              height: 95,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    PosterArt(anime: anime, borderRadius: 0, showTitle: false),
                    Container(color: Colors.black.withValues(alpha: 0.18)),
                    Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.black,
                          size: 26,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              anime.title,
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
            const SizedBox(height: 2),
            Text(
              'Episode ${anime.currentEpisode ?? 1}',
              style: TextStyle(
                color: isDark
                    ? AppTheme.textSecondaryDark
                    : AppTheme.textSecondaryLight,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridCard extends StatelessWidget {
  const _GridCard({required this.anime, required this.onTap});

  final Anime anime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final int score = (anime.rating * 10).round();
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  PosterArt(anime: anime, borderRadius: 0, showTitle: false),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.white,
                            size: 13,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$score%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            anime.title,
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
          const SizedBox(height: 2),
          Text(
            '${anime.year} • ${anime.episodeCount} eps',
            style: TextStyle(
              color: isDark
                  ? AppTheme.textSecondaryDark
                  : AppTheme.textSecondaryLight,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
