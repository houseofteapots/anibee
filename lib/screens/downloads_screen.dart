import 'package:flutter/material.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

import '../models.dart';
import '../settings_store.dart';
import '../theme.dart';
import '../widgets/reicon_icon.dart';

/// Downloads: episodes saved for offline watching (M1 state only).
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key, required this.store});

  final SettingsStore store;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = Theme.of(context).colorScheme.primary;
    final Color primaryText =
        isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
    final Color secondaryText =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;

    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: ListenableBuilder(
        listenable: store,
        builder: (BuildContext context, Widget? _) {
          final List<MapEntry<String, String>> entries =
              store.downloadStatus.entries.toList();
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No downloads yet.\nTap the download button on any '
                  'episode to save it for offline watching.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondaryText, fontSize: 15),
                ),
              ),
            );
          }
          final List<Anime> catalogue = mockCatalogue();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: entries.length,
            itemBuilder: (BuildContext context, int index) {
              final MapEntry<String, String> entry = entries[index];
              final List<String> parts = entry.key.split(':');
              final String animeId = parts[0];
              final String epNum = parts.length > 1 ? parts[1] : '?';
              final Anime anime = catalogue.firstWhere(
                (Anime a) => a.id == animeId,
                orElse: () => catalogue.first,
              );
              final String status = entry.value;
              final double progress =
                  store.downloadProgress[entry.key] ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: anime.gradient,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: ReiconIcon(
                        Reicon.outline.play,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            anime.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: primaryText,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Episode $epNum • ${status == 'downloaded'
                                ? 'Ready offline'
                                : status == 'downloading'
                                    ? 'Downloading ${(progress * 100).toInt()}%'
                                    : 'Queued'}',
                            style: TextStyle(
                              color: secondaryText,
                              fontSize: 13,
                            ),
                          ),
                          if (status == 'downloading') ...<Widget>[
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: progress,
                              minHeight: 4,
                              color: accent,
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: ReiconIcon(
                        Reicon.outline.trash,
                        size: 22,
                      ),
                      onPressed: () =>
                          store.removeDownload(entry.key),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
