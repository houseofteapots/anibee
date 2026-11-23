import 'package:flutter/material.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

import '../models.dart';
import '../services/app_services.dart';
import '../settings_store.dart';
import '../theme.dart';
import '../widgets/poster.dart';
import '../widgets/reicon_icon.dart';

/// Collection: exactly three AniList-style status lists — Watching,
/// Finished, To Be Watched. No separate Saved list (a saved title goes
/// into one of the three, default To Be Watched), no Downloads here
/// (Settings → Downloads only), no Continue Watching row (Home only).
///
/// 0.2.11: the grid is the bundled catalogue PLUS titles pulled
/// from the user's AniList list — synced titles are not in the
/// catalogue, so without the merge a pulled list would be invisible.
/// The pull runs when the tab opens (throttled to once per 15
/// minutes inside the service) and on the refresh button.
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({
    super.key,
    required this.store,
    required this.onOpenAnime,
    required this.onBrowse,
    this.services,
  });

  final SettingsStore store;
  final ValueChanged<Anime> onOpenAnime;

  /// Jump to the Search tab (used by the empty-state Browse button).
  final VoidCallback onBrowse;

  /// App services for the AniList pull (null in tests that only
  /// check the local lists — no pull happens then).
  final AppServices? services;

  /// Bundled catalogue + AniList-synced titles, deduped: when a
  /// synced title has the same AniList id as a catalogue entry, the
  /// synced entry wins (fresher metadata). Pure — unit-tested.
  /// (Static on the public widget, not the private State, so tests
  /// can reach it.)
  static List<Anime> mergeCatalogue(
    List<Anime> catalogue,
    List<Anime> synced,
  ) {
    final Map<int, Anime> byAnilistId = <int, Anime>{};
    final List<Anime> out = <Anime>[];
    for (final Anime a in catalogue) {
      out.add(a);
      if (a.anilistId != null) byAnilistId[a.anilistId!] = a;
    }
    for (final Anime s in synced) {
      final int? id = s.anilistId;
      if (id != null && byAnilistId.containsKey(id)) {
        final int index = out.indexOf(byAnilistId[id]!);
        out[index] = s;
      } else if (!out.any((Anime a) => a.id == s.id)) {
        out.add(s);
      }
    }
    return out;
  }

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  int _tab = 0;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pullAnilist());
  }

  /// Pull the AniList list into Collection (best-effort, silent —
  /// a failed pull leaves the local lists untouched).
  Future<void> _pullAnilist({bool force = false}) async {
    final AppServices? services = widget.services;
    if (services == null || !widget.store.anilistConnected) return;
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await services.pullAnilistList(store: widget.store, force: force);
    } catch (_) {
      // Best-effort: never surface a sync error on the Collection tab.
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  static const List<({String label, String status})> _tabs =
      <({String label, String status})>[
        (label: 'Watching', status: 'watching'),
        (label: 'Finished', status: 'finished'),
        (label: 'To Be Watched', status: 'plan'),
      ];

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

    return ListenableBuilder(
      listenable: widget.store,
      builder: (BuildContext context, Widget? _) {
        final List<Anime> catalogue = CollectionScreen.mergeCatalogue(
          mockCatalogue(),
          widget.store.syncedAnimeList,
        );
        List<Anime> inList(String status) {
          return catalogue
              .where((Anime a) => widget.store.statusOf(a) == status)
              .toList();
        }

        final List<List<Anime>> lists = <List<Anime>>[
          inList('watching'),
          inList('finished'),
          inList('plan'),
        ];
        final List<Anime> current = lists[_tab];

        return ListView(
          padding: const EdgeInsets.only(bottom: 110),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 12),
              child: Row(
                children: <Widget>[
                  Text(
                    'Collection',
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  if (widget.store.anilistConnected)
                    _syncing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: Icon(
                              Icons.sync_rounded,
                              color: secondaryText,
                            ),
                            tooltip: 'Sync from AniList',
                            onPressed: () => _pullAnilist(force: true),
                          ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: i == 0 ? 0 : 4,
                          right: i == _tabs.length - 1 ? 0 : 4,
                        ),
                        child: _ListTab(
                          label: '${_tabs[i].label} (${lists[i].length})',
                          selected: i == _tab,
                          accent: accent,
                          onTap: () => setState(() => _tab = i),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: current.isEmpty
                  ? _EmptyList(
                      key: ValueKey<String>('empty-${_tabs[_tab].status}'),
                      tab: _tabs[_tab].status,
                      secondaryText: secondaryText,
                      onBrowse: widget.onBrowse,
                    )
                  : Padding(
                      key: ValueKey<String>('grid-${_tabs[_tab].status}'),
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
                        itemCount: current.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Anime anime = current[index];
                          return PosterCard(
                            anime: anime,
                            width: double.infinity,
                            onTap: () => widget.onOpenAnime(anime),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ListTab extends StatelessWidget {
  const _ListTab({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? accent
              : (isDark ? AppTheme.cardDark : AppTheme.cardLight),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected
                ? Colors.white
                : (isDark
                      ? AppTheme.textSecondaryDark
                      : AppTheme.textSecondaryLight),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({
    super.key,
    required this.tab,
    required this.secondaryText,
    required this.onBrowse,
  });

  final String tab;
  final Color secondaryText;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final String icon;
    final String title;
    final String body;
    switch (tab) {
      case 'finished':
        icon = Reicon.outline.check;
        title = 'Nothing finished yet';
        body =
            'When you finish a series it lands here. '
            'You can also mark any title Finished from its page.';
      case 'plan':
        icon = Reicon.outline.bookmark;
        title = 'Nothing saved yet';
        body =
            'Tap the bookmark on any anime to add it to '
            'your To Be Watched list.';
      case 'watching':
      default:
        icon = Reicon.outline.eye;
        title = 'Nothing in progress';
        body =
            'Start watching any anime and it shows up here '
            'with your progress.';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: <Widget>[
          ReiconIcon(icon, size: 44, color: secondaryText),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppTheme.textPrimaryDark
                  : AppTheme.textPrimaryLight,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: secondaryText, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onBrowse,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Browse anime',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
