import 'dart:async';

import 'package:anibee_mpv_pip/anibee_mpv_pip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models.dart';
import '../player/trailer_player.dart';
import '../services/miruro_resolver.dart';
import '../settings_store.dart';
import '../theme.dart';
import '../widgets/poster.dart';

/// Full-screen player (Zeus feature set, AniBee accent).
///
/// - Opens in LANDSCAPE, returns to portrait on close.
/// - Never blank: the anime poster sits behind the video; a loading
///   spinner while the trailer buffers; a real error state (poster +
///   message + Retry) when the sample fails to load.
/// - Play/pause, seek bar with times, double-tap seek, swipe gestures
///   (seek / brightness / volume), playback speed, audio track picker,
///   subtitle track picker + in-player subtitle edit + delay, episode
///   picker (prev/next + list), Skip Intro chip, quality picker,
///   PiP (native iOS window via the Zeus frame-tap mechanism), autoplay
///   next episode, resume from last position, hwdec from Settings,
///   pinch zoom (0.5–3.0, double-tap resets to fit).
/// - Accent: every highlight (seek bar, Skip Intro chip, selected rows,
///   radios, episode selection) uses the accent color selected in
///   Settings → Appearance (`Theme.colorScheme.primary`) — never a
///   hardcoded gold/amber/white.
///
/// M1.1 plays the sample trailer for every episode; full episode streams
/// arrive with milestone 2 (real Miruro resolve). The menus are fully
/// wired to libmpv and work against whatever tracks the stream has.
///
/// M2: [stream] is the resolved real stream for [initialEpisode]
/// (Miruro/Anikoto or a Debrid direct link). When the user switches
/// episode inside the player, [onResolveEpisode] resolves the new
/// episode's stream (null = keep playing the current episode). When
/// both are null the player falls back to the sample trailer.
class FullPlayerScreen extends StatefulWidget {
  const FullPlayerScreen({
    super.key,
    required this.trailer,
    required this.store,
    required this.anime,
    required this.episodes,
    required this.initialEpisode,
    this.onEpisodeChanged,
    this.stream,
    this.onResolveEpisode,
  });

  final TrailerPlayer trailer;
  final SettingsStore store;
  final Anime anime;
  final List<Episode> episodes;
  final Episode initialEpisode;

  /// Fired when the user jumps to another episode inside the player
  /// (Detail marks progress + list status).
  final ValueChanged<Episode>? onEpisodeChanged;

  /// Resolved real stream for the initial episode (M2).
  final ResolvedStream? stream;

  /// Resolve the stream for a newly selected episode (M2).
  final Future<ResolvedStream?> Function(Episode episode)? onResolveEpisode;

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  Player get _player => widget.trailer.player;
  SettingsStore get _store => widget.store;

  late Episode _currentEpisode;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  /// The stream currently playing (M2, null = sample trailer).
  ResolvedStream? _currentStream;

  /// True while a new episode's stream is resolving.
  bool _resolving = false;
  final ValueNotifier<double> _videoScale = ValueNotifier<double>(1.0);
  final ValueNotifier<String?> _gestureHint = ValueNotifier<String?>(null);
  double _brightness = 0; // mpv brightness -100..100
  double _rate = 1.0;

  StreamSubscription<Duration>? _positionSub;
  bool _resumeApplied = false;
  bool _autoplayShown = false;
  Timer? _autoplayTimer;
  int _autoplayCountdown = 5;

  // PiP (software-rendered player + native window).
  Player? _pipPlayer;
  // Retained (never read): the controller owns the native texture —
  // dropping it would kill the frames feeding the PiP window.
  // ignore: unused_field
  VideoController? _pipController;
  AnibeeMpvPip? _pipBridge;
  bool _inPip = false;
  bool _pipBusy = false;
  DateTime _lastPipUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  // Gesture state.
  Duration? _dragStartPosition;
  Duration? _dragHintTarget;
  double _dragAccumDx = 0;
  double _dragStartVolume = 100;
  double _dragStartBrightness = 0;
  double _scaleBase = 1.0;

  String get _resumeKey => '${widget.anime.id}:${_currentEpisode.number}';

  Episode? get _nextEpisode {
    final int i = widget.episodes.indexOf(_currentEpisode);
    if (i < 0 || i + 1 >= widget.episodes.length) return null;
    return widget.episodes[i + 1];
  }

  Episode? get _prevEpisode {
    final int i = widget.episodes.indexOf(_currentEpisode);
    if (i <= 0) return null;
    return widget.episodes[i - 1];
  }

  @override
  void initState() {
    super.initState();
    _currentEpisode = widget.initialEpisode;
    _rate = _player.state.rate;

    // Landscape + immersive, like a real video player.
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Hand the shared player to the full screen, apply Settings.
    unawaited(widget.trailer.expandToFull());
    unawaited(widget.trailer.applyHwdec(_store.hwDecoding));
    _applySubtitleStyle();
    // M2: load the resolved real stream (unmuted) once the surface
    // is ours; the trailer path loads nothing extra.
    if (widget.stream != null) {
      _currentStream = widget.stream;
      unawaited(_loadStream(widget.stream!));
    }

    _positionSub = _player.stream.position.listen(_onPosition);
    _scheduleHide();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _hideTimer?.cancel();
    _autoplayTimer?.cancel();
    _videoScale.dispose();
    _gestureHint.dispose();
    _saveResumePosition();
    _teardownPip();
    unawaited(widget.trailer.backToInline());
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------------------------------------------------------------- resume

  void _onPosition(Duration position) {
    final Duration duration = _player.state.duration;
    if (!_resumeApplied && duration.inSeconds > 20) {
      _resumeApplied = true;
      final double? saved = _store.resumeSeconds[_resumeKey];
      if (saved != null && saved > 10 && saved < duration.inSeconds - 20) {
        unawaited(_player.seek(Duration(seconds: saved.round())));
      }
    }
    // Autoplay-next countdown near the end of a real episode.
    if (!_autoplayShown &&
        _store.autoplayNext &&
        _nextEpisode != null &&
        duration.inSeconds > 10 &&
        position >= duration - const Duration(seconds: 3)) {
      _autoplayShown = true;
      _showAutoplayOverlay();
    }
    // Keep the native PiP window's scrubber in sync (throttled).
    if (_inPip && _pipBridge != null) {
      final DateTime now = DateTime.now();
      if (now.difference(_lastPipUpdate).inMilliseconds > 500) {
        _lastPipUpdate = now;
        unawaited(
          _pipBridge!.updateState(
            position: _pipPlayer?.state.position ?? position,
            duration: duration,
            playing: _pipPlayer?.state.playing ?? _player.state.playing,
            rate: _rate,
          ),
        );
      }
    }
  }

  void _saveResumePosition() {
    final Duration pos = _player.state.position;
    final Duration dur = _player.state.duration;
    if (pos.inSeconds > 10 && pos < dur - const Duration(seconds: 20)) {
      unawaited(_store.setResumeSeconds(_resumeKey, pos.inSeconds.toDouble()));
    } else {
      unawaited(_store.clearResumeSeconds(_resumeKey));
    }
  }

  // ------------------------------------------------------- subtitle styling

  /// Best-effort mpv property set (Zeus pattern): the public Player has
  /// no setProperty — the native platform player does. Never throws, so
  /// a styling/brightness set can never break playback.
  static Future<void> _setMpvProperty(
    Player player,
    String key,
    String value,
  ) async {
    final PlatformPlayer? platform = player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty(key, value);
      } catch (_) {
        // Best-effort only.
      }
    }
  }

  void _applySubtitleStyle() {
    final Color color =
        kSubtitleColors[_store.subColorIndex.clamp(
          0,
          kSubtitleColors.length - 1,
        )];
    final String hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    unawaited(
      _setMpvProperty(
        _player,
        'sub-font-size',
        (_store.subSize * 2).toString(),
      ),
    );
    unawaited(_setMpvProperty(_player, 'sub-color', hex));
    unawaited(
      _setMpvProperty(
        _player,
        'sub-back-color',
        _store.subBackground ? '#CC000000' : '#00000000',
      ),
    );
    unawaited(
      _setMpvProperty(
        _player,
        'sub-pos',
        _store.subPosition == 'Top' ? '5' : '100',
      ),
    );
    unawaited(
      _setMpvProperty(
        _player,
        'sub-delay',
        (_store.subDelayMs / 1000).toStringAsFixed(2),
      ),
    );
  }

  // ------------------------------------------------------------- controls

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted && _player.state.playing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _pokeControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  Future<void> _togglePlay() async {
    _pokeControls();
    if (_player.state.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _seekBy(int seconds) async {
    final Duration pos = _player.state.position;
    final Duration dur = _player.state.duration;
    Duration target = pos + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > dur) target = dur;
    await _player.seek(target);
    _pokeControls();
  }

  void _cycleSpeed() {
    const List<double> rates = <double>[1.0, 1.25, 1.5, 2.0, 0.5];
    final int i = rates.indexOf(_rate);
    final double next = rates[(i + 1) % rates.length];
    setState(() => _rate = next);
    unawaited(_player.setRate(next));
    _pokeControls();
  }

  /// Load a resolved stream into the shared player (unmuted).
  Future<void> _loadStream(ResolvedStream stream) async {
    await widget.trailer.loadStream(stream);
    _applySubtitleStyle();
  }

  void _selectEpisode(Episode episode) {
    if (episode.number == _currentEpisode.number) return;
    final Episode previous = _currentEpisode;
    setState(() {
      _currentEpisode = episode;
      _autoplayShown = false;
      _resumeApplied = true; // resume handled inline below
    });
    widget.onEpisodeChanged?.call(episode);
    // M2: a real stream per episode — resolve the new one. Failure
    // keeps the current episode playing (never a blank screen).
    if (widget.onResolveEpisode != null) {
      unawaited(_switchToEpisode(episode, previous));
      return;
    }
    final double? saved =
        _store.resumeSeconds['${widget.anime.id}:${episode.number}'];
    unawaited(
      _player.seek(
        saved != null && saved > 10
            ? Duration(seconds: saved.round())
            : Duration.zero,
      ),
    );
    unawaited(_player.play());
    _pokeControls();
  }

  Future<void> _switchToEpisode(Episode episode, Episode previous) async {
    setState(() => _resolving = true);
    final ResolvedStream? stream = await widget.onResolveEpisode!(episode);
    if (!mounted) return;
    if (stream == null) {
      setState(() {
        _currentEpisode = previous;
        _resolving = false;
      });
      _snack('Could not find sources for episode ${episode.number}');
      return;
    }
    _currentStream = stream;
    await _loadStream(stream);
    if (!mounted) return;
    setState(() => _resolving = false);
    final double? saved =
        _store.resumeSeconds['${widget.anime.id}:${episode.number}'];
    unawaited(
      _player.seek(
        saved != null && saved > 10
            ? Duration(seconds: saved.round())
            : Duration.zero,
      ),
    );
    unawaited(_player.play());
    _pokeControls();
  }

  void _showAutoplayOverlay() {
    _autoplayCountdown = 5;
    _autoplayTimer?.cancel();
    _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_autoplayCountdown <= 1) {
        t.cancel();
        final Episode? next = _nextEpisode;
        if (next != null) _selectEpisode(next);
      } else {
        setState(() => _autoplayCountdown -= 1);
      }
    });
    setState(() {});
  }

  // ------------------------------------------------------------------- PiP

  Future<void> _enterPip() async {
    if (_pipBusy || _pipPlayer != null) return;
    final String? url = widget.trailer.url;
    if (url == null) {
      _snack('No video loaded yet');
      return;
    }
    if (!await AnibeeMpvPip.isSupported) {
      _snack('Picture-in-Picture is not available on this device');
      return;
    }
    _pipBusy = true;
    final Duration pos = _player.state.position;
    final Duration dur = _player.state.duration;
    try {
      final Player pipPlayer = Player();
      // Software renderer: the fork's frame tap feeds the native window.
      final VideoController pipController = VideoController(
        pipPlayer,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: false,
          hwdec: 'videotoolbox-copy',
        ),
      );
      await _setMpvProperty(pipPlayer, 'hwdec', 'videotoolbox-copy');
      await pipPlayer.open(
        Media(url, httpHeaders: _currentStream?.headers ?? const <String, String>{}),
      );
      await pipPlayer.seek(pos);
      await pipPlayer.setVolume(_player.state.volume);
      await pipPlayer.setRate(_rate);
      await pipPlayer.play();
      await _player.pause();

      final AnibeeMpvPip bridge = AnibeeMpvPip();
      bridge.onPipStarted = () {
        if (mounted) setState(() => _inPip = true);
      };
      bridge.onPipStopped = (bool restored) async {
        await _restoreFromPip();
      };
      bridge.onPipFailed = (String reason) async {
        if (mounted) _snack('PiP failed: $reason');
        await _restoreFromPip();
      };
      bridge.onPipSetPlaying = (bool playing) {
        if (playing) {
          unawaited(pipPlayer.play());
        } else {
          unawaited(pipPlayer.pause());
        }
      };
      bridge.onPipSkip = (int seconds) {
        unawaited(
          pipPlayer.seek(pipPlayer.state.position + Duration(seconds: seconds)),
        );
      };
      await bridge.prepare(
        position: pos,
        duration: dur,
        playing: true,
        rate: _rate,
      );
      final bool ok = await bridge.enterPiP();
      if (!ok) {
        await pipPlayer.dispose();
        return;
      }
      _pipPlayer = pipPlayer;
      _pipController = pipController;
      _pipBridge = bridge;
    } catch (e) {
      if (mounted) _snack('PiP failed: $e');
      await _restoreFromPip();
    } finally {
      _pipBusy = false;
    }
  }

  Future<void> _restoreFromPip() async {
    final Player? pipPlayer = _pipPlayer;
    if (pipPlayer == null) return;
    final Duration pos = pipPlayer.state.position;
    final bool wasPlaying = pipPlayer.state.playing;
    await _pipBridge?.suspend();
    _pipPlayer = null;
    _pipController = null;
    _pipBridge = null;
    _inPip = false;
    await pipPlayer.dispose();
    await _player.seek(pos);
    if (wasPlaying) await _player.play();
    if (mounted) setState(() {});
  }

  void _teardownPip() {
    final Player? pipPlayer = _pipPlayer;
    _pipPlayer = null;
    _pipController = null;
    final AnibeeMpvPip? bridge = _pipBridge;
    _pipBridge = null;
    _inPip = false;
    if (bridge != null) unawaited(bridge.exitPiP());
    if (pipPlayer != null) unawaited(pipPlayer.dispose());
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // ---------------------------------------------------------------- sheets

  Future<void> _showAudioSheet() async {
    final Tracks tracks = _player.state.tracks;
    final String currentId = _player.state.track.audio.id;
    final List<AudioTrack> list = tracks.audio
        .where((AudioTrack t) => t.id != 'auto' && t.id != 'no')
        .toList();
    await _showTrackSheet<AudioTrack>(
      title: 'Audio',
      currentId: currentId,
      entries: <({String id, String label, AudioTrack? track})>[
        (id: 'auto', label: 'Auto', track: AudioTrack.auto()),
        ...list.map(
          (AudioTrack t) => (
            id: t.id,
            label: _trackLabel(t.title, t.language, 'Track'),
            track: t,
          ),
        ),
        (id: 'no', label: 'Off', track: AudioTrack.no()),
      ],
      onPick: (AudioTrack track) => _player.setAudioTrack(track),
    );
  }

  Future<void> _showSubtitleSheet() async {
    final Tracks tracks = _player.state.tracks;
    final String currentId = _player.state.track.subtitle.id;
    final List<SubtitleTrack> list = tracks.subtitle
        .where((SubtitleTrack t) => t.id != 'auto' && t.id != 'no')
        .toList();
    await _showTrackSheet<SubtitleTrack>(
      title: 'Subtitles',
      currentId: currentId,
      entries: <({String id, String label, SubtitleTrack? track})>[
        (id: 'no', label: 'Off', track: SubtitleTrack.no()),
        ...list.map(
          (SubtitleTrack t) => (
            id: t.id,
            label: _trackLabel(t.title, t.language, 'Subtitle'),
            track: t,
          ),
        ),
      ],
      onPick: (SubtitleTrack track) => _player.setSubtitleTrack(track),
    );
  }

  Future<void> _showQualitySheet() async {
    // M2: real streams carry quality variants — picking one reloads
    // the same stream at that rendition, keeping the position.
    final ResolvedStream? stream = _currentStream;
    if (stream != null && stream.variants.isNotEmpty) {
      final Color accent = Theme.of(context).colorScheme.primary;
      final Duration pos = _player.state.position;
      final String? picked = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: const Color(0xFF17171F),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (BuildContext context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'Quality',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final StreamVariant v in stream.variants)
                        ListTile(
                          title: Text(
                            v.qualityLabel,
                            style: const TextStyle(color: Colors.white),
                          ),
                          trailing: v.url == stream.url
                              ? Icon(Icons.check_rounded, color: accent)
                              : null,
                          onTap: () => Navigator.of(context).pop(v.url),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
      if (picked != null && picked != stream.url) {
        final StreamVariant variant = stream.variants.firstWhere(
          (StreamVariant v) => v.url == picked,
          orElse: () => stream.variants.first,
        );
        _currentStream = ResolvedStream(
          url: variant.url,
          label: '${stream.source} ${variant.qualityLabel}',
          source: stream.source,
          headers: stream.headers,
          variants: stream.variants,
          subtitles: stream.subtitles,
        );
        await _loadStream(_currentStream!);
        unawaited(_player.seek(pos));
        unawaited(_player.play());
        _pokeControls();
      }
      return;
    }
    final Tracks tracks = _player.state.tracks;
    final String currentId = _player.state.track.video.id;
    final List<VideoTrack> list = tracks.video
        .where((VideoTrack t) => t.id != 'auto' && t.id != 'no')
        .toList();
    await _showTrackSheet<VideoTrack>(
      title: 'Quality',
      currentId: currentId,
      entries: <({String id, String label, VideoTrack? track})>[
        (
          id: 'auto',
          label: list.isEmpty ? 'Auto (single quality in this sample)' : 'Auto',
          track: VideoTrack.auto(),
        ),
        ...list.map(
          (VideoTrack t) => (
            id: t.id,
            label: _trackLabel(t.title, null, 'Quality'),
            track: t,
          ),
        ),
      ],
      onPick: (VideoTrack track) => _player.setVideoTrack(track),
    );
  }

  String _trackLabel(String? title, String? language, String fallback) {
    if (title != null && title.isNotEmpty) return title;
    if (language != null && language.isNotEmpty) return language;
    return fallback;
  }

  Future<void> _showTrackSheet<T>({
    required String title,
    required String currentId,
    required List<({String id, String label, T? track})> entries,
    required Future<void> Function(T) onPick,
  }) async {
    final Color accent = Theme.of(context).colorScheme.primary;
    final T? picked = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: const Color(0xFF17171F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final entry in entries)
                      ListTile(
                        title: Text(
                          entry.label,
                          style: const TextStyle(color: Colors.white),
                        ),
                        trailing: entry.id == currentId
                            ? Icon(Icons.check_rounded, color: accent)
                            : null,
                        onTap: () => Navigator.of(context).pop(entry.track),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      await onPick(picked);
      _pokeControls();
    }
  }

  Future<void> _showSubtitleEditSheet() async {
    final Color accent = Theme.of(context).colorScheme.primary;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF17171F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Subtitle style',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Size',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    Slider(
                      value: _store.subSize,
                      min: 12,
                      max: 28,
                      divisions: 16,
                      activeColor: accent,
                      onChanged: (double v) {
                        setSheet(() {});
                        unawaited(_store.setSubSize(v));
                        _applySubtitleStyle();
                      },
                    ),
                    const Text(
                      'Color',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      children: <Widget>[
                        for (int i = 0; i < kSubtitleColors.length; i++)
                          InkWell(
                            onTap: () {
                              setSheet(() {});
                              unawaited(_store.setSubColorIndex(i));
                              _applySubtitleStyle();
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: kSubtitleColors[i],
                                shape: BoxShape.circle,
                                border: i == _store.subColorIndex
                                    ? Border.all(color: accent, width: 2)
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Background',
                        style: TextStyle(color: Colors.white),
                      ),
                      value: _store.subBackground,
                      activeThumbColor: accent,
                      onChanged: (bool v) {
                        setSheet(() {});
                        unawaited(_store.setSubBackground(v));
                        _applySubtitleStyle();
                      },
                    ),
                    Row(
                      children: <Widget>[
                        const Text(
                          'Position',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(width: 12),
                        for (final String pos in <String>['Bottom', 'Top'])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(pos),
                              selected: _store.subPosition == pos,
                              selectedColor: accent,
                              labelStyle: TextStyle(
                                color: _store.subPosition == pos
                                    ? Colors.white
                                    : Colors.white70,
                              ),
                              onSelected: (_) {
                                setSheet(() {});
                                unawaited(_store.setSubPosition(pos));
                                _applySubtitleStyle();
                              },
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Delay: ${(_store.subDelayMs / 1000).toStringAsFixed(1)}s',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    Slider(
                      value: _store.subDelayMs.toDouble(),
                      min: -5000,
                      max: 5000,
                      divisions: 100,
                      activeColor: accent,
                      onChanged: (double v) {
                        setSheet(() {});
                        unawaited(_store.setSubDelayMs(v.round()));
                        _applySubtitleStyle();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showEpisodeSheet() async {
    final Color accent = Theme.of(context).colorScheme.primary;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF17171F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'Episodes — ${widget.anime.title}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.6,
                        ),
                    itemCount: widget.episodes.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Episode ep = widget.episodes[index];
                      final bool selected = ep.number == _currentEpisode.number;
                      return InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          _selectEpisode(ep);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected ? accent : const Color(0xFF23232F),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${ep.number}',
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: widget.trailer,
        builder: (BuildContext context, Widget? _) {
          final bool hasError = widget.trailer.loadError != null;
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Poster behind everything: the screen is never blank.
              PosterArt(anime: widget.anime, showTitle: false),
              if (!hasError)
                ValueListenableBuilder<double>(
                  valueListenable: _videoScale,
                  builder: (BuildContext context, double scale, Widget? _) {
                    return Transform.scale(
                      scale: scale,
                      child: Video(
                        controller: widget.trailer.controller,
                        fit: BoxFit.contain,
                        // No built-in controls: the vendored media_kit_video
                        // defaults to AdaptiveVideoControls, whose bottom
                        // bar (duplicate time + fullscreen button) renders
                        // UNDER the custom controls — the extra strip the
                        // user reported (0.2.1, Chainsaw Man EP 2).
                        // `NoVideoControls` is `null`, which disables the
                        // built-in controls entirely.
                        controls: NoVideoControls,
                      ),
                    );
                  },
                ),
              if (!hasError)
                StreamBuilder<bool>(
                  stream: _player.stream.buffering,
                  initialData: _player.state.buffering,
                  builder: (BuildContext context, AsyncSnapshot<bool> snap) {
                    if (snap.data == true) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              if (hasError)
                _ErrorState(
                  accent: accent,
                  onRetry: () => unawaited(widget.trailer.retry()),
                ),
              if (_resolving)
                Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Finding sources…',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!hasError) _buildGestures(),
              if (!hasError && _controlsVisible) _buildControls(accent),
              ValueListenableBuilder<String?>(
                valueListenable: _gestureHint,
                builder: (BuildContext context, String? hint, Widget? _) {
                  if (hint == null) return const SizedBox.shrink();
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        hint,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (_autoplayTimer != null && _autoplayTimer!.isActive)
                _AutoplayOverlay(
                  countdown: _autoplayCountdown,
                  next: _nextEpisode,
                  accent: accent,
                  onPlayNow: () {
                    _autoplayTimer?.cancel();
                    final Episode? next = _nextEpisode;
                    if (next != null) _selectEpisode(next);
                  },
                  onCancel: () {
                    _autoplayTimer?.cancel();
                    setState(() {});
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGestures() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _pokeControls,
      onDoubleTapDown: (TapDownDetails details) {
        // Zoomed in: double-tap resets to fit. Otherwise: side seek.
        if (_videoScale.value != 1.0) {
          _videoScale.value = 1.0;
          return;
        }
        final double w = MediaQuery.of(context).size.width;
        if (details.globalPosition.dx < w / 2) {
          unawaited(_seekBy(-_store.doubleTapSeek));
        } else {
          unawaited(_seekBy(_store.doubleTapSeek));
        }
      },
      onScaleStart: (ScaleStartDetails details) {
        _scaleBase = _videoScale.value;
      },
      onScaleUpdate: (ScaleUpdateDetails details) {
        if (details.scale == 1.0) return;
        _videoScale.value = (_scaleBase * details.scale).clamp(0.5, 3.0);
      },
      onHorizontalDragStart: (DragStartDetails details) {
        if (!_store.gestures) return;
        _dragStartPosition = _player.state.position;
        _dragAccumDx = 0;
      },
      onHorizontalDragUpdate: (DragUpdateDetails details) {
        if (!_store.gestures || _dragStartPosition == null) return;
        _dragAccumDx += details.delta.dx;
        final int seconds = (_dragAccumDx / 10).round();
        _dragHintTarget = _dragStartPosition! + Duration(seconds: seconds);
        _gestureHint.value = '${seconds >= 0 ? '+' : ''}$seconds s';
      },
      onHorizontalDragEnd: (DragEndDetails details) {
        if (!_store.gestures || _dragStartPosition == null) return;
        final Duration target = _dragHintTarget ?? _dragStartPosition!;
        _dragStartPosition = null;
        _dragHintTarget = null;
        _gestureHint.value = null;
        final Duration dur = _player.state.duration;
        Duration clamped = target;
        if (clamped < Duration.zero) clamped = Duration.zero;
        if (clamped > dur) clamped = dur;
        unawaited(_player.seek(clamped));
        _pokeControls();
      },
      onVerticalDragStart: (DragStartDetails details) {
        if (!_store.gestures) return;
        _dragStartVolume = _player.state.volume;
        _dragStartBrightness = _brightness;
      },
      onVerticalDragUpdate: (DragUpdateDetails details) {
        if (!_store.gestures) return;
        final double w = MediaQuery.of(context).size.width;
        final bool rightSide = details.globalPosition.dx > w / 2;
        if (rightSide) {
          final double v = (_dragStartVolume - details.delta.dy * 0.5).clamp(
            0,
            100,
          );
          unawaited(_player.setVolume(v));
          _gestureHint.value = 'Volume ${v.round()}%';
        } else {
          final double b = (_dragStartBrightness - details.delta.dy * 0.3)
              .clamp(-100, 100);
          _brightness = b;
          unawaited(
            _setMpvProperty(_player, 'brightness', b.toStringAsFixed(0)),
          );
          _gestureHint.value = 'Brightness ${b >= 0 ? '+' : ''}${b.round()}';
        }
      },
      onVerticalDragEnd: (DragEndDetails details) {
        _gestureHint.value = null;
      },
      child: const SizedBox.expand(),
    );
  }

  Widget _buildControls(Color accent) {
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0x99000000),
              Colors.transparent,
              Colors.transparent,
              Color(0x99000000),
            ],
            stops: <double>[0.0, 0.25, 0.65, 1.0],
          ),
        ),
        child: Column(
          children: <Widget>[
            _buildTopBar(accent),
            const Spacer(),
            StreamBuilder<Duration>(
              stream: _player.stream.position,
              initialData: _player.state.position,
              builder: (BuildContext context, AsyncSnapshot<Duration> snap) {
                final Duration pos = snap.data ?? Duration.zero;
                final Duration dur = _player.state.duration;
                final bool showSkip =
                    _store.skipIntro &&
                    dur.inSeconds > 120 &&
                    pos.inSeconds < 95;
                if (!showSkip) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16, bottom: 12),
                    child: ElevatedButton(
                      onPressed: () {
                        unawaited(_player.seek(const Duration(seconds: 85)));
                        _pokeControls();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Skip Intro',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                );
              },
            ),
            _buildBottomBar(accent),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(Color accent) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.anime.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Episode ${_currentEpisode.number} · ${_currentEpisode.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: _showEpisodeSheet,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'EP ${_currentEpisode.number}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            _TopButton(
              label:
                  '${_rate.toStringAsFixed(_rate.truncateToDouble() == _rate ? 0 : 2)}x',
              onTap: _cycleSpeed,
            ),
            IconButton(
              icon: Icon(
                Icons.picture_in_picture_alt_rounded,
                color: _inPip ? accent : Colors.white,
              ),
              tooltip: 'Picture-in-Picture',
              onPressed: _inPip
                  ? () async {
                      final AnibeeMpvPip? bridge = _pipBridge;
                      if (bridge != null) await bridge.exitPiP();
                    }
                  : _enterPip,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(Color accent) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            StreamBuilder<Duration>(
              stream: _player.stream.position,
              initialData: _player.state.position,
              builder: (BuildContext context, AsyncSnapshot<Duration> snap) {
                final Duration pos = snap.data ?? Duration.zero;
                final Duration dur = _player.state.duration;
                final double max = dur.inMilliseconds.toDouble().clamp(
                  1,
                  double.infinity,
                );
                return Row(
                  children: <Widget>[
                    Text(
                      _formatDuration(pos),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: accent,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                        ),
                        child: Slider(
                          value: pos.inMilliseconds.toDouble().clamp(0, max),
                          max: max,
                          onChanged: (double v) {
                            unawaited(
                              _player.seek(Duration(milliseconds: v.round())),
                            );
                          },
                        ),
                      ),
                    ),
                    Text(
                      _formatDuration(dur),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  icon: const Icon(
                    Icons.skip_previous_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                  onPressed: _prevEpisode == null
                      ? null
                      : () => _selectEpisode(_prevEpisode!),
                ),
                const SizedBox(width: 8),
                StreamBuilder<bool>(
                  stream: _player.stream.playing,
                  initialData: _player.state.playing,
                  builder: (BuildContext context, AsyncSnapshot<bool> snap) {
                    final bool playing = snap.data ?? false;
                    return IconButton(
                      icon: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                      onPressed: _togglePlay,
                    );
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.skip_next_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                  onPressed: _nextEpisode == null
                      ? null
                      : () => _selectEpisode(_nextEpisode!),
                ),
                const SizedBox(width: 16),
                _ControlChip(
                  label: 'Audio',
                  accent: accent,
                  onTap: _showAudioSheet,
                ),
                const SizedBox(width: 8),
                _ControlChip(
                  label: 'Subs',
                  accent: accent,
                  onTap: _showSubtitleSheet,
                ),
                const SizedBox(width: 8),
                _ControlChip(
                  label: 'Sub edit',
                  accent: accent,
                  onTap: _showSubtitleEditSheet,
                ),
                const SizedBox(width: 8),
                _ControlChip(
                  label: 'Quality',
                  accent: accent,
                  onTap: _showQualitySheet,
                ),
                const SizedBox(width: 8),
                _ControlChip(
                  label: 'Episodes',
                  accent: accent,
                  onTap: _showEpisodeSheet,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final int h = d.inHours;
    final String m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

class _TopButton extends StatelessWidget {
  const _TopButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.accent, required this.onRetry});

  final Color accent;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white70,
                size: 44,
              ),
              const SizedBox(height: 16),
              const Text(
                'Trailer unavailable',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The preview sample could not load. Full episodes '
                'arrive in milestone 2.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoplayOverlay extends StatelessWidget {
  const _AutoplayOverlay({
    required this.countdown,
    required this.next,
    required this.accent,
    required this.onPlayNow,
    required this.onCancel,
  });

  final int countdown;
  final Episode? next;
  final Color accent;
  final VoidCallback onPlayNow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 120,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xE617171F),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Up next: Episode ${next?.number ?? ''}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Playing in $countdown s',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ElevatedButton(
                  onPressed: onPlayNow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Play now'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onCancel,
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
