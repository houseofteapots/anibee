import 'package:flutter/material.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

import '../models.dart';
import '../services/app_services.dart';
import '../settings_store.dart';
import '../theme.dart';
import '../widgets/reicon_icon.dart';

/// Downloads: episodes saved for offline watching (0.2.5: REAL files
/// — HLS segments + local playlist, or a direct file — via
/// DownloadService). Tapping a completed download plays the local
/// file offline; rows show the record's real title (never the old
/// mock-catalogue fallback). Deleting removes the files, not just
/// the row.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({
    super.key,
    required this.store,
    this.services,
    this.onPlayDownload,
    this.embedded = false,
  });

  final SettingsStore store;

  /// App services (download service + resolver for offline playback).
  /// Null in tests — rows then only show state, no playback.
  final AppServices? services;

  /// Called with the download key when the user taps a row:
  /// AppShell plays the local file (or explains why it can't).
  final ValueChanged<String>? onPlayDownload;

  /// True when shown as a nav tab: no AppBar, content starts below
  /// the status bar like the other tabs. False (default) when pushed
  /// from Settings → Downloads, which keeps its AppBar.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color primaryText = isDark
        ? AppTheme.textPrimaryDark
        : AppTheme.textPrimaryLight;
    final Color secondaryText = isDark
        ? AppTheme.textSecondaryDark
        : AppTheme.textSecondaryLight;

    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('Downloads')),
      body: ListenableBuilder(
        listenable: store,
        builder: (BuildContext context, Widget? _) {
          final List<MapEntry<String, String>> entries = store
              .downloadStatus
              .entries
              .toList();
          final Widget list = entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No downloads yet.\nTap the download button on any '
                      'episode to save it for offline watching.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondaryText, fontSize: 14),
                    ),
                  ),
                )
              : _DownloadsList(
                  entries: entries,
                  store: store,
                  services: services,
                  onPlayDownload: onPlayDownload,
                  topPadding: embedded ? 0 : 8,
                );
          if (!embedded) return list;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 56, 16, 12),
                child: Text(
                  'Downloads',
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(child: list),
            ],
          );
        },
      ),
    );
  }
}

class _DownloadsList extends StatelessWidget {
  const _DownloadsList({
    required this.entries,
    required this.store,
    required this.services,
    required this.onPlayDownload,
    required this.topPadding,
  });

  final List<MapEntry<String, String>> entries;
  final SettingsStore store;
  final AppServices? services;
  final ValueChanged<String>? onPlayDownload;
  final double topPadding;

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
    final List<Anime> catalogue = mockCatalogue();
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
      itemCount: entries.length,
      itemBuilder: (BuildContext context, int index) {
        final MapEntry<String, String> entry = entries[index];
        final List<String> parts = entry.key.split(':');
        final String animeId = parts[0];
        final String epNum = parts.length > 1 ? parts[1] : '?';
        // Real title from the download record (0.2.5); the catalogue
        // fallback only covers rows from before records existed.
        final Map<String, dynamic>? record = store.downloadRecordFor(entry.key);
        final String title =
            record?['title'] as String? ??
            catalogue
                .firstWhere(
                  (Anime a) => a.id == animeId,
                  orElse: () => catalogue.first,
                )
                .title;
        final List<Color> gradient = (record?['posterUrl'] as String?) != null
            ? const <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)]
            : catalogue
                  .firstWhere(
                    (Anime a) => a.id == animeId,
                    orElse: () => catalogue.first,
                  )
                  .gradient;
        final String status = entry.value;
        final double progress = store.downloadProgress[entry.key] ?? 0;
        final String subtitle = status == 'downloaded'
            ? 'Episode $epNum • Ready offline — tap to play'
            : status == 'downloading'
            ? 'Episode $epNum • Downloading ${(progress * 100).toInt()}%'
            : status == 'failed'
            ? 'Episode $epNum • Failed — re-download from the episode list'
            : 'Episode $epNum • Queued';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.cardDark : AppTheme.cardLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: onPlayDownload == null
                ? null
                : () => onPlayDownload!(entry.key),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: gradient),
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
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: primaryText,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(color: secondaryText, fontSize: 12),
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
                    icon: ReiconIcon(Reicon.outline.trash, size: 22),
                    onPressed: () async {
                      // Delete the files too, not just the row.
                      final AppServices? svc = services;
                      if (svc != null) {
                        await svc.downloads.removeDownload(entry.key, store);
                      } else {
                        await store.removeDownload(entry.key);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
