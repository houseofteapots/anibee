import 'package:flutter/material.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

import '../models.dart';
import '../settings_store.dart';
import '../theme.dart';
import 'poster.dart';
import 'premium_picker.dart';
import 'reicon_icon.dart';

/// Episode list (user rules 01:44 + 01:45; refs in the goal files/):
///
/// - LONG anime (> 24 episodes): 5-column NUMBER grid, AniWaves style —
///   "Sub & Dub" filter dropdown, range dropdown (001-100, 101-200...),
///   "Find number" search to jump to an episode, grid/list toggle.
///   Tapping a number plays it; the found episode is highlighted.
/// - SHORT anime (<= 24 episodes): Miruro-style CARDS — thumbnail with
///   an "EP n" badge, title, 2-line synopsis, date, subtitle icon.
///   Controls on top: sort, watched/eye toggle, grid toggle. A
///   next-episode countdown bar sits at the bottom when the anime is
///   ongoing ("Episode 9 in 6d 20h · Nov 29 at 22:05").
///
/// The toggle switches grid <-> cards on any anime; the rule above is
/// only the default. Per-episode download (real in 0.2.5: HLS/file
/// download with resume via DownloadService) lives on the cards AND,
/// via a long-press options menu, on the grid cells. Watch progress
/// (0.2.5): cards show a thin accent progress bar + completed check;
/// grid cells show a small watched tick in the corner + a small
/// download state — the episode number always stays visible.
class EpisodeSection extends StatefulWidget {
  const EpisodeSection({
    super.key,
    required this.anime,
    required this.episodes,
    required this.store,
    required this.onPlay,
    required this.onToggleDownload,
    this.audioFilter,
    this.onAudioFilterChanged,
  });

  final Anime anime;
  final List<Episode> episodes;
  final SettingsStore store;
  final void Function(Episode episode) onPlay;
  final void Function(Episode episode) onToggleDownload;

  /// Sub/Dub filter driven by the parent (Detail server row). When set,
  /// the grid dropdown mirrors it; picking in the dropdown reports back
  /// via [onAudioFilterChanged].
  final String? audioFilter;
  final ValueChanged<String>? onAudioFilterChanged;

  @override
  State<EpisodeSection> createState() => _EpisodeSectionState();
}

class _EpisodeSectionState extends State<EpisodeSection> {
  /// Episode count above which the number grid is the default view.
  static const int kGridThreshold = 24;

  /// Episodes per range page in the grid (001-100, 101-200, ...).
  static const int kRangeSize = 100;

  late bool _gridMode;
  bool _descending = false;
  bool _hideWatched = false;
  String _audioFilter = 'Sub & Dub';
  late int _rangeStart;
  int? _highlighted;
  final TextEditingController _findController = TextEditingController();

  int get _total => widget.episodes.length;

  int? get _lastWatched => widget.store.progressEpisodes[widget.anime.id];

  bool _isWatched(Episode ep) =>
      _lastWatched != null && ep.number <= _lastWatched!;

  @override
  void initState() {
    super.initState();
    _audioFilter = widget.audioFilter ?? 'Sub & Dub';
    _gridMode = widget.anime.episodeCount > kGridThreshold;
    // Default range: the one holding the next unwatched episode.
    final int nextUp = (_lastWatched ?? 0) + 1;
    _rangeStart = ((nextUp - 1) ~/ kRangeSize) * kRangeSize + 1;
    if (_rangeStart > _total) _rangeStart = 1;
  }

  @override
  void didUpdateWidget(covariant EpisodeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Parent (Detail server row) changed the Sub/Dub pill.
    if (widget.audioFilter != null && widget.audioFilter != _audioFilter) {
      _audioFilter = widget.audioFilter!;
    }
  }

  @override
  void dispose() {
    _findController.dispose();
    super.dispose();
  }

  List<Episode> get _visibleEpisodes {
    List<Episode> list = widget.episodes.where((Episode ep) {
      if (_hideWatched && _isWatched(ep)) return false;
      // The Sub & Dub filter is a grid control; cards always show all.
      if (_gridMode && _audioFilter == 'Dub' && !ep.hasDub) return false;
      return true;
    }).toList();
    if (_descending) list = list.reversed.toList();
    return list;
  }

  List<Episode> get _rangeEpisodes {
    return _visibleEpisodes
        .where(
          (Episode ep) =>
              ep.number >= _rangeStart && ep.number < _rangeStart + kRangeSize,
        )
        .toList();
  }

  List<int> get _rangeStarts {
    final List<int> starts = <int>[];
    for (int s = 1; s <= _total; s += kRangeSize) {
      starts.add(s);
    }
    return starts;
  }

  String _rangeLabel(int start) {
    final int end = (start + kRangeSize - 1).clamp(1, _total);
    return '${start.toString().padLeft(3, '0')}'
        '-${end.toString().padLeft(3, '0')}';
  }

  void _findEpisode(String raw) {
    final int? n = int.tryParse(raw.trim());
    if (n == null || n < 1 || n > _total) return;
    setState(() {
      _rangeStart = ((n - 1) ~/ kRangeSize) * kRangeSize + 1;
      _highlighted = n;
    });
  }

  /// Range picker as a premium bottom sheet (0.2.8) — never an
  /// overlay dropdown (the old DropdownButton menu rendered as a
  /// solid grey box overlapping the Sub dropdown and the Find number
  /// field). The selected range is unmistakable (accent check + tint).
  Future<void> _showRangeSheet() async {
    final int? picked = await showPremiumPicker<int>(
      context: context,
      title: 'Episode range',
      selected: _rangeStart,
      options: <PremiumPickerOption<int>>[
        for (final int s in _rangeStarts)
          PremiumPickerOption<int>(value: s, label: _rangeLabel(s)),
      ],
    );
    if (picked != null && mounted) setState(() => _rangeStart = picked);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                'EPISODES',
                style: TextStyle(
                  color: secondaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '$_total Episodes',
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (_gridMode) _buildGridControls(isDark, card, primaryText),
        // Sort / watched / grid-toggle controls (both modes).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              _ControlButton(
                icon: Icons.swap_vert_rounded,
                tooltip: _descending ? 'Newest first' : 'Oldest first',
                active: _descending,
                onTap: () => setState(() => _descending = !_descending),
              ),
              const SizedBox(width: 8),
              _ControlButton(
                icon: _hideWatched
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                tooltip: _hideWatched ? 'Show watched' : 'Hide watched',
                active: _hideWatched,
                onTap: () => setState(() => _hideWatched = !_hideWatched),
              ),
              const SizedBox(width: 8),
              _ControlButton(
                icon: _gridMode ? Icons.list_rounded : Icons.grid_view_rounded,
                tooltip: _gridMode ? 'Show as cards' : 'Show as grid',
                active: false,
                onTap: () => setState(() => _gridMode = !_gridMode),
              ),
            ],
          ),
        ),
        if (_gridMode)
          _buildGrid(isDark, card, primaryText, secondaryText, accent)
        else
          _buildCards(isDark, card, primaryText, secondaryText, accent),
        if (widget.anime.nextEpisode != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 18,
                    color: secondaryText,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Episode ${widget.anime.nextEpisode} in '
                      '${widget.anime.nextEpisodeIn} · '
                      '${widget.anime.nextEpisodeAt}',
                      style: TextStyle(
                        color: primaryText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGridControls(bool isDark, Color card, Color primaryText) {
    final Color secondaryText = isDark
        ? AppTheme.textSecondaryDark
        : AppTheme.textSecondaryLight;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: <Widget>[
          _DropdownBox(
            card: card,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _audioFilter,
                icon: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: secondaryText,
                ),
                style: TextStyle(color: primaryText, fontSize: 13),
                dropdownColor: card,
                items: const <String>['Sub & Dub', 'Sub', 'Dub']
                    .map(
                      (String v) => DropdownMenuItem<String>(
                        value: v,
                        child: _DropdownItemLabel(
                          label: v,
                          isSelected: v == _audioFilter,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (String? v) {
                  if (v != null) {
                    setState(() => _audioFilter = v);
                    widget.onAudioFilterChanged?.call(v);
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          _RangeBox(
            card: card,
            label: _rangeLabel(_rangeStart),
            hasMultiple: _rangeStarts.length > 1,
            primaryText: primaryText,
            secondaryText: secondaryText,
            onTap: _rangeStarts.length > 1 ? _showRangeSheet : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _findController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.search,
              onSubmitted: _findEpisode,
              style: TextStyle(color: primaryText, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Find number',
                hintStyle: TextStyle(color: secondaryText, fontSize: 13),
                filled: true,
                fillColor: card,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF3A3A48)
                        : const Color(0xFFD5D5DE),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark
                        ? const Color(0xFF3A3A48)
                        : const Color(0xFFD5D5DE),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Long-press a grid cell: episode options (Play + Download /
  /// Remove download / Cancel download). Download is the same flow
  /// as the cards' button (0.2.5: the user asked for an OPTION, not
  /// a hidden gesture that downloads directly).
  Future<void> _showEpisodeOptions(Episode ep) async {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accent = Theme.of(context).colorScheme.primary;
    final Color primaryText = isDark
        ? AppTheme.textPrimaryDark
        : AppTheme.textPrimaryLight;
    final Color sheetBg = isDark ? AppTheme.cardDark : AppTheme.cardLight;
    final String key = '${widget.anime.id}:${ep.number}';
    final String? status = widget.store.downloadStatus[key];
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3A48),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Episode ${ep.number} · ${ep.title}',
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.play_arrow_rounded, color: accent),
                title: Text('Play', style: TextStyle(color: primaryText)),
                onTap: () => Navigator.of(context).pop('play'),
              ),
              if (status == 'downloaded')
                ListTile(
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: primaryText,
                  ),
                  title: Text(
                    'Remove download',
                    style: TextStyle(color: primaryText),
                  ),
                  onTap: () => Navigator.of(context).pop('download'),
                )
              else if (status == 'downloading')
                ListTile(
                  leading: Icon(Icons.close_rounded, color: primaryText),
                  title: Text(
                    'Cancel download',
                    style: TextStyle(color: primaryText),
                  ),
                  onTap: () => Navigator.of(context).pop('download'),
                )
              else
                ListTile(
                  leading: Icon(Icons.download_rounded, color: accent),
                  title: Text('Download', style: TextStyle(color: primaryText)),
                  onTap: () => Navigator.of(context).pop('download'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    if (choice == 'play') {
      widget.onPlay(ep);
    } else if (choice == 'download') {
      widget.onToggleDownload(ep);
    }
  }

  Widget _buildGrid(
    bool isDark,
    Color card,
    Color primaryText,
    Color secondaryText,
    Color accent,
  ) {
    final List<Episode> eps = _rangeEpisodes;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.6,
      ),
      itemCount: eps.length,
      itemBuilder: (BuildContext context, int i) {
        final Episode ep = eps[i];
        final bool highlighted = _highlighted == ep.number;
        final bool watched = _isWatched(ep);
        // 0.2.5: real completed state (small tick) + download state,
        // both tiny corner marks — the number stays fully visible.
        final bool completed = widget.store.isEpisodeCompleted(
          widget.anime,
          ep,
        );
        final String dlKey = '${widget.anime.id}:${ep.number}';
        final String? dlStatus = widget.store.downloadStatus[dlKey];
        final double dlProgress = widget.store.downloadProgress[dlKey] ?? 0;
        return InkWell(
          onTap: () {
            setState(() => _highlighted = ep.number);
            widget.onPlay(ep);
          },
          onLongPress: () => _showEpisodeOptions(ep),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: highlighted ? accent : card,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: <Widget>[
                Center(
                  child: Text(
                    '${ep.number}',
                    style: TextStyle(
                      color: highlighted
                          ? Colors.white
                          : (watched ? secondaryText : primaryText),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (completed)
                  Positioned(
                    top: 3,
                    right: 4,
                    child: Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: highlighted ? Colors.white : accent,
                    ),
                  ),
                if (dlStatus == 'downloading')
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                        value: dlProgress,
                        strokeWidth: 2,
                        color: highlighted ? Colors.white : accent,
                      ),
                    ),
                  )
                else if (dlStatus == 'downloaded')
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Icon(
                      Icons.download_done_rounded,
                      size: 12,
                      color: highlighted ? Colors.white : accent,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCards(
    bool isDark,
    Color card,
    Color primaryText,
    Color secondaryText,
    Color accent,
  ) {
    final List<Episode> eps = _visibleEpisodes;
    return Column(
      children: eps.map((Episode ep) {
        final String key = '${widget.anime.id}:${ep.number}';
        final String? status = widget.store.downloadStatus[key];
        final double progress = widget.store.downloadProgress[key] ?? 0;
        // 0.2.5: real watch progress (accent bar) + completed state.
        final double watchProgress = widget.store.episodeProgressFor(
          widget.anime,
          ep,
        );
        final bool completed = widget.store.isEpisodeCompleted(
          widget.anime,
          ep,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: InkWell(
            onTap: () => widget.onPlay(ep),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: 104,
                          height: 82,
                          child: Stack(
                            children: <Widget>[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  width: 104,
                                  height: 82,
                                  child: PosterArt(
                                    anime: widget.anime,
                                    showTitle: false,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 6,
                                bottom: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'EP ${ep.number}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              if (completed)
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: accent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      size: 13,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  ep.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: primaryText,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  ep.synopsis,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: secondaryText,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: <Widget>[
                                    Icon(
                                      Icons.closed_caption_rounded,
                                      size: 18,
                                      color: secondaryText,
                                    ),
                                    const Spacer(),
                                    Text(
                                      ep.airDate,
                                      style: TextStyle(
                                        color: secondaryText,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    _DownloadButton(
                                      status: status,
                                      progress: progress,
                                      accent: accent,
                                      onTap: () => widget.onToggleDownload(ep),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    // 0.2.5: thin accent progress bar along the card's
                    // bottom edge (full when completed). Unwatched = none.
                    if (watchProgress > 0)
                      SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(
                          value: watchProgress,
                          backgroundColor: Colors.transparent,
                          color: accent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Small square control button (sort / eye / grid toggle).
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color card = isDark ? AppTheme.cardDark : AppTheme.cardLight;
    final Color accent = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(10),
            border: active ? Border.all(color: accent, width: 1.5) : null,
          ),
          child: Icon(
            icon,
            size: 20,
            color: active
                ? accent
                : (isDark
                      ? AppTheme.textPrimaryDark
                      : AppTheme.textPrimaryLight),
          ),
        ),
      ),
    );
  }
}

/// Range selector box: shows the current episode range (001-047).
/// Tapping opens a bottom sheet with the range options — never an
/// overlay dropdown (the old menu rendered as a solid grey box over the
/// Sub dropdown and Find number field). A single range renders as a
/// static label: no chevron, not tappable.
class _RangeBox extends StatelessWidget {
  const _RangeBox({
    required this.card,
    required this.label,
    required this.hasMultiple,
    required this.primaryText,
    required this.secondaryText,
    required this.onTap,
  });

  final Color card;
  final String label;
  final bool hasMultiple;
  final Color primaryText;
  final Color secondaryText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label, style: TextStyle(color: primaryText, fontSize: 13)),
            if (hasMultiple) ...<Widget>[
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: secondaryText,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dark rounded box wrapping a dropdown (grid controls).
class _DropdownBox extends StatelessWidget {
  const _DropdownBox({required this.card, required this.child});

  final Color card;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

/// Per-episode download button: download -> progress -> downloaded.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({
    required this.status,
    required this.progress,
    required this.accent,
    required this.onTap,
  });

  final String? status;
  final double progress;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (status == 'downloaded') {
      // Reicon check (not a generic Material download icon).
      child = ReiconIcon(Reicon.outline.check, size: 22, color: accent);
    } else if (status == 'downloading') {
      child = SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          value: progress,
          strokeWidth: 2.5,
          color: accent,
        ),
      );
    } else {
      // Reicon Outline download (reicon.dev) — the app's download mark.
      child = ReiconIcon(
        Reicon.outline.download,
        size: 22,
        color: Theme.of(context).brightness == Brightness.dark
            ? AppTheme.textSecondaryDark
            : AppTheme.textSecondaryLight,
      );
    }
    return IconButton(
      onPressed: onTap,
      icon: child,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}

/// One row of a compact DropdownButton menu (0.2.8): the selected value
/// carries an accent checkmark, so the current choice is obvious at a
/// glance — the same treatment as the premium pickers.
class _DropdownItemLabel extends StatelessWidget {
  const _DropdownItemLabel({required this.label, required this.isSelected});

  final String label;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w400,
          ),
        ),
        if (isSelected) ...<Widget>[
          const SizedBox(width: 8),
          Icon(Icons.check_rounded, color: accent, size: 16),
        ],
      ],
    );
  }
}
