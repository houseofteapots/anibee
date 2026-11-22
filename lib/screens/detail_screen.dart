import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models.dart';
import '../player/trailer_player.dart';
import '../settings_store.dart';
import '../theme.dart';
import '../widgets/episode_list.dart';
import '../widgets/poster.dart';
import 'full_player_screen.dart';

/// Detail screen.
/// Layout (user-decided): banner -> title -> SERVER picker -> synopsis ->
/// episodes. The banner plays the TRAILER preview inline via libmpv;
/// a button on the SIDE of the banner (and tapping the banner) opens it
/// in the full player — same Player instance, same engine.
class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.anime,
    required this.store,
  });

  final Anime anime;
  final SettingsStore store;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final TrailerPlayer _trailer;
  late List<Episode> _episodes;
  final Map<String, Timer> _downloadTimers = <String, Timer>{};

  Anime get _anime => widget.anime;
  SettingsStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _trailer = TrailerPlayer();
    _episodes = mockEpisodes(_anime);
    _trailer.loadInline(_anime.trailerUrl);
  }

  @override
  void dispose() {
    for (final Timer t in _downloadTimers.values) {
      t.cancel();
    }
    _trailer.dispose();
    super.dispose();
  }

  Future<void> _openFullPlayer({required String label}) async {
    await _trailer.expandToFull();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => FullPlayerScreen(
          trailer: _trailer,
          store: _store,
          title: _anime.title,
          label: label,
        ),
      ),
    );
    await _trailer.backToInline();
  }

  /// M1 download simulation: the button animates queued -> downloading ->
  /// downloaded. Real file download wires in M2.
  void _toggleDownload(Episode episode) {
    final String key = '${_anime.id}:${episode.number}';
    final String? status = _store.downloadStatus[key];
    if (status == 'downloaded' || status == 'downloading') {
      _downloadTimers[key]?.cancel();
      _downloadTimers.remove(key);
      _store.removeDownload(key);
      return;
    }
    _store.setDownloadStatus(key, 'downloading');
    _store.setDownloadProgress(key, 0);
    double progress = 0;
    _downloadTimers[key] = Timer.periodic(
      const Duration(milliseconds: 300),
      (Timer timer) {
        progress += 0.12;
        if (progress >= 1) {
          timer.cancel();
          _downloadTimers.remove(key);
          _store.setDownloadStatus(key, 'downloaded');
        } else {
          _store.setDownloadProgress(key, progress);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = Theme.of(context).colorScheme.primary;
    final Color primaryText =
        isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
    final Color secondaryText =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;

    return Scaffold(
      body: ListenableBuilder(
        listenable: _store,
        builder: (BuildContext context, Widget? _) {
          final bool saved = _store.savedIds.contains(_anime.id);
          return ListView(
            padding: const EdgeInsets.only(bottom: 110),
            children: <Widget>[
              _TrailerHero(
                anime: _anime,
                trailer: _trailer,
                onExpand: () => _openFullPlayer(label: 'Trailer'),
                onBack: () => Navigator.of(context).pop(),
                onToggleSaved: () => _store.toggleSaved(_anime.id),
                saved: saved,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  _anime.title,
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: <Widget>[
                    Row(
                      children: List<Widget>.generate(
                        5,
                        (int i) => Icon(
                          Icons.star_rounded,
                          size: 18,
                          color: i < 4
                              ? const Color(0xFFFFC531)
                              : const Color(0xFF3A3A48),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_anime.rating} • ${_anime.year} • '
                      '${_anime.episodeCount} eps • TV-13',
                      style: TextStyle(color: secondaryText, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: <Widget>[
                    ..._anime.genres.map(
                      (String g) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppTheme.cardDark
                                : AppTheme.cardLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            g,
                            style: TextStyle(
                              color: primaryText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () =>
                          _openFullPlayer(label: 'Trailer'),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text(
                        'PLAY',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // SERVER picker — above the synopsis, per the design.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  'SERVER',
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ..._store.sources.where((ProviderSource s) => s.enabled).map(
                (ProviderSource source) {
                  final bool selected =
                      _store.preferredServer == source.name;
                  return Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: InkWell(
                      onTap: () =>
                          _store.setPreferredServer(source.name),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.cardDark
                              : AppTheme.cardLight,
                          borderRadius: BorderRadius.circular(12),
                          border: selected
                              ? Border.all(color: accent, width: 1.5)
                              : null,
                        ),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: selected
                                    ? accent
                                    : (isDark
                                        ? const Color(0xFF2A2A38)
                                        : const Color(0xFFD5D5DE)),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                selected
                                    ? Icons.check_rounded
                                    : Icons.circle_outlined,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              source.name,
                              style: TextStyle(
                                color: primaryText,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              source.tagline,
                              style: TextStyle(
                                color: secondaryText,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'SYNOPSIS',
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _anime.synopsis,
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ),
              EpisodeSection(
                anime: _anime,
                episodes: _episodes,
                store: _store,
                onPlay: (Episode ep) {
                  _store.markProgress(_anime.id, ep.number);
                  _openFullPlayer(
                    label: 'Ep ${ep.number} • Trailer preview',
                  );
                },
                onToggleDownload: _toggleDownload,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The inline trailer hero: libmpv Video in the banner, muted loop.
/// Side button (right edge) + tapping the banner expands to full player.
class _TrailerHero extends StatelessWidget {
  const _TrailerHero({
    required this.anime,
    required this.trailer,
    required this.onExpand,
    required this.onBack,
    required this.onToggleSaved,
    required this.saved,
  });

  final Anime anime;
  final TrailerPlayer trailer;
  final VoidCallback onExpand;
  final VoidCallback onBack;
  final VoidCallback onToggleSaved;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ListenableBuilder(
            listenable: trailer,
            builder: (BuildContext context, Widget? _) {
              if (trailer.inlineActive && trailer.loaded) {
                return GestureDetector(
                  onTap: onExpand,
                  child: Video(controller: trailer.controller),
                );
              }
              return PosterArt(anime: anime, borderRadius: 0, showTitle: false);
            },
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.black.withValues(alpha: 0.35),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
          Positioned(
            top: 48,
            left: 12,
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
              ),
              onPressed: onBack,
            ),
          ),
          Positioned(
            top: 48,
            right: 12,
            child: IconButton(
              icon: Icon(
                saved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                color: Colors.white,
              ),
              onPressed: onToggleSaved,
            ),
          ),
          // TRAILER badge.
          Positioned(
            left: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.play_circle_filled_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'TRAILER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Side button: opens the trailer in the full player.
          Positioned(
            right: 16,
            bottom: 16,
            child: InkWell(
              onTap: onExpand,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                ),
                child: const Icon(
                  Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
