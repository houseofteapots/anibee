import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets/poster.dart';

/// Search: field + genre chips + poster grid (mock catalogue, M1).
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.onOpenAnime,
  });

  final ValueChanged<Anime> onOpenAnime;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  String _genre = 'All';

  static const List<String> _genres = <String>[
    'All',
    'Action',
    'Romance',
    'Sci-Fi',
    'Fantasy',
    'Horror',
    'Adventure',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = Theme.of(context).colorScheme.primary;
    final Color primaryText =
        isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
    final Color secondaryText =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;

    final List<Anime> results = mockCatalogue().where((Anime a) {
      final bool matchesQuery = _query.isEmpty ||
          a.title.toLowerCase().contains(_query.toLowerCase());
      final bool matchesGenre =
          _genre == 'All' || a.genres.contains(_genre);
      return matchesQuery && matchesGenre;
    }).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 56, 16, 12),
          child: Text(
            'Search',
            style: TextStyle(
              color: primaryText,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _controller,
            onChanged: (String v) => setState(() => _query = v),
            style: TextStyle(color: primaryText),
            decoration: InputDecoration(
              hintText: 'Search anime...',
              hintStyle: TextStyle(color: secondaryText),
              prefixIcon: Icon(Icons.search_rounded, color: secondaryText),
              filled: true,
              fillColor: isDark ? AppTheme.cardDark : AppTheme.cardLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _genres.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) {
              final String genre = _genres[index];
              final bool selected = genre == _genre;
              return ChoiceChip(
                label: Text(genre),
                selected: selected,
                selectedColor: accent,
                backgroundColor:
                    isDark ? AppTheme.cardDark : AppTheme.cardLight,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : primaryText,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) => setState(() => _genre = genre),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 12,
              childAspectRatio: 0.62,
            ),
            itemCount: results.length,
            itemBuilder: (BuildContext context, int index) {
              final Anime anime = results[index];
              return PosterCard(
                anime: anime,
                width: double.infinity,
                onTap: () => widget.onOpenAnime(anime),
              );
            },
          ),
        ),
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'No anime found. Try another search.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondaryText, fontSize: 15),
            ),
          ),
      ],
    );
  }
}
