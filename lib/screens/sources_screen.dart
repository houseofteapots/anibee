import 'package:flutter/material.dart';

import '../models.dart';
import '../settings_store.dart';
import '../theme.dart';

/// Sources: enable/disable providers, drag to reorder, star = preferred.
/// Miruro is preferred by default.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key, required this.store});

  final SettingsStore store;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = Theme.of(context).colorScheme.primary;
    final Color secondaryText =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;

    return Scaffold(
      appBar: AppBar(title: const Text('Sources')),
      body: ListenableBuilder(
        listenable: store,
        builder: (BuildContext context, Widget? _) {
          final List<ProviderSource> sources = store.sources;
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  'Choose which providers to use',
                  style: TextStyle(color: secondaryText, fontSize: 15),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: sources.length,
                  onReorderItem: (int oldIndex, int newIndex) async {
                    final List<ProviderSource> next =
                        List<ProviderSource>.of(sources);
                    final ProviderSource moved = next.removeAt(oldIndex);
                    next.insert(newIndex, moved);
                    await store.setSources(next);
                  },
                  itemBuilder: (BuildContext context, int index) {
                    final ProviderSource source = sources[index];
                    return Container(
                      key: ValueKey<String>(source.name),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color:
                            isDark ? AppTheme.cardDark : AppTheme.cardLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(Icons.drag_handle_rounded),
                            const SizedBox(width: 8),
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                source.name[0],
                                style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Row(
                          children: <Widget>[
                            Text(
                              source.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            if (source.preferred) ...<Widget>[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFFFC531),
                                size: 16,
                              ),
                              const Text(
                                'Preferred',
                                style: TextStyle(
                                  color: Color(0xFFFFC531),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(source.tagline),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              icon: Icon(
                                source.preferred
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                color: source.preferred
                                    ? const Color(0xFFFFC531)
                                    : secondaryText,
                              ),
                              onPressed: () =>
                                  store.setPreferredServer(source.name),
                            ),
                            Switch(
                              value: source.enabled,
                              onChanged: (bool value) async {
                                final List<ProviderSource> next =
                                    List<ProviderSource>.of(sources);
                                next[index] =
                                    source.copyWith(enabled: value);
                                await store.setSources(next);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  'Drag to reorder priority',
                  style: TextStyle(color: secondaryText, fontSize: 13),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
