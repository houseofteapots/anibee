import 'package:flutter/material.dart';

import '../models.dart';
import '../settings_store.dart';
import '../theme.dart';
import '../widgets/poster.dart';

/// Collection: My List (saved) + Continue Watching.
class CollectionScreen extends StatelessWidget {
  const CollectionScreen({
    super.key,
    required this.store,
    required this.onOpenAnime,
  });

  final SettingsStore store;
  final ValueChanged<Anime> onOpenAnime;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryText =
        isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
    final Color secondaryText =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;

    return ListenableBuilder(
      listenable: store,
      builder: (BuildContext context, Widget? _) {
        final List<Anime> catalogue = mockCatalogue();
        final List<Anime> saved = catalogue
            .where((Anime a) => store.savedIds.contains(a.id))
            .toList();
        final List<Anime> watching = catalogue
            .where((Anime a) => a.currentEpisode != null)
            .toList();

        return ListView(
          padding: const EdgeInsets.only(bottom: 110),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 12),
              child: Text(
                'Collection',
                style: TextStyle(
                  color: primaryText,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            AnimeRow(
              title: 'Continue Watching',
              items: watching,
              onTapAnime: onOpenAnime,
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'My List',
                style: TextStyle(
                  color: primaryText,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (saved.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Text(
                  'Nothing saved yet. Tap the bookmark on any anime to '
                  'save it here.',
                  style: TextStyle(color: secondaryText, fontSize: 15),
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
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: saved.length,
                  itemBuilder: (BuildContext context, int index) {
                    return PosterCard(
                      anime: saved[index],
                      width: double.infinity,
                      onTap: () => onOpenAnime(saved[index]),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
