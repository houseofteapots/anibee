import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/anilist_service.dart';
import '../theme.dart';
import '../widgets/poster.dart';

/// Search: field + genre chips + poster grid.
///
/// M2: live AniList GraphQL search (debounced 400 ms) + the local
/// 39-title catalogue as instant fallback. Local results show
/// immediately on every keystroke; remote results merge in below
/// (deduped by title). When AniList is unreachable the local results
/// stay and a note says so — search never shows a dead empty state.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.onOpenAnime,
    required this.anilist,
  });

  final ValueChanged<Anime> onOpenAnime;
  final AniListService anilist;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  String _genre = 'All';
  Timer? _debounce;
  List<Anime> _remote = <Anime>[];
  bool _searching = false;
  bool _remoteFailed = false;

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
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _remote = <Anime>[];
        _searching = false;
        _remoteFailed = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final String q = _controller.text.trim();
      if (q.length < 2) return;
      try {
        final List<Anime> results = await widget.anilist.searchAnime(q);
        if (!mounted || _controller.text.trim() != q) return;
        setState(() {
          _remote = results;
          _searching = false;
          _remoteFailed = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _searching = false;
          _remoteFailed = true;
        });
      }
    });
  }

  List<Anime> _localResults() {
    final String q = _query.toLowerCase();
    return mockCatalogue().where((Anime a) {
      final bool matchesQuery =
          _query.isEmpty ||
          a.title.toLowerCase().contains(q) ||
          a.genres.any((String g) => g.toLowerCase().contains(q));
      final bool matchesGenre = _genre == 'All' || a.genres.contains(_genre);
      return matchesQuery && matchesGenre;
    }).toList();
  }

  List<Anime> _mergedResults(List<Anime> local) {
    if (_query.trim().length < 2) return local;
    final Set<String> seen = local
        .map((Anime a) => a.title.toLowerCase())
        .toSet();
    final List<Anime> merged = List<Anime>.of(local);
    for (final Anime a in _remote) {
      if (seen.add(a.title.toLowerCase())) merged.add(a);
    }
    return merged;
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

    final List<Anime> results = _mergedResults(_localResults());

    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 56, 16, 12),
          child: Text(
            'Search',
            style: TextStyle(
              color: primaryText,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _controller,
            onChanged: _onQueryChanged,
            style: TextStyle(color: primaryText),
            decoration: InputDecoration(
              hintText: 'Search anime...',
              hintStyle: TextStyle(color: secondaryText),
              prefixIcon: Icon(Icons.search_rounded, color: secondaryText),
              suffixIcon: _searching
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      ),
                    )
                  : null,
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
                backgroundColor: isDark
                    ? AppTheme.cardDark
                    : AppTheme.cardLight,
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
        if (_query.isNotEmpty || _genre != 'All')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '${results.length} result${results.length == 1 ? '' : 's'}'
              '${_query.isNotEmpty ? " for '$_query'" : ''}'
              '${_searching ? ' • searching AniList…' : ''}',
              style: TextStyle(color: secondaryText, fontSize: 13),
            ),
          ),
        if (_remoteFailed && _query.trim().length >= 2)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Couldn\'t reach AniList — showing local results.',
              style: TextStyle(color: secondaryText, fontSize: 12),
            ),
          ),
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
        if (results.isEmpty && !_searching)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'No anime found. Try another search.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondaryText, fontSize: 14),
            ),
          ),
      ],
    );
  }
}
