import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

import '../models.dart';
import '../player/trailer_player.dart';
import '../settings_store.dart';
import '../theme.dart';
import '../widgets/episode_list.dart';
import '../widgets/page_route.dart';
import '../widgets/poster.dart';
import '../widgets/reicon_icon.dart';
import '../widgets/server_sheet.dart';
import 'full_player_screen.dart';

/// Detail screen.
/// Layout: banner -> title -> My List -> synopsis -> server row
/// (Anilili-style dropdown + SUB/DUB + status) -> episodes. The banner
/// plays the TRAILER preview inline via libmpv; a button on the SIDE of
/// the banner (and tapping the banner) opens it in the full player —
/// same Player instance, same engine.
class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.anime,
    required this.store,
    this.autoPlay = false,
  });

  final Anime anime;
  final SettingsStore store;

  /// Home "Watch Now" opens straight into the full player.
  final bool autoPlay;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final TrailerPlayer _trailer;
  late List<Episode> _episodes;
  final Map<String, Timer> _downloadTimers = <String, Timer>{};
  String _subDub = 'Sub';
  bool _connecting = false;
  Timer? _connectTimer;

  Anime get _anime => widget.anime;
  SettingsStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _trailer = TrailerPlayer();
    _episodes = mockEpisodes(_anime);
    _trailer.loadInline(_anime.trailerUrl);
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openFullPlayer();
      });
    }
  }

  @override
  void dispose() {
    for (final Timer t in _downloadTimers.values) {
      t.cancel();
    }
    _connectTimer?.cancel();
    _trailer.dispose();
    super.dispose();
  }

  /// Opens the Anilili-style server sheet; on pick, switches the
  /// preferred server and shows "Reconnecting..." briefly.
  Future<void> _showServerSheet() async {
    final ({String server, String subDub})? result = await showServerSheet(
      context: context,
      store: _store,
      currentServer: _store.preferredServer,
      subDub: _subDub,
    );
    if (result == null) return;
    await _store.setPreferredServer(result.server);
    setState(() {
      _subDub = result.subDub;
      _connecting = true;
    });
    _connectTimer?.cancel();
    _connectTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _connecting = false);
    });
  }

  Future<void> _openFullPlayer({Episode? episode, bool markPlayed = true}) async {
    final Episode initial = episode ??
        _episodes.firstWhere(
          (Episode e) => e.number == (_anime.currentEpisode ?? 1),
          orElse: () => _episodes.first,
        );
    if (markPlayed) {
      _store.markProgress(_anime.id, initial.number);
      _autoStatus(initial);
    }
    await _trailer.expandToFull();
    if (!mounted) return;
    await Navigator.of(context).push(
      SmoothPageRoute<void>(
        builder: (BuildContext context) => FullPlayerScreen(
          trailer: _trailer,
          store: _store,
          anime: _anime,
          episodes: _episodes,
          initialEpisode: initial,
          onEpisodeChanged: _onPlayerEpisodeChanged,
        ),
      ),
    );
    await _trailer.backToInline();
  }

  void _onPlayerEpisodeChanged(Episode episode) {
    _store.markProgress(_anime.id, episode.number);
    _autoStatus(episode);
  }

  /// Playing an episode puts it in the Collection lists automatically:
  /// last episode → Finished, anything else → Watching.
  void _autoStatus(Episode episode) {
    if (episode.number >= _anime.episodeCount) {
      _store.setListStatus(_anime.id, 'finished');
    } else {
      _store.setListStatus(_anime.id, 'watching');
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'watching':
        return 'Watching';
      case 'finished':
        return 'Finished';
      case 'plan':
        return 'To Be Watched';
      default:
        return 'Not in list';
    }
  }

  Future<void> _pickListStatus() async {
    final Color accent = Theme.of(context).colorScheme.primary;
    final String? current = _store.statusOf(_anime);
    final String? picked = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('My List'),
        children: <Widget>[
          for (final (String value, String label)
              in <(String, String)>[
            ('plan', 'To Be Watched'),
            ('watching', 'Watching'),
            ('finished', 'Finished'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(value),
              child: Row(
                children: <Widget>[
                  Text(label),
                  const Spacer(),
                  if (current == value)
                    Icon(Icons.check_rounded, color: accent),
                ],
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Remove from list'),
          ),
        ],
      ),
    );
    if (picked == null) return;
    if (picked.isEmpty) {
      _store.setListStatus(_anime.id, null);
    } else {
      _store.setListStatus(_anime.id, picked);
    }
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
                onExpand: () => _openFullPlayer(markPlayed: false),
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
                      onPressed: () => _openFullPlayer(),
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
              // MY LIST — Collection status picker (Watching / Finished /
              // To Be Watched). Bookmarking also lands here (To Be Watched).
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: InkWell(
                  onTap: _pickListStatus,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
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
                        Icon(Icons.bookmark_rounded, color: accent, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          'My List',
                          style: TextStyle(
                            color: primaryText,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _statusLabel(_store.statusOf(_anime)),
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: secondaryText,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
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
              // Server row (Anilili style, above the episodes list):
              // compact dropdown + SUB/DUB pill + connection status.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Row(
                  children: <Widget>[
                    InkWell(
                      onTap: _showServerSheet,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.cardDark
                              : AppTheme.cardLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            ReiconIcon(
                              Reicon.outline.download,
                              size: 18,
                              color: accent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _store.preferredServer,
                              style: TextStyle(
                                color: primaryText,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            ReiconIcon(
                              Reicon.outline.chevronDown,
                              size: 16,
                              color: secondaryText,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppTheme.cardDark
                            : AppTheme.cardLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (final String v in <String>['Sub', 'Dub'])
                            InkWell(
                              onTap: () => setState(() => _subDub = v),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: _subDub == v
                                      ? accent
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  v.toUpperCase(),
                                  style: TextStyle(
                                    color: _subDub == v
                                        ? Colors.white
                                        : secondaryText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _connecting
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Reconnecting ${_store.preferredServer}...',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: secondaryText,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 16,
                                  color: AppTheme.success,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Connected',
                                  style: TextStyle(
                                    color: secondaryText,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              EpisodeSection(
                anime: _anime,
                episodes: _episodes,
                store: _store,
                audioFilter: _subDub,
                onAudioFilterChanged: (String v) {
                  if (v == 'Sub' || v == 'Dub') {
                    setState(() => _subDub = v);
                  }
                },
                onPlay: (Episode ep) {
                  _openFullPlayer(episode: ep);
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
