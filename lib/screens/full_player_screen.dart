import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anibee_mpv_pip/anibee_mpv_pip.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models.dart';
import '../player/subtitle_style.dart';
import '../player/trailer_player.dart';
import '../services/anilist_service.dart';
import '../services/aniskip_service.dart';
import '../services/miruro_resolver.dart';
import '../settings_store.dart';
import '../theme.dart';
import '../widgets/poster.dart';
import '../widgets/server_sheet.dart';
import '../widgets/subtitle_overlay.dart';
import '../widgets/top_notification.dart';

/// Right-side slide-over panel kind (0.2.4, Zeus style).
enum _PanelKind { sources, audio, subtitles, quality }

/// Full-screen player (Zeus feature set, AniBee accent).
///
/// - Opens in LANDSCAPE, returns to portrait on close.
/// - Never blank: the anime poster sits behind the video; a loading
///   spinner while the stream buffers; a real error state (poster +
///   message + Retry) when the stream fails to load.
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
/// M2: [stream] is the resolved real stream for [initialEpisode]
/// (Miruro/Anikoto or a Debrid direct link). When the user switches
/// episode inside the player, [onResolveEpisode] resolves the new
/// episode's stream (null = keep playing the current episode).
/// There is no sample fallback any more (0.2.4) — a stream that
/// cannot be resolved shows the error dialog, never a placeholder.
/// The episode after [currentNumber] in [episodes], or null when
/// there is none. Pure — unit-tested. Lookup is BY EPISODE NUMBER,
/// never by identity: `Episode` has no `==` override, so
/// `indexOf(_currentEpisode)` is identity-based, and Detail rebuilds
/// its episode list (0.2.9 thumbnails) while the stream resolves —
/// by push time the initial object may no longer be identical to any
/// list element, `indexOf` returns -1, and the Up-next card never
/// shows (0.2.10: EP 2 restarted at EOF instead of advancing).
Episode? nextEpisodeAfter(List<Episode> episodes, int currentNumber) {
  final int i = episodes.indexWhere((Episode e) => e.number == currentNumber);
  if (i < 0 || i + 1 >= episodes.length) return null;
  return episodes[i + 1];
}

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
    this.resolver,
    this.onServerChanged,
    this.subDub = 'Sub',
    this.currentDebrid,
    this.anilist,
    this.aniSkip,
  });

  final TrailerPlayer trailer;
  final SettingsStore store;
  final Anime anime;
  final List<Episode> episodes;
  final Episode initialEpisode;

  /// AniList service (0.2.4): resolves malId for AniSkip when the
  /// anime has an anilistId but no malId (the local catalogue). Null
  /// in tests — AniSkip is then skipped.
  final AniListService? anilist;

  /// AniSkip service (0.2.4): real Skip Intro/Outro data. Injected
  /// for tests; a real one is created when not passed in.
  final AniSkipService? aniSkip;

  /// Fired when the user jumps to another episode inside the player
  /// (Detail marks progress + list status).
  final ValueChanged<Episode>? onEpisodeChanged;

  /// Resolved real stream for the initial episode (M2).
  final ResolvedStream? stream;

  /// Resolve the stream for a newly selected episode (M2).
  final Future<ResolvedStream?> Function(Episode episode)? onResolveEpisode;

  /// Miruro resolver (shared with Detail) — used to fetch English
  /// subtitles when the playing stream has none. Created on the spot
  /// when not passed in.
  final MiruroResolver? resolver;

  /// Fired when the user picks another server in the player (server
  /// icon in the bottom-right row). Detail updates its preferred
  /// server / debrid choice; the player then re-resolves the current
  /// episode through [onResolveEpisode].
  final Future<void> Function(String server, String subDub, String? debrid)?
  onServerChanged;

  /// Sub/Dub of the current stream + the debrid choice in use (from
  /// Detail) — shown in the in-player server sheet.
  final String subDub;
  final String? currentDebrid;

  @override
  State<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends State<FullPlayerScreen> {
  Player get _player => widget.trailer.player;
  SettingsStore get _store => widget.store;

  late Episode _currentEpisode;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  /// The stream currently playing (M2, null = no stream loaded yet).
  ResolvedStream? _currentStream;

  /// True while a new episode's stream is resolving.
  bool _resolving = false;
  final ValueNotifier<double> _videoScale = ValueNotifier<double>(1.0);

  /// Animated gesture HUD state (volume / brightness / seek).
  final ValueNotifier<_HudState?> _hud = ValueNotifier<_HudState?>(null);
  Timer? _hudHideTimer;

  /// Brightness 0..100 as an overlay dim layer (100 = full bright, no
  /// overlay; 0 = darkest). mpv's `brightness` property is a no-op on
  /// iOS under hwdec (videotoolbox), so the picture is dimmed with a
  /// black overlay instead — it visibly works on every stream.
  final ValueNotifier<double> _brightnessLevel = ValueNotifier<double>(100);
  double _rate = 1.0;

  StreamSubscription<Duration>? _positionSub;
  // 0.2.9: the AniSkip fetch is deferred until the real duration is
  // known — this subscription retries it the moment the duration
  // arrives, instead of waiting for the next position tick (which
  // may be seconds away, or never come if playback stalls).
  StreamSubscription<Duration>? _durationSub;
  // 0.2.10: end-of-episode — fires when mpv reports the media
  // completed, so the end card shows even if no position tick lands
  // in the last 3 s (HLS position jumps) or autoplay is off.
  StreamSubscription<bool>? _completedSub;
  bool _resumeApplied = false;
  bool _autoplayShown = false;
  Timer? _autoplayTimer;
  int _autoplayCountdown = 5;

  /// 0.2.10: the Up-next card is visible independently of the
  /// countdown timer — with autoplay OFF there is no timer, the
  /// player is paused and the card waits for the user. True from
  /// the moment the card is shown until Cancel / Play now / an
  /// episode switch hides it.
  bool _autoplayVisible = false;

  /// 0.2.10: the user explicitly cancelled the card. The
  /// end-of-playback handler must NOT re-show it — Cancel means
  /// "stay on this episode", not "ask me again at EOF".
  bool _autoplayCancelled = false;

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
  double _dragAccumDy = 0;
  double _dragStartVolume = 100;
  double _dragStartBrightnessLevel = 100;
  bool _dragVerticalRight = true;

  // Pinch zoom is tracked with a raw Listener (pointer events), NOT
  // with a ScaleGestureRecognizer: the scale recognizer competes with
  // the drag recognizers in the gesture arena and swallows
  // single-finger drags. The Listener never joins the arena, so
  // vertical/horizontal drags always reach their handlers.
  final Map<int, Offset> _activePointers = <int, Offset>{};
  bool _pinching = false;
  double _pinchBaseDistance = 0;
  double _pinchBaseScale = 1.0;

  /// Hold-to-2x (0.2.8): tap and hold the RIGHT side plays at 2x while
  /// held, releasing restores the previously selected speed. Tracked
  /// in the same raw Listener as pinch zoom (never the gesture
  /// arena), so it cannot disturb double-tap seek or the volume /
  /// brightness swipes: 2x only engages when the finger stays down
  /// without moving for a short hold threshold (400ms), and a quick
  /// second tap is still the +10s seek.
  Timer? _holdTimer;
  Offset? _holdDownPosition;
  int? _holdPointer;
  double? _rateBeforeHold;
  bool _hold2x = false;

  /// When a hold releases, the pointer-up also completes a tap — and
  /// that tap must NOT toggle the controls overlay. The tap fires
  /// within milliseconds of the release (possibly after the
  /// double-tap window), so the toggle ignores any tap inside 500ms
  /// of a hold release.
  DateTime? _holdReleasedAt;

  // 0.2.3 Zeus-layout player state.
  /// Controls locked (lock icon): only the unlock button shows.
  bool _controlsLocked = false;

  /// Video fit, cycled by the aspect-ratio button: Fit → Fill → Stretch.
  BoxFit _videoFit = BoxFit.contain;

  /// Double-tap seek flash: which side + how much, shown briefly.
  /// null side = center play/pause flash.
  bool _seekFlashVisible = false;
  bool? _seekFlashLeft;
  int _seekFlashAmount = 10;
  Timer? _seekFlashTimer;

  /// X of the last double-tap down (onDoubleTap carries no position).
  double _lastDoubleTapX = 0;

  /// English-subtitle fetch (0.2.3): one attempt per loaded stream.
  bool _englishFetchTried = false;

  /// Real AniSkip data for the current episode (0.2.4): null = no
  /// data (not fetched yet, or AniSkip has none for this episode) —
  /// the player then shows NO Skip button at all, never the old
  /// hardcoded 85s jump.
  SkipTimes? _skipTimes;
  int? _skipTimesEpisode;
  int? _resolvedMalId;

  /// 0.2.9: true when a Skip fetch was deferred because the episode
  /// duration was still unknown (stream not loaded yet). `_onPosition`
  /// retries the fetch once the real duration first arrives.
  bool _skipTimesAwaitingDuration = false;

  /// Right-side slide-over panel (0.2.4, Zeus style): null = closed.
  _PanelKind? _panelKind;

  AniSkipService get _aniSkip => widget.aniSkip ?? _fallbackAniSkip;
  late final AniSkipService _fallbackAniSkip;

  /// Test seam: hide the controls overlay without a tap, so a test
  /// can prove a double-tap leaves them hidden.
  @visibleForTesting
  void hideControlsForTest() {
    if (mounted) setState(() => _controlsVisible = false);
  }

  /// Test seam: whether the controls overlay is currently visible.
  @visibleForTesting
  bool get controlsVisibleForTest => _controlsVisible;

  /// Test seam: whether the double-tap seek flash is currently shown.
  @visibleForTesting
  bool get seekFlashVisibleForTest => _seekFlashVisible;

  /// Test seam: whether hold-to-2x is currently engaged.
  @visibleForTesting
  bool get hold2xForTest => _hold2x;

  /// Test seam: the current playback rate (1.0 normally, 2.0 while
  /// holding the right side).
  @visibleForTesting
  double get rateForTest => _rate;

  /// Test seam: show the autoplay-next overlay immediately (the real
  /// trigger is the position stream near the end of an episode).
  @visibleForTesting
  void showAutoplayForTest() {
    if (mounted) _showAutoplayOverlay();
  }

  /// Test seam: drive the end-of-playback path (the real trigger is
  /// mpv's `completed` stream at EOF). The player pauses and the
  /// Up-next card shows — the episode must NOT restart.
  @visibleForTesting
  void simulateEndForTest() {
    if (mounted) _onPlaybackCompleted();
  }

  /// Test seam: whether the autoplay-next overlay is currently shown.
  @visibleForTesting
  bool get autoplayVisibleForTest => _autoplayVisible;

  /// Test seam: the current video scale (pinch zoom, 1.0 = fit).
  @visibleForTesting
  double get videoScaleForTest => _videoScale.value;

  /// Test seam: the episode currently playing.
  @visibleForTesting
  int get currentEpisodeForTest => _currentEpisode.number;

  /// Test seam: whether a Skip Intro/Outro fetch is deferred, waiting
  /// for the episode duration to become known (0.2.9).
  @visibleForTesting
  bool get skipTimesAwaitingDurationForTest => _skipTimesAwaitingDuration;

  /// Test seam: the loaded Skip Intro/Outro data (null = none).
  @visibleForTesting
  SkipTimes? get skipTimesForTest => _skipTimes;

  /// Last periodic progress save (Continue Watching + resume).
  DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);

  MiruroResolver get _resolver => widget.resolver ?? _fallbackResolver;
  late final MiruroResolver _fallbackResolver;

  /// Canonical resume key: the same title opened from Home and from
  /// Search shares one key (see SettingsStore.keyFor).
  String get _resumeKey =>
      _store.resumeKeyFor(widget.anime, _currentEpisode.number);

  Episode? get _nextEpisode =>
      nextEpisodeAfter(widget.episodes, _currentEpisode.number);

  @override
  void initState() {
    super.initState();
    _currentEpisode = widget.initialEpisode;
    _rate = _player.state.rate;
    _fallbackResolver = MiruroResolver();
    _fallbackAniSkip = AniSkipService();

    // Landscape + immersive, like a real video player.
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Hand the shared player to the full screen, apply Settings.
    unawaited(widget.trailer.expandToFull());
    unawaited(widget.trailer.applyHwdec(_store.hwDecoding));
    _applySubtitlePipeline();
    // M2: load the resolved real stream (unmuted) once the surface
    // is ours; the trailer path loads nothing extra.
    if (widget.stream != null) {
      _currentStream = widget.stream;
      unawaited(_loadStream(widget.stream!));
    }

    _positionSub = _player.stream.position.listen(_onPosition);
    _durationSub = _player.stream.duration.listen((Duration d) {
      if (d > Duration.zero) _maybeRetrySkipTimes();
    });
    // 0.2.10: the end-of-episode card must show even when no
    // position tick lands in the last 3 s (HLS jumps) or autoplay
    // is off — mpv's `completed` fires exactly once at EOF.
    _completedSub = _player.stream.completed.listen((bool done) {
      if (done) _onPlaybackCompleted();
    });
    _scheduleHide();
    // 0.2.4: real AniSkip data for the first episode (best-effort,
    // silent — no data simply means no Skip button).
    unawaited(_loadSkipTimes(_currentEpisode));
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completedSub?.cancel();
    _hideTimer?.cancel();
    _holdTimer?.cancel();
    _autoplayTimer?.cancel();
    _seekFlashTimer?.cancel();
    _hudHideTimer?.cancel();
    _videoScale.dispose();
    _brightnessLevel.dispose();
    _hud.dispose();
    _saveProgress();
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
      final double? saved = _store.resumePositionFor(
        widget.anime,
        _currentEpisode.number,
      );
      if (saved != null && saved > 10 && saved < duration.inSeconds - 20) {
        unawaited(_player.seek(Duration(seconds: saved.round())));
      }
    }
    // Periodic progress save (Continue Watching + resume): every 30 s
    // while playing, so a background kill / crash doesn't lose the
    // position — dispose() alone was not enough.
    if (_player.state.playing &&
        position.inSeconds > 5 &&
        DateTime.now().difference(_lastProgressSave).inSeconds >= 30) {
      _lastProgressSave = DateTime.now();
      _saveProgress();
    }
    // 0.2.9: the AniSkip fetch was deferred until the real duration
    // was known — retry once now that it has arrived.
    _maybeRetrySkipTimes();
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

  /// Save the current position: resume key (canonical — Home and
  /// Search share it) + the real Continue Watching entry. Called on
  /// pause, periodically while playing, on episode switch and on exit.
  ///
  /// 0.2.5: three cases, so the episode list can show real progress:
  /// - mid-episode: save resume position + duration + CW entry.
  /// - watched to the end (last 20 s): clear the resume, mark the
  ///   episode completed, CW entry at 100%.
  /// - barely started: clear the resume, mark nothing.
  void _saveProgress() {
    final Duration pos = _player.state.position;
    final Duration dur = _player.state.duration;
    if (dur.inSeconds <= 30) {
      // Too short to judge: only a mid position counts, never
      // completed.
      if (pos.inSeconds > 10 && pos < dur - const Duration(seconds: 20)) {
        _saveInProgress(pos, dur);
      }
      return;
    }
    if (pos.inSeconds > 10 && pos < dur - const Duration(seconds: 20)) {
      _saveInProgress(pos, dur);
    } else if (pos >= dur - const Duration(seconds: 20)) {
      unawaited(_store.clearResumeSeconds(_resumeKey));
      unawaited(_store.clearResumeDuration(_resumeKey));
      unawaited(_store.markEpisodeCompleted(_resumeKey));
      unawaited(
        _store.recordWatch(
          anime: widget.anime,
          episode: _currentEpisode.number,
          positionSeconds: dur.inSeconds.toDouble(),
          durationSeconds: dur.inSeconds.toDouble(),
        ),
      );
    } else {
      unawaited(_store.clearResumeSeconds(_resumeKey));
    }
  }

  void _saveInProgress(Duration pos, Duration dur) {
    unawaited(_store.setResumeSeconds(_resumeKey, pos.inSeconds.toDouble()));
    unawaited(_store.setResumeDuration(_resumeKey, dur.inSeconds.toDouble()));
    unawaited(
      _store.recordWatch(
        anime: widget.anime,
        episode: _currentEpisode.number,
        positionSeconds: pos.inSeconds.toDouble(),
        durationSeconds: dur.inSeconds.toDouble(),
      ),
    );
  }

  // ------------------------------------------------------- subtitle styling

  /// Best-effort mpv property set (Zeus pattern): the public Player has
  /// no setProperty — the native platform player does. Never throws, so
  /// a styling/brightness set can never break playback. Returns false
  /// when the set did not go through (not a NativePlayer, or the
  /// platform call threw) so the caller can retry.
  static Future<bool> _setMpvProperty(
    Player player,
    String key,
    String value,
  ) async {
    final PlatformPlayer? platform = player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty(key, value);
        return true;
      } catch (_) {
        // Best-effort only.
        return false;
      }
    }
    return false;
  }

  /// Builds the mpv subtitle pipeline map from the current store
  /// values: only `sub-delay` and `sub-codepage` are ever written
  /// to mpv now (0.2.7 — see the header of
  /// `lib/player/subtitle_style.dart` for why the other `sub-*`
  /// options can never affect the picture).
  Map<String, String> _subtitlePipelineProps() {
    return buildSubtitlePipelineProperties(
      subDelayMs: _store.subDelayMs,
      subEncoding: _store.subEncoding,
    );
  }

  /// 0.2.7: the subtitle style lives in the Flutter overlay
  /// (`SubtitleOverlay`, driven by the store — no mpv write can
  /// change it), so the only mpv writes left are the pipeline ones:
  /// `sub-delay` (proven on the VM with real mpv: it shifts the
  /// `sub-text` emission the overlay reads) and `sub-codepage`
  /// (read when the subtitle file is (re)loaded). Best-effort;
  /// never throws, never touches the UI.
  void _applySubtitlePipeline() {
    unawaited(_applySubtitlePipelineOnce());
  }

  Future<void> _applySubtitlePipelineOnce() async {
    try {
      final Map<String, String> props = _subtitlePipelineProps();
      await Future.wait(<Future<bool>>[
        for (final MapEntry<String, String> entry in props.entries)
          _setMpvProperty(_player, entry.key, entry.value),
      ]);
    } catch (_) {
      // Best-effort only.
    }
  }

  /// Re-select the current subtitle track so a new sub-codepage takes
  /// effect: mpv only reads the encoding when the subtitle file is
  /// (re)loaded, so changing Encoding mid-playback otherwise does
  /// nothing until the next episode. Best-effort; playback continues
  /// either way.
  Future<void> _reloadSubtitleTrack() async {
    final SubtitleTrack current = _player.state.track.subtitle;
    if (current.id == 'no' || current.id == 'auto') return;
    try {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      await _player.setSubtitleTrack(current);
      _applySubtitlePipeline();
    } catch (_) {
      // Best-effort only.
    }
  }

  /// The overlay's style + position, from the current store values
  /// (same values the panel preview shows, so the panel and the
  /// picture can never drift apart).
  TextStyle _subtitleOverlayStyle() {
    final Color color =
        kSubtitleColors[_store.subColorIndex.clamp(
          0,
          kSubtitleColors.length - 1,
        )];
    return buildSubtitleOverlayStyle(
      subSize: _store.subSize,
      subFont: _store.subFont,
      subColor: color,
      subOpacity: _store.subOpacity,
      subBold: _store.subBold,
      subOutline: _store.subOutline,
      subBackgroundMode: _store.subBackgroundMode,
    );
  }

  Alignment _subtitleOverlayAlignment() {
    return subtitleOverlayAlignment(
      subPosition: _store.subPosition,
      subAutoAdjust: _store.subAutoAdjust,
      subManualPercent: _store.subManualPercent,
      controlsVisible: _controlsVisible,
    );
  }

  /// The on-screen subtitle overlay (0.2.7): the app renders
  /// `player.stream.subtitle` itself, styled from the store.
  /// Rebuilds live when the store changes (ListenableBuilder) and
  /// when the controls show/hide (parent setState re-runs the
  /// builder). Never blocks input.
  Widget _buildSubtitleOverlay() {
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: _store,
        builder: (BuildContext context, Widget? _) {
          return StreamBuilder<List<String>>(
            stream: _player.stream.subtitle,
            initialData: _player.state.subtitle,
            builder: (BuildContext context, AsyncSnapshot<List<String>> snap) {
              if (_player.state.track.subtitle.id == 'no') {
                return const SizedBox.shrink();
              }
              return SubtitleOverlay(
                lines: snap.data ?? _player.state.subtitle,
                style: _subtitleOverlayStyle(),
                alignment: _subtitleOverlayAlignment(),
              );
            },
          );
        },
      ),
    );
  }

  // -------------------------------------------- subtitle diagnostics (0.2.7)

  /// Diagnostic readout shown in the Subtitles panel (0.2.7): the
  /// active track, its codec as mpv reports it, and the mpv
  /// rendering state — the only way the next phone test can tell
  /// whether the subtitle pipeline is what the panel claims.
  /// The mpv readback runs only once the player is actually running
  /// (duration known): `getProperty` before init passes a null
  /// handle to native code and segfaults (0.2.6), and it is
  /// time-boxed so it can never stall the UI. '—' = not available.
  String _diagTrack = '—';
  String _diagCodec = '—';
  String _diagSubVisibility = '—';
  String _diagSubAss = '—';

  Future<void> _loadSubtitleDiagnostics() async {
    final SubtitleTrack current = _player.state.track.subtitle;
    final String trackLine = current.id == 'no'
        ? 'Off'
        : '${current.title ?? 'Subtitle'}'
              ' (${current.language ?? '?'}) · ${_shortId(current.id)}';
    if (mounted) setState(() => _diagTrack = trackLine);
    if (_player.state.duration <= Duration.zero) return;
    final PlatformPlayer? platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      final String vis = await platform
          .getProperty('sub-visibility')
          .timeout(const Duration(seconds: 2));
      final String ass = await platform
          .getProperty('sub-ass')
          .timeout(const Duration(seconds: 2));
      String codec = '—';
      try {
        final String trackList = await platform
            .getProperty('track-list')
            .timeout(const Duration(seconds: 2));
        codec = _codecFromTrackList(trackList, current);
      } catch (_) {
        // Codec stays '—'.
      }
      if (!mounted) return;
      setState(() {
        _diagSubVisibility = vis;
        _diagSubAss = ass;
        _diagCodec = codec;
      });
    } catch (_) {
      // Readback unavailable — the track line above still shows.
    }
  }

  static String _shortId(String id) {
    if (id.length <= 40) return id;
    return '…${id.substring(id.length - 40)}';
  }

  /// Codec of the active subtitle track from mpv's `track-list`
  /// JSON: prefer the entry whose title matches the current track,
  /// else the first subtitle entry, else '—'. mpv track ids are
  /// ints; media_kit external-track ids are URLs, so the match is
  /// by title, not id.
  static String _codecFromTrackList(String json, SubtitleTrack current) {
    try {
      final dynamic decoded = jsonDecode(json);
      if (decoded is! List) return '—';
      final List<Map<String, dynamic>> subs = <Map<String, dynamic>>[
        for (final dynamic e in decoded)
          if (e is Map<String, dynamic> && e['type'] == 'sub') e,
      ];
      if (subs.isEmpty) return '—';
      final String title = (current.title ?? '').trim().toLowerCase();
      for (final Map<String, dynamic> e in subs) {
        final String t = (e['title'] as String? ?? '').trim().toLowerCase();
        if (title.isNotEmpty && t == title) {
          return (e['codec'] as String? ?? '—').toString();
        }
      }
      return (subs.first['codec'] as String? ?? '—').toString();
    } catch (_) {
      return '—';
    }
  }

  // ---------------------------------------------------------- AniSkip (0.2.4)

  /// Fetch real Skip Intro / Skip Outro segments for an episode.
  /// AniSkip needs a MAL id: the anime's own, else resolved from its
  /// AniList id (one GraphQL call, cached for the title). No id, no
  /// service, or no AniSkip data -> null, and the player shows no
  /// Skip button. Never throws.
  ///
  /// 0.2.9: (1) AniSkip 400s without `episodeLength` ("Validation
  /// failed: episodeLength NaN"), and the duration is usually still
  /// 0 when this runs at init / episode switch — so the fetch is now
  /// DEFERRED until the real duration is known and never sent
  /// without it; `_onPosition` retries once the duration arrives.
  /// (2) Most catalogue titles have neither a malId nor an
  /// anilistId, so the fetch never started at all — the AniList id
  /// is now resolved by title first (same helper as the season
  /// selector), then the MAL id from it.
  Future<void> _loadSkipTimes(Episode episode) async {
    if (_skipTimesEpisode == episode.number && _skipTimes != null) return;
    _skipTimesEpisode = episode.number;
    int? malId = widget.anime.malId ?? _resolvedMalId;
    if (malId == null) {
      int? anilistId = widget.anime.anilistId;
      anilistId ??= await widget.anilist?.resolveId(widget.anime.title);
      if (anilistId != null) {
        try {
          final Anime? full = await widget.anilist?.mediaById(anilistId);
          malId = full?.malId;
          if (malId != null) _resolvedMalId = malId;
        } catch (_) {
          malId = null;
        }
      }
    }
    if (malId == null) return;
    final int duration = _player.state.duration.inSeconds;
    if (duration <= 0) {
      // Duration not known yet (stream still loading): do NOT fetch
      // without episodeLength — AniSkip 400s. `_onPosition` retries
      // once the duration arrives.
      _skipTimesAwaitingDuration = true;
      return;
    }
    _skipTimesAwaitingDuration = false;
    final SkipTimes? times = await _aniSkip.fetchSkipTimes(
      malId: malId,
      episode: episode.number,
      episodeLength: duration,
    );
    if (!mounted || _skipTimesEpisode != episode.number) return;
    setState(() => _skipTimes = times);
  }

  /// 0.2.9: the AniSkip fetch was deferred until the real duration
  /// was known — retry once now that it has arrived. Called from
  /// `_onPosition` (every position update carries the duration).
  void _maybeRetrySkipTimes() {
    if (_skipTimesAwaitingDuration &&
        _player.state.duration.inSeconds > 0) {
      _skipTimesAwaitingDuration = false;
      unawaited(_loadSkipTimes(_currentEpisode));
    }
  }

  // ------------------------------------------------------------- controls

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 3000), () {
      if (mounted && _player.state.playing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  /// Single-tap toggle (0.2.5): one tap hides ALL controls, the next
  /// shows them again. The root GestureDetector already
  /// disambiguates: onTap fires only once the double-tap window has
  /// passed, so a double-tap's first tap never toggles. Showing
  /// restarts the 3 s auto-hide; hiding cancels it — hidden stays
  /// hidden until the next tap.
  ///
  /// 0.2.8: a tap that ends a hold-to-2x is ignored — the release
  /// itself is the "stop 2x" action, not a request to toggle the
  /// overlay (see [_holdReleasedAt]).
  void _toggleControls() {
    if (_holdReleasedAt != null &&
        DateTime.now().difference(_holdReleasedAt!).inMilliseconds < 500) {
      _holdReleasedAt = null;
      return;
    }
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _pokeControls();
    }
  }

  /// Cancel a pending hold-to-2x (finger moved, second finger down,
  /// or a drag started).
  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdDownPosition = null;
    _holdPointer = null;
  }

  /// Engage 2x: only when the same single finger is still down on
  /// the right side after the hold threshold.
  void _engageHold2x() {
    _holdTimer = null;
    if (_hold2x || _pinching || _activePointers.length != 1) return;
    final Offset? down = _holdDownPosition;
    if (down == null) return;
    final double w = MediaQuery.of(context).size.width;
    if (down.dx <= w / 2) return;
    _rateBeforeHold = _rate;
    setState(() {
      _rate = 2.0;
      _hold2x = true;
    });
    unawaited(_player.setRate(2.0));
  }

  /// Release 2x: restore the speed the user had selected before the
  /// hold — never a hardcoded 1x.
  void _disengageHold2x() {
    if (!_hold2x) return;
    final double restore = _rateBeforeHold ?? 1.0;
    _rateBeforeHold = null;
    _holdReleasedAt = DateTime.now();
    setState(() {
      _rate = restore;
      _hold2x = false;
    });
    unawaited(_player.setRate(restore));
  }

  /// Show the controls overlay (single tap, button taps, episode
  /// switches). Double-tap handlers pass `showControls: false`:
  /// a double-tap must ONLY seek / play-pause and leave the overlay
  /// exactly as was (0.2.4 — the old code called this from
  /// _seekBy/_togglePlay, so every double-tap flashed the overlay).
  void _pokeControls({bool showControls = true}) {
    if (showControls && !_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _scheduleHide();
  }

  Future<void> _togglePlay({bool showControls = true}) async {
    _pokeControls(showControls: showControls);
    if (_player.state.playing) {
      await _player.pause();
      // Pausing saves progress right away (Continue Watching + resume).
      _saveProgress();
    } else {
      await _player.play();
    }
  }

  Future<void> _seekBy(
    int seconds, {
    bool showFlash = false,
    bool showControls = true,
  }) async {
    final Duration pos = _player.state.position;
    final Duration dur = _player.state.duration;
    Duration target = pos + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > dur) target = dur;
    // Feedback FIRST, seek second: the flash is the user's proof the
    // tap worked, and it must not wait on the seek round-trip (a
    // slow network stream would otherwise leave the tap feeling
    // dead). The seek itself stays best-effort below.
    if (showFlash) _flashSeek(seconds < 0, seconds.abs());
    _pokeControls(showControls: showControls);
    // Best-effort: a rejected seek (no media yet, live edge) must
    // never break the gesture — the flash is the feedback either way.
    try {
      await _player.seek(target);
    } catch (_) {}
  }

  /// Double-tap seek flash: a brief "-10s" / "+10s" badge on the
  /// tapped side (center = play/pause flash). This is what makes the
  /// double-tap feel like it worked — 0.2.1 sought silently.
  void _flashSeek(bool left, int amount) {
    _seekFlashTimer?.cancel();
    setState(() {
      _seekFlashVisible = true;
      _seekFlashLeft = left;
      _seekFlashAmount = amount;
    });
    _seekFlashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekFlashVisible = false);
    });
  }

  void _flashPlayPause() {
    _seekFlashTimer?.cancel();
    setState(() {
      _seekFlashVisible = true;
      _seekFlashLeft = null;
    });
    _seekFlashTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _seekFlashVisible = false);
    });
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
    await widget.trailer.loadStream(
      stream,
      subtitleLanguage: _store.subtitleLanguage,
    );
    _englishFetchTried = false;
    unawaited(_maybeFetchEnglishSubtitles(stream));
  }

  /// When the playing stream carries no English subtitles (0.2.1:
  /// JJK's stream had Arabic only), fetch English tracks for the
  /// episode from the justanime providers and add the first one.
  /// Best-effort and silent — the sheet keeps working either way.
  Future<void> _maybeFetchEnglishSubtitles(ResolvedStream stream) async {
    if (_englishFetchTried) return;
    _englishFetchTried = true;
    final String lang = _store.subtitleLanguage;
    if (lang == 'off' || (lang != 'auto' && lang != 'en')) return;
    if (stream.subtitles.any(
      (SubtitleInfo s) => MiruroResolver.isEnglishLabel(s.label),
    )) {
      return;
    }
    // Let mpv's own (HLS rendition) tracks arrive first.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    final bool mpvHasEnglish = _player.state.tracks.subtitle.any(
      (SubtitleTrack t) =>
          MiruroResolver.isEnglishLabel(t.title) ||
          (t.language ?? '').toLowerCase().startsWith('en'),
    );
    if (mpvHasEnglish) return;
    final List<SubtitleInfo> fetched = await _resolver.fetchSubtitlesOnly(
      anime: widget.anime,
      episodeNumber: _currentEpisode.number,
    );
    if (!mounted) return;
    final SubtitleInfo? english = fetched
        .where((SubtitleInfo s) => MiruroResolver.isEnglishLabel(s.label))
        .firstOrNull;
    if (english == null) return;
    if (_player.state.tracks.subtitle.any(
      (SubtitleTrack t) => MiruroResolver.isEnglishLabel(t.title),
    )) {
      return;
    }
    await widget.trailer.addExternalSubtitle(english);
    if (mounted) setState(() {});
  }

  void _selectEpisode(Episode episode) {
    if (episode.number == _currentEpisode.number) return;
    final Episode previous = _currentEpisode;
    // Save the old episode's position before leaving it.
    _saveProgress();
    setState(() {
      _currentEpisode = episode;
      _autoplayShown = false;
      _autoplayVisible = false;
      _autoplayCancelled = false;
      _autoplayTimer?.cancel();
      _autoplayTimer = null;
      _resumeApplied = true; // resume handled inline below
    });
    widget.onEpisodeChanged?.call(episode);
    // 0.2.4: real AniSkip data for the new episode.
    unawaited(_loadSkipTimes(episode));
    // M2: a real stream per episode — resolve the new one. Failure
    // keeps the current episode playing (never a blank screen).
    if (widget.onResolveEpisode != null) {
      unawaited(_switchToEpisode(episode, previous));
      return;
    }
    final double? saved = _store.resumePositionFor(
      widget.anime,
      episode.number,
    );
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
    final double? saved = _store.resumePositionFor(
      widget.anime,
      episode.number,
    );
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

  /// End of playback (mpv `completed` at EOF, 0.2.10): the player
  /// PAUSES and the Up-next card shows — the episode NEVER restarts.
  /// (Before this, `PlaylistMode.single` looped the media, so EP 2
  /// silently replayed from 00:00 and no card ever appeared.)
  /// - The early card is already up (autoplay ON, countdown
  ///   running): nothing to do — the timer advances as usual.
  /// - The user cancelled the early card: respect it, stay paused
  ///   with no card.
  /// - Otherwise (autoplay OFF, or the early trigger never fired):
  ///   show the card — WITH the 5 s countdown when autoplay is on,
  ///   paused with NO countdown when it is off, waiting for the user.
  /// - No next episode (last one): just pause, no card.
  void _onPlaybackCompleted() {
    if (!mounted) return;
    unawaited(_player.pause());
    _saveProgress();
    _pokeControls();
    if (_autoplayShown || _autoplayCancelled) return;
    if (_nextEpisode == null) return;
    _autoplayShown = true;
    _showAutoplayOverlay(withCountdown: _store.autoplayNext);
  }

  void _showAutoplayOverlay({bool withCountdown = true}) {
    _autoplayCountdown = 5;
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
    if (withCountdown) {
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
    }
    _autoplayVisible = true;
    setState(() {});
  }

  // ------------------------------------------------------------------- PiP

  /// 0.2.9: the ONE short line the user ever sees when PiP fails.
  /// The raw native diagnostic (PGPegasusErrorDomain … + the diag
  /// counters) goes to the log only — never to the banner.
  static const String _pipFailedMessage = 'PiP nahi khula — dobara try karo.';

  /// Test seam: the short PiP-failure line (the raw native diagnostic
  /// must never reach the user).
  @visibleForTesting
  String get pipFailedMessageForTest => _pipFailedMessage;

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
    // The main player keeps playing until the PiP layer is primed —
    // pausing it first would freeze the picture for the whole wait.
    final bool wasPlaying = _player.state.playing;
    final AnibeeMpvPip bridge = AnibeeMpvPip();
    Player? pipPlayerForCleanup;
    try {
      final Player pipPlayer = Player();
      pipPlayerForCleanup = pipPlayer;
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
        Media(
          url,
          httpHeaders: _currentStream?.headers ?? const <String, String>{},
        ),
      );
      await pipPlayer.seek(pos);
      await pipPlayer.setVolume(_player.state.volume);
      await pipPlayer.setRate(_rate);
      await pipPlayer.play();

      bridge.onPipStarted = () {
        if (mounted) setState(() => _inPip = true);
      };
      bridge.onPipStopped = (bool restored) async {
        await _restoreFromPip();
      };
      bridge.onPipFailed = (String reason) async {
        debugPrint('Anibee PiP failed: $reason');
        if (mounted) _snack(_pipFailedMessage);
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
      // 0.2.9: do NOT enter until the layer holds a frame. The Swift
      // side polls only ~3 s for `possible`, and the pip player's
      // first frame (HLS open + seek + decode) routinely takes
      // longer — the old code entered immediately and failed with
      // primed=false / ingest=0. Wait here (main player still
      // playing); on timeout fail short and leave the main player
      // exactly as it was.
      if (!await bridge.waitForPrime()) {
        String diag = '';
        try {
          diag = await bridge.diag;
        } catch (_) {}
        debugPrint('Anibee PiP never primed: $diag');
        await bridge.dispose();
        await pipPlayer.dispose();
        if (mounted) _snack(_pipFailedMessage);
        return;
      }
      await _player.pause();
      // Refresh the scrubber position: it advanced while we waited.
      await bridge.updateState(
        position: _player.state.position,
        duration: _player.state.duration,
        playing: true,
        rate: _rate,
      );
      final bool ok = await bridge.enterPiP();
      if (!ok) {
        // Start refused even primed: resume the main player — the
        // old code left it paused with no window.
        await bridge.dispose();
        await pipPlayer.dispose();
        if (wasPlaying) await _player.play();
        if (mounted) _snack(_pipFailedMessage);
        return;
      }
      _pipPlayer = pipPlayer;
      _pipController = pipController;
      _pipBridge = bridge;
    } catch (e) {
      debugPrint('Anibee PiP failed: $e');
      await bridge.dispose();
      await pipPlayerForCleanup?.dispose();
      if (wasPlaying && !_player.state.playing) {
        await _player.play();
      }
      if (mounted) _snack(_pipFailedMessage);
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
    TopNotification.show(context, message);
  }

  // ---------------------------------------------------------------- sheets

  // ---------------------------------------------------------------- panels
  // 0.2.4: Sources / Audio / Subtitles / Quality open as RIGHT-SIDE
  // slide-over panels (Zeus style, ~42% width, dark glossy), not
  // bottom sheets. Volume + Episode stay bottom sheets. Opening a
  // panel keeps the controls visible — no auto-hide while it is open.

  void _openPanel(_PanelKind kind) {
    setState(() {
      _panelKind = kind;
      _controlsVisible = true;
    });
    _hideTimer?.cancel();
    if (kind == _PanelKind.subtitles) {
      unawaited(_loadSubtitleDiagnostics());
    }
  }

  void _closePanel() {
    setState(() => _panelKind = null);
    _scheduleHide();
  }

  void _showAudioPanel() => _openPanel(_PanelKind.audio);

  void _showSubtitlesPanel() => _openPanel(_PanelKind.subtitles);

  void _showSourcesPanel() => _openPanel(_PanelKind.sources);

  void _showQualityPanel() => _openPanel(_PanelKind.quality);

  /// The right-side slide-over panel: a dim scrim on the left (tap
  /// to close) and the dark glossy panel on the right. Rendered above
  /// the controls in the build stack, independent of the controls'
  /// auto-hide.
  Widget _buildSidePanel(Color accent) {
    final _PanelKind kind = _panelKind!;
    final String title = switch (kind) {
      _PanelKind.sources => 'Sources',
      _PanelKind.audio => 'Audio',
      _PanelKind.subtitles => 'Subtitles',
      _PanelKind.quality => 'Quality',
    };
    final Widget content = switch (kind) {
      _PanelKind.sources => _buildSourcesPanelContent(),
      _PanelKind.audio => _buildAudioPanelContent(accent),
      _PanelKind.subtitles => _buildSubtitlesPanelContent(accent),
      _PanelKind.quality => _buildQualityPanelContent(accent),
    };
    return Positioned.fill(
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closePanel,
              child: Container(color: Colors.black.withValues(alpha: 0.35)),
            ),
          ),
          Container(
            width: MediaQuery.of(context).size.width * 0.42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xFF23232F), Color(0xFF121218)],
              ),
              border: Border(
                left: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                        ),
                        onPressed: _closePanel,
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF2A2A35), height: 1),
                Expanded(child: content),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sources panel: the same server picker as the detail screen's
  /// bottom sheet, as a single-column list (ServerSheetBody compact).
  Widget _buildSourcesPanelContent() {
    final String? currentDebrid = _currentStream?.source == 'TorBox'
        ? 'torbox'
        : _currentStream?.source == 'Real-Debrid'
        ? 'realdebrid'
        : widget.currentDebrid;
    return ServerSheetBody(
      store: _store,
      currentServer: _store.preferredServer,
      subDub: widget.subDub,
      currentDebrid: currentDebrid,
      compact: true,
      onPick: (({String server, String subDub, String? debrid}) result) {
        _closePanel();
        unawaited(_applyServerPick(result));
      },
      onClose: _closePanel,
    );
  }

  /// In-player server switch (server icon in the bottom row): pick
  /// another server (or debrid) for THIS episode, then re-resolve the
  /// current episode through Detail's resolver and reload it at the
  /// same position.
  Future<void> _applyServerPick(
    ({String server, String subDub, String? debrid}) picked,
  ) async {
    final String currentServer = _store.preferredServer;
    final String? currentDebrid = _currentStream?.source == 'TorBox'
        ? 'torbox'
        : _currentStream?.source == 'Real-Debrid'
        ? 'realdebrid'
        : widget.currentDebrid;
    if (picked.server == currentServer && picked.debrid == currentDebrid) {
      return;
    }
    final Duration pos = _player.state.position;
    await widget.onServerChanged?.call(
      picked.server,
      picked.subDub,
      picked.debrid,
    );
    if (!mounted || widget.onResolveEpisode == null) return;
    setState(() => _resolving = true);
    final ResolvedStream? stream = await widget.onResolveEpisode!(
      _currentEpisode,
    );
    if (!mounted) return;
    setState(() => _resolving = false);
    if (stream == null) {
      _snack('Could not find sources on ${picked.server}');
      return;
    }
    _currentStream = stream;
    await _loadStream(stream);
    if (!mounted) return;
    unawaited(_player.seek(pos));
    unawaited(_player.play());
    _pokeControls();
  }

  /// Audio panel: Auto + the stream's audio tracks + Off, with an
  /// accent radio for the selected one. Picking a track applies it
  /// immediately and keeps the panel open.
  Widget _buildAudioPanelContent(Color accent) {
    final Tracks tracks = _player.state.tracks;
    final String currentId = _player.state.track.audio.id;
    final List<AudioTrack> list = tracks.audio
        .where((AudioTrack t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final List<({String id, String label, AudioTrack track})> entries =
        <({String id, String label, AudioTrack track})>[
          (id: 'auto', label: 'Auto', track: AudioTrack.auto()),
          ...list.map(
            (AudioTrack t) => (
              id: t.id,
              label: _trackLabel(t.title, t.language, 'Track'),
              track: t,
            ),
          ),
          (id: 'no', label: 'Off', track: AudioTrack.no()),
        ];
    return ListView(
      children: <Widget>[
        _panelSectionHeader('TRACKS'),
        for (final entry in entries)
          _panelTrackRow(
            label: entry.label,
            selected: entry.id == currentId,
            accent: accent,
            onTap: () async {
              await _player.setAudioTrack(entry.track);
              if (mounted) setState(() {});
              _pokeControls();
            },
          ),
      ],
    );
  }

  /// Subtitles panel (Zeus style): track list (Off + every mpv /
  /// fetched track) + "Load subtitle file" + the full style editor
  /// (size, colour, font, bold, background, outline, position,
  /// opacity, encoding, auto-adjust, manual position, delay) with a
  /// live preview. Every style option drives the app's own subtitle
  /// overlay directly (0.2.7 — mpv never renders subtitles with
  /// libass: false, so the old sub-* writes could never change the
  /// picture); only Delay (sub-delay shifts the sub-text timing)
  /// and Encoding (sub-codepage) still write to mpv.
  Widget _buildSubtitlesPanelContent(Color accent) {
    return ListenableBuilder(
      listenable: _store,
      builder: (BuildContext context, Widget? _) {
        final Tracks tracks = _player.state.tracks;
        final String currentId = _player.state.track.subtitle.id;
        // mpv's own tracks (incl. HLS rendition subtitles) + the
        // tracks the resolver fetched for this episode (e.g. English
        // when the stream only carried Arabic) — deduped by id.
        final List<SubtitleTrack> list = tracks.subtitle
            .where((SubtitleTrack t) => t.id != 'auto' && t.id != 'no')
            .toList();
        for (final SubtitleTrack t in widget.trailer.streamSubtitles) {
          if (!list.any((SubtitleTrack m) => m.id == t.id)) list.add(t);
        }
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _panelSectionHeader('TRACKS'),
              _panelTrackRow(
                label: 'Off',
                selected: currentId == 'no',
                accent: accent,
                onTap: () async {
                  await _player.setSubtitleTrack(SubtitleTrack.no());
                  if (mounted) setState(() {});
                },
              ),
              for (final SubtitleTrack t in list)
                _panelTrackRow(
                  label: _trackLabel(t.title, t.language, 'Subtitle'),
                  selected: t.id == currentId,
                  accent: accent,
                  onTap: () async {
                    await _player.setSubtitleTrack(t);
                    if (mounted) setState(() {});
                    unawaited(_loadSubtitleDiagnostics());
                  },
                ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: Icon(Icons.upload_file_rounded, color: accent),
                title: const Text(
                  'Load subtitle file',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: const Text(
                  '.srt / .ass / .vtt from Files',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () => unawaited(_loadSubtitleFile()),
              ),
              const Divider(color: Color(0xFF2A2A35)),
              _panelSectionHeader('SUBTITLE STYLE'),
              _buildSubtitlePreview(),
              const SizedBox(height: 6),
              _stepperRow(
                label: 'Text size',
                value: _store.subSize.round().toString(),
                onMinus: () {
                  unawaited(
                    _store.setSubSize((_store.subSize - 1).clamp(12, 28)),
                  );
                },
                onPlus: () {
                  unawaited(
                    _store.setSubSize((_store.subSize + 1).clamp(12, 28)),
                  );
                },
              ),
              _dropdownRow<int>(
                label: 'Text colour',
                value: _store.subColorIndex,
                items: <DropdownMenuItem<int>>[
                  for (int i = 0; i < kSubtitleColors.length; i++)
                    DropdownMenuItem<int>(
                      value: i,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: kSubtitleColors[i],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(kSubtitleColorNames[i]),
                        ],
                      ),
                    ),
                ],
                onChanged: (int? i) {
                  if (i == null) return;
                  unawaited(_store.setSubColorIndex(i));
                },
              ),
              _dropdownRow<String>(
                label: 'Font',
                value: _store.subFont,
                items: <DropdownMenuItem<String>>[
                  for (final String f in <String>[
                    'Inter Semibold',
                    'System',
                    'Rounded',
                    'Mono',
                  ])
                    DropdownMenuItem<String>(value: f, child: Text(f)),
                ],
                onChanged: (String? f) {
                  if (f == null) return;
                  unawaited(_store.setSubFont(f));
                },
              ),
              _toggleRow(
                label: 'Bold',
                value: _store.subBold,
                accent: accent,
                onChanged: (bool v) {
                  unawaited(_store.setSubBold(v));
                },
              ),
              _dropdownRow<String>(
                label: 'Background',
                value: _store.subBackgroundMode,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: 'off', child: Text('Off')),
                  DropdownMenuItem<String>(value: 'dark', child: Text('Dark')),
                  DropdownMenuItem<String>(
                    value: 'solid',
                    child: Text('Solid'),
                  ),
                ],
                onChanged: (String? m) {
                  if (m == null) return;
                  unawaited(_store.setSubBackgroundMode(m));
                },
              ),
              _dropdownRow<String>(
                label: 'Outline',
                value: _store.subOutline,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: 'none', child: Text('None')),
                  DropdownMenuItem<String>(value: 'thin', child: Text('Thin')),
                  DropdownMenuItem<String>(
                    value: 'medium',
                    child: Text('Medium'),
                  ),
                  DropdownMenuItem<String>(
                    value: 'thick',
                    child: Text('Thick'),
                  ),
                ],
                onChanged: (String? o) {
                  if (o == null) return;
                  unawaited(_store.setSubOutline(o));
                },
              ),
              _dropdownRow<String>(
                label: 'Position',
                value: _store.subPosition,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                    value: 'Bottom',
                    child: Text('Bottom'),
                  ),
                  DropdownMenuItem<String>(
                    value: 'Middle',
                    child: Text('Middle'),
                  ),
                  DropdownMenuItem<String>(value: 'Top', child: Text('Top')),
                ],
                onChanged: (String? p) {
                  if (p == null) return;
                  unawaited(_store.setSubPosition(p));
                },
              ),
              _stepperRow(
                label: 'Text opacity',
                value: '${_store.subOpacity}%',
                onMinus: () {
                  unawaited(_store.setSubOpacity(_store.subOpacity - 5));
                },
                onPlus: () {
                  unawaited(_store.setSubOpacity(_store.subOpacity + 5));
                },
              ),
              _dropdownRow<String>(
                label: 'Encoding',
                value: _store.subEncoding,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(value: 'auto', child: Text('Auto')),
                  DropdownMenuItem<String>(
                    value: 'utf-8',
                    child: Text('UTF-8'),
                  ),
                  DropdownMenuItem<String>(
                    value: 'windows-1252',
                    child: Text('Windows-1252'),
                  ),
                  DropdownMenuItem<String>(
                    value: 'windows-1251',
                    child: Text('Windows-1251'),
                  ),
                  DropdownMenuItem<String>(
                    value: 'iso-8859-1',
                    child: Text('ISO-8859-1'),
                  ),
                  DropdownMenuItem<String>(
                    value: 'shift_jis',
                    child: Text('Shift_JIS'),
                  ),
                ],
                onChanged: (String? e) {
                  if (e == null) return;
                  unawaited(_store.setSubEncoding(e));
                  _applySubtitlePipeline();
                  // sub-codepage only takes effect when the subtitle
                  // file is (re)loaded — re-select the track so the
                  // new encoding applies live.
                  unawaited(_reloadSubtitleTrack());
                },
              ),
              _toggleRow(
                label: 'Auto-Adjust',
                value: _store.subAutoAdjust,
                accent: accent,
                onChanged: (bool v) {
                  unawaited(_store.setSubAutoAdjust(v));
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        'Manual position',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                    Text(
                      '${_store.subManualPercent.round()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        unawaited(_store.setSubManualPercent(0));
                      },
                      child: Text(
                        'Reset',
                        style: TextStyle(color: accent, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              Slider(
                value: _store.subManualPercent,
                min: 0,
                max: 100,
                activeColor: accent,
                // 0.2.5: always draggable — dragging IS manual mode,
                // so it turns Auto-Adjust off. Before, the slider
                // was disabled while auto-adjust was on (the
                // default), so out of the box it could not be moved
                // at all — the "manual slider nahi chalrha" report.
                onChanged: (double v) {
                  if (_store.subAutoAdjust) {
                    unawaited(_store.setSubAutoAdjust(false));
                  }
                  unawaited(_store.setSubManualPercent(v));
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Delay: ${(_store.subDelayMs / 1000).toStringAsFixed(1)}s',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
              Slider(
                value: _store.subDelayMs.toDouble(),
                min: -5000,
                max: 5000,
                divisions: 100,
                activeColor: accent,
                onChanged: (double v) {
                  unawaited(_store.setSubDelayMs(v.round()));
                  // sub-delay shifts the sub-text timing the overlay
                  // reads (proven with real mpv) — the one panel
                  // option that still writes to mpv.
                  _applySubtitlePipeline();
                },
              ),
              const Divider(color: Color(0xFF2A2A35)),
              _panelSectionHeader('DIAGNOSTICS'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _diagLine('Track', _diagTrack),
                    _diagLine('Codec', _diagCodec),
                    _diagLine('mpv sub-visibility', _diagSubVisibility),
                    _diagLine('mpv sub-ass', _diagSubAss),
                    _diagLine(
                      'Renderer',
                      'Flutter overlay — mpv rendering is off, so '
                          'this panel drives the text above the video',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  /// Live preview of the current subtitle style (sample text, styled
  /// like the mpv output: size, colour + opacity, bold, background).
  Widget _buildSubtitlePreview() {
    final Color color =
        kSubtitleColors[_store.subColorIndex.clamp(
          0,
          kSubtitleColors.length - 1,
        )];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Text(
          'This is a subtitle preview',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: _store.subSize,
            fontWeight: _store.subBold ? FontWeight.w700 : FontWeight.w500,
            color: color.withValues(
              alpha: _store.subOpacity.clamp(0, 100) / 100,
            ),
            backgroundColor: switch (_store.subBackgroundMode) {
              'solid' => Colors.black,
              'dark' => Colors.black54,
              _ => Colors.transparent,
            },
          ),
        ),
      ),
    );
  }

  /// Pick a .srt / .ass / .vtt file from Files and load it as an
  /// external subtitle track on the playing stream (via the shared
  /// TrailerPlayer — the track then appears in the list above).
  Future<void> _loadSubtitleFile() async {
    // file_picker 13: static pickFiles, returns the files directly
    // (empty list = cancelled) — no FilePickerResult wrapper.
    final List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['srt', 'ass', 'vtt'],
    );
    if (files.isEmpty) return;
    final PlatformFile file = files.first;
    String? path = file.path;
    if (path == null) {
      final File tmp = File(
        '${Directory.systemTemp.path}/anibee-sub-${file.name}',
      );
      await tmp.writeAsBytes(await file.readAsBytes());
      path = tmp.path;
    }
    await widget.trailer.addExternalSubtitle(
      SubtitleInfo(label: file.name, url: path),
    );
    if (!mounted) return;
    setState(() {});
    _snack('Loaded subtitle: ${file.name}');
  }

  /// Quality panel: stream variants first (1080p / 720p …), then the
  /// mpv video tracks. Picking a variant reloads the same stream at
  /// that rendition, keeping the position.
  Widget _buildQualityPanelContent(Color accent) {
    final ResolvedStream? stream = _currentStream;
    final List<Widget> children = <Widget>[];
    if (stream != null && stream.variants.isNotEmpty) {
      children.add(_panelSectionHeader('QUALITY'));
      for (final StreamVariant v in stream.variants) {
        children.add(
          _panelTrackRow(
            label: v.qualityLabel,
            selected: v.url == stream.url,
            accent: accent,
            onTap: () => unawaited(_applyQualityVariant(v)),
          ),
        );
      }
      children.add(const SizedBox(height: 8));
    }
    final Tracks tracks = _player.state.tracks;
    final String currentId = _player.state.track.video.id;
    final List<VideoTrack> list = tracks.video
        .where((VideoTrack t) => t.id != 'auto' && t.id != 'no')
        .toList();
    children.add(_panelSectionHeader('VIDEO TRACKS'));
    children.add(
      _panelTrackRow(
        label: list.isEmpty ? 'Auto (single quality)' : 'Auto',
        selected: currentId == 'auto',
        accent: accent,
        onTap: () async {
          await _player.setVideoTrack(VideoTrack.auto());
          if (mounted) setState(() {});
        },
      ),
    );
    for (final VideoTrack t in list) {
      children.add(
        _panelTrackRow(
          label: _trackLabel(t.title, null, 'Quality'),
          selected: t.id == currentId,
          accent: accent,
          onTap: () async {
            await _player.setVideoTrack(t);
            if (mounted) setState(() {});
          },
        ),
      );
    }
    return ListView(children: children);
  }

  Future<void> _applyQualityVariant(StreamVariant variant) async {
    final ResolvedStream? stream = _currentStream;
    if (stream == null || variant.url == stream.url) return;
    final Duration pos = _player.state.position;
    _currentStream = ResolvedStream(
      url: variant.url,
      label: '${stream.source} ${variant.qualityLabel}',
      source: stream.source,
      headers: stream.headers,
      variants: stream.variants,
      subtitles: stream.subtitles,
    );
    await _loadStream(_currentStream!);
    if (!mounted) return;
    unawaited(_player.seek(pos));
    unawaited(_player.play());
    setState(() {});
  }

  String _trackLabel(String? title, String? language, String fallback) {
    if (title != null && title.isNotEmpty) return title;
    if (language != null && language.isNotEmpty) return language;
    return fallback;
  }

  // ---------------------------------------------------------- panel pieces

  Widget _panelSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// One diagnostics row in the Subtitles panel (0.2.7): small grey
  /// label + value, unobtrusive.
  Widget _diagLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
    );
  }

  /// One selectable row in a panel: label + an accent radio when
  /// selected (never a hardcoded gold).
  Widget _panelTrackRow({
    required String label,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      trailing: _PanelRadio(selected: selected, accent: accent),
      onTap: onTap,
    );
  }

  Widget _stepperRow({
    required String label,
    required String value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          _StepperButton(icon: Icons.remove_rounded, onTap: onMinus),
          SizedBox(
            width: 56,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _StepperButton(icon: Icons.add_rounded, onTap: onPlus),
        ],
      ),
    );
  }

  Widget _dropdownRow<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          DropdownButton<T>(
            value: value,
            dropdownColor: const Color(0xFF23232F),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            underline: const SizedBox.shrink(),
            // 0.2.8: the selected value carries an accent checkmark in
            // the menu, like the premium pickers — the current choice
            // is obvious at a glance instead of a flat list. The
            // accent comes from the theme (the Settings accent
            // picker), never hardcoded.
            items: <DropdownMenuItem<T>>[
              for (final DropdownMenuItem<T> item in items)
                DropdownMenuItem<T>(
                  value: item.value,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      item.child,
                      if (item.value == value) ...<Widget>[
                        const SizedBox(width: 10),
                        Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _toggleRow({
    required String label,
    required bool value,
    required Color accent,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      value: value,
      activeThumbColor: accent,
      onChanged: onChanged,
    );
  }

  /// Volume sheet: slider + mute toggle, opened from the volume icon.
  Future<void> _showVolumeSheet() async {
    final Color accent = Theme.of(context).colorScheme.primary;
    double volume = _player.state.volume;
    await showModalBottomSheet<void>(
      context: context,
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
                      'Volume',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        IconButton(
                          icon: Icon(
                            volume == 0
                                ? Icons.volume_off_rounded
                                : Icons.volume_down_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            setSheet(() => volume = 0);
                            unawaited(_player.setVolume(0));
                          },
                        ),
                        Expanded(
                          child: Slider(
                            value: volume,
                            min: 0,
                            max: 100,
                            activeColor: accent,
                            onChanged: (double v) {
                              setSheet(() => volume = v);
                              unawaited(_player.setVolume(v));
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.volume_up_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            setSheet(() => volume = 100);
                            unawaited(_player.setVolume(100));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    _pokeControls();
  }

  /// Aspect ratio cycle: Fit → Fill → Stretch (cover).
  void _cycleAspect() {
    setState(() {
      _videoFit = _videoFit == BoxFit.contain
          ? BoxFit.cover
          : _videoFit == BoxFit.cover
          ? BoxFit.fill
          : BoxFit.contain;
    });
    _pokeControls();
  }

  String get _aspectLabel => _videoFit == BoxFit.contain
      ? 'Fit'
      : _videoFit == BoxFit.cover
      ? 'Fill'
      : 'Stretch';

  Future<void> _showEpisodeSheet() async {
    final Color accent = Theme.of(context).colorScheme.primary;
    // 0.2.10: CONTENT-DRIVEN height, capped at 0.55. The 0.2.9 sheet
    // was a fixed 0.55 box PLUS SafeArea/chrome on top, so it
    // rendered ~0.63 tall on the phone — and for a short anime (11
    // eps = 3 grid rows) most of that height was empty space. Now
    // the sheet shrink-wraps to its content: a short anime gets a
    // SHORT sheet, and only a long list grows to the cap and scrolls.
    // Short anime (<= 12 eps) get ONE horizontal row instead of a
    // grid ("line se ana chaiye"); more than 12 keep the 5-column
    // grid. Title is one line with ellipsis.
    final bool singleRow = widget.episodes.length <= 12;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF17171F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        final double maxHeight =
            MediaQuery.of(context).size.height * 0.55;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Text(
                    'Episodes — ${widget.anime.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Flexible(
                  child: singleRow
                      ? _EpisodeRow(
                          episodes: widget.episodes,
                          current: _currentEpisode,
                          accent: accent,
                          onSelect: (Episode ep) {
                            Navigator.of(context).pop();
                            _selectEpisode(ep);
                          },
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          shrinkWrap: true,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 5,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 1.6,
                              ),
                          itemCount: widget.episodes.length,
                          itemBuilder: (BuildContext context, int index) {
                            final Episode ep = widget.episodes[index];
                            return _EpisodeCell(
                              episode: ep,
                              selected:
                                  ep.number == _currentEpisode.number,
                              accent: accent,
                              onTap: () {
                                Navigator.of(context).pop();
                                _selectEpisode(ep);
                              },
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
                        fit: _videoFit,
                        // 0.2.7: the built-in subtitle overlay is OFF.
                        // With the default PlayerConfiguration
                        // (libass: false) mpv never renders subtitles
                        // and media_kit_video shows its SubtitleView
                        // overlay with a FIXED default style — no
                        // sub-* property could ever change it (the
                        // 0.2.5 + 0.2.6 "nothing works" bug). The app
                        // renders its own overlay below
                        // (_buildSubtitleOverlay), styled from the
                        // settings store.
                        subtitleViewConfiguration:
                            const SubtitleViewConfiguration(visible: false),
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
              // Brightness dim layer (0.2.3): a black overlay whose
              // opacity follows the left-swipe brightness level. It sits
              // above the video but below the gestures/controls/HUD, so
              // it dims the picture (and the poster) without blocking
              // input. mpv's `brightness` property is a no-op under
              // hwdec on iOS, so this overlay IS the brightness control.
              if (!hasError)
                ValueListenableBuilder<double>(
                  valueListenable: _brightnessLevel,
                  builder: (BuildContext context, double level, Widget? _) {
                    final double opacity = ((100 - level) / 100 * 0.75).clamp(
                      0,
                      0.75,
                    );
                    if (opacity <= 0) return const SizedBox.shrink();
                    return IgnorePointer(
                      child: Container(
                        color: Colors.black.withValues(alpha: opacity),
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
              // 0.2.7: the app's own subtitle overlay (styled from
              // the settings store). Above the video + brightness
              // dim, below the controls/HUD — and IgnorePointer, so
              // it never eats a tap or a swipe.
              if (!hasError) _buildSubtitleOverlay(),
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
              if (!hasError) _buildPinchListener(child: _buildGestures()),
              if (!hasError && _controlsVisible) _buildControls(accent),
              // 0.2.4: right-side slide-over panel (Sources / Audio /
              // Subtitles / Quality) — above the controls, independent
              // of their auto-hide.
              if (_panelKind != null) _buildSidePanel(accent),
              if (_seekFlashVisible) _buildSeekFlash(),
              ValueListenableBuilder<_HudState?>(
                valueListenable: _hud,
                builder: (BuildContext context, _HudState? state, Widget? _) {
                  return _GestureHud(state: state, accent: accent);
                },
              ),
              // 0.2.8: the "2x" indicator while hold-to-2x is engaged.
              // Top-center so it shows even when the controls are
              // hidden (the hold works with the overlay hidden).
              if (_hold2x)
                Positioned(
                  top: 48,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        key: const ValueKey('hold2x-indicator'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.fast_forward_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '2x',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_autoplayVisible)
                _AutoplayOverlay(
                  countdown: _autoplayTimer != null ? _autoplayCountdown : null,
                  next: _nextEpisode,
                  accent: accent,
                  onPlayNow: () {
                    _autoplayTimer?.cancel();
                    _autoplayTimer = null;
                    _autoplayVisible = false;
                    final Episode? next = _nextEpisode;
                    if (next != null) _selectEpisode(next);
                    setState(() {});
                  },
                  onCancel: () {
                    // 0.2.10: Cancel means "stay on this episode" —
                    // hide the card AND remember it, so the EOF
                    // handler does not re-show it. The player stays
                    // paused on the finished episode.
                    _autoplayTimer?.cancel();
                    _autoplayTimer = null;
                    _autoplayVisible = false;
                    _autoplayCancelled = true;
                    setState(() {});
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  /// Pinch zoom lives in a raw Listener, NOT in the GestureDetector:
  /// a ScaleGestureRecognizer competes with the drag recognizers in
  /// the arena and swallows single-finger drags. The Listener only
  /// observes raw pointer events, so it never steals a drag.
  Widget _buildPinchListener({required Widget child}) {
    return Listener(
      // 0.2.8: opaque — the Listener must be in the hit path even
      // where the video texture itself does not hit-test; deferToChild
      // left it out of the path on some spots.
      behavior: HitTestBehavior.opaque,
      onPointerDown: (PointerDownEvent event) {
        _activePointers[event.pointer] = event.position;
        if (_activePointers.length == 2) {
          final List<Offset> points = _activePointers.values.toList();
          _pinchBaseDistance = (points[0] - points[1]).distance;
          _pinchBaseScale = _videoScale.value;
          _pinching = true;
          // Second finger: a pinch, never a hold.
          _cancelHold();
          _disengageHold2x();
        } else if (_activePointers.length == 1) {
          // Hold-to-2x (0.2.8): arm the hold only for the RIGHT side,
          // and only when gestures are enabled. The timer fires at
          // 400ms only if the finger is still down without moving —
          // a quick tap or a double-tap never arms it.
          _cancelHold();
          final double w = MediaQuery.of(context).size.width;
          if (_store.gestures && event.position.dx > w / 2) {
            _holdDownPosition = event.position;
            _holdPointer = event.pointer;
            _holdTimer = Timer(
              const Duration(milliseconds: 400),
              _engageHold2x,
            );
          }
        }
      },
      onPointerMove: (PointerMoveEvent event) {
        if (!_activePointers.containsKey(event.pointer)) return;
        _activePointers[event.pointer] = event.position;
        if (_pinching && _activePointers.length == 2) {
          final List<Offset> points = _activePointers.values.toList();
          final double distance = (points[0] - points[1]).distance;
          if (_pinchBaseDistance > 0) {
            // 0.2.10: pinch zoom is 1x–3x ONLY. The old 0.5 floor
            // shrank the video to half size and exposed the poster
            // behind it ("background araha" on pinch-out, 2026-11-23
            // video) — zoom-out now stops exactly at fit.
            _videoScale.value =
                (_pinchBaseScale * distance / _pinchBaseDistance).clamp(
                  1.0,
                  3.0,
                );
          }
        }
        // Hold-to-2x: the finger moved — a swipe is starting, not a
        // hold. Cancel the pending timer, or disengage if 2x is on.
        if (_holdDownPosition != null && event.pointer == _holdPointer) {
          final Offset delta = event.position - _holdDownPosition!;
          if (delta.distance > 12) {
            _cancelHold();
            _disengageHold2x();
          }
        }
      },
      onPointerUp: (PointerUpEvent event) {
        _activePointers.remove(event.pointer);
        if (_activePointers.length < 2) _pinching = false;
        if (event.pointer == _holdPointer) {
          _cancelHold();
          _disengageHold2x();
        }
      },
      onPointerCancel: (PointerCancelEvent event) {
        _activePointers.remove(event.pointer);
        if (_activePointers.length < 2) _pinching = false;
        if (event.pointer == _holdPointer) {
          _cancelHold();
          _disengageHold2x();
        }
      },
      child: child,
    );
  }

  /// Show the animated gesture HUD (volume / brightness / seek).
  void _showHud(_HudState state) {
    _hudHideTimer?.cancel();
    _hud.value = state;
  }

  /// Fade the HUD out shortly after the drag ends.
  void _hideHudSoon() {
    _hudHideTimer?.cancel();
    _hudHideTimer = Timer(const Duration(milliseconds: 700), () {
      _hud.value = null;
    });
  }

  Widget _buildGestures() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleControls,
      onDoubleTapDown: (TapDownDetails details) {
        _lastDoubleTapX = details.globalPosition.dx;
        // Zoomed in: center double-tap resets to fit. Side double-taps
        // always seek, even when zoomed (0.2.1 reset the zoom on ANY
        // double-tap, which felt broken).
        final double w = MediaQuery.of(context).size.width;
        final double x = details.globalPosition.dx;
        if (_videoScale.value != 1.0 && x > w / 3 && x < w * 2 / 3) {
          _videoScale.value = 1.0;
        }
      },
      onDoubleTap: () {
        final double w = MediaQuery.of(context).size.width;
        final double x = _lastDoubleTapX;
        // 0.2.4: showControls: false — a double-tap must NEVER show
        // the player details/controls overlay. It only seeks (with
        // the flash) or play/pauses; the overlay stays as it was.
        if (x < w / 3) {
          unawaited(
            _seekBy(
              -_store.doubleTapSeek,
              showFlash: true,
              showControls: false,
            ),
          );
        } else if (x > w * 2 / 3) {
          unawaited(
            _seekBy(_store.doubleTapSeek, showFlash: true, showControls: false),
          );
        } else {
          _flashPlayPause();
          unawaited(_togglePlay(showControls: false));
        }
      },
      onHorizontalDragStart: (DragStartDetails details) {
        // A drag starting means the finger moved: never a hold.
        _cancelHold();
        _disengageHold2x();
        if (!_store.gestures || _pinching) return;
        _dragStartPosition = _player.state.position;
        _dragAccumDx = 0;
      },
      onHorizontalDragUpdate: (DragUpdateDetails details) {
        if (!_store.gestures || _dragStartPosition == null || _pinching) {
          return;
        }
        _dragAccumDx += details.delta.dx;
        final int seconds = (_dragAccumDx / 10).round();
        _dragHintTarget = _dragStartPosition! + Duration(seconds: seconds);
        _showHud(_HudState.seek(label: '${seconds >= 0 ? '+' : ''}$seconds s'));
      },
      onHorizontalDragEnd: (DragEndDetails details) {
        if (!_store.gestures || _dragStartPosition == null) return;
        final Duration target = _dragHintTarget ?? _dragStartPosition!;
        _dragStartPosition = null;
        _dragHintTarget = null;
        _hideHudSoon();
        final Duration dur = _player.state.duration;
        Duration clamped = target;
        if (clamped < Duration.zero) clamped = Duration.zero;
        if (clamped > dur) clamped = dur;
        unawaited(_player.seek(clamped));
        _pokeControls();
      },
      onVerticalDragStart: (DragStartDetails details) {
        // A drag starting means the finger moved: never a hold.
        _cancelHold();
        _disengageHold2x();
        if (!_store.gestures || _pinching) return;
        final double w = MediaQuery.of(context).size.width;
        _dragVerticalRight = details.globalPosition.dx > w / 2;
        _dragAccumDy = 0;
        _dragStartVolume = _player.state.volume;
        _dragStartBrightnessLevel = _brightnessLevel.value;
      },
      onVerticalDragUpdate: (DragUpdateDetails details) {
        if (!_store.gestures || _pinching) return;
        // ROOT CAUSE (0.2.1): the old code subtracted only the
        // per-frame `details.delta.dy` from the start value, so the
        // value oscillated around where the swipe began and never
        // accumulated — the swipe visibly did nothing. The distance
        // must be accumulated across frames (like _dragAccumDx).
        _dragAccumDy += details.delta.dy;
        if (_dragVerticalRight) {
          // Right half = volume. Swipe up raises it; ~200 px spans
          // the full 0..100 range.
          final double v = (_dragStartVolume - _dragAccumDy * 0.5).clamp(
            0,
            100,
          );
          unawaited(_player.setVolume(v));
          _showHud(
            _HudState.volume(value: v / 100, label: 'Volume ${v.round()}%'),
          );
        } else {
          // Left half = brightness (overlay dim layer — mpv's
          // `brightness` property is a no-op under hwdec on iOS).
          // Swipe up brightens; ~250 px spans the full range.
          final double b = (_dragStartBrightnessLevel - _dragAccumDy * 0.4)
              .clamp(0, 100);
          _brightnessLevel.value = b;
          _showHud(
            _HudState.brightness(
              value: b / 100,
              label: 'Brightness ${b.round()}%',
            ),
          );
        }
      },
      onVerticalDragEnd: (DragEndDetails details) {
        _hideHudSoon();
      },
      child: const SizedBox.expand(),
    );
  }

  /// Zeus/Steps layout (0.2.3): NO top bar, NO bottom bar — every
  /// control floats directly over the video. Buttons are flat icons
  /// with no circular background (0.2.5), accent color from Settings.
  ///
  /// 0.2.4: a Stack, not a Column — the center cluster sits at the
  /// EXACT vertical center of the screen (the old Column centered it
  /// in the space between the bars, which lands above center because
  /// the bottom bar is taller than the top bar). Top bar pinned to
  /// the top, Skip + bottom bar pinned to the bottom.
  Widget _buildControls(Color accent) {
    if (_controlsLocked) {
      return Center(
        child: _RoundButton(
          icon: Icons.lock_open_rounded,
          size: 56,
          iconSize: 28,
          accentIcon: true,
          accent: accent,
          tooltip: 'Unlock controls',
          onTap: () {
            setState(() => _controlsLocked = false);
            _pokeControls();
          },
        ),
      );
    }
    return AnimatedOpacity(
      opacity: _controlsVisible ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      child: Stack(
        children: <Widget>[
          Positioned(top: 0, left: 0, right: 0, child: _buildTopBar(accent)),
          // Exact vertical center of the screen.
          Center(child: _buildCenterControls(accent)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                StreamBuilder<Duration>(
                  stream: _player.stream.position,
                  initialData: _player.state.position,
                  builder:
                      (BuildContext context, AsyncSnapshot<Duration> snap) {
                        final Duration pos = snap.data ?? Duration.zero;
                        final double posSeconds = pos.inMilliseconds / 1000.0;
                        // 0.2.4: REAL AniSkip segments — "Skip Intro"
                        // only while the position is inside the OP
                        // segment, "Skip Outro" only inside the ED
                        // segment. No AniSkip data -> no button at
                        // all, never the old hardcoded 85s jump.
                        final SkipInterval? op = _skipTimes?.op;
                        final SkipInterval? ed = _skipTimes?.ed;
                        final bool showIntro =
                            _store.skipIntro &&
                            op != null &&
                            op.contains(posSeconds);
                        final bool showOutro =
                            _store.skipIntro &&
                            ed != null &&
                            ed.contains(posSeconds);
                        // (label, seek target). Flow analysis: a true
                        // showIntro/showOutro implies its interval is
                        // non-null, so the accesses below are safe.
                        final (String, double)? skip = showIntro
                            ? ('Skip Intro', op.endTime)
                            : showOutro
                            ? ('Skip Outro', ed.endTime)
                            : null;
                        if (skip == null) {
                          return const SizedBox.shrink();
                        }
                        final String skipLabel = skip.$1;
                        final double target = skip.$2;
                        return Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              right: 16,
                              bottom: 12,
                            ),
                            child: ElevatedButton(
                              onPressed: () {
                                unawaited(
                                  _player.seek(
                                    Duration(
                                      milliseconds: (target * 1000).round(),
                                    ),
                                  ),
                                );
                                _pokeControls();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                skipLabel,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
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
        ],
      ),
    );
  }

  /// Center cluster: medium flat buttons — -10s / play-pause /
  /// +10s (the red-circled area of the reference). No circles (0.2.5).
  Widget _buildCenterControls(Color accent) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _RoundButton(
            icon: Icons.replay_10_rounded,
            size: 48,
            iconSize: 26,
            accent: accent,
            tooltip: 'Back 10 seconds',
            onTap: () => unawaited(_seekBy(-10, showFlash: true)),
          ),
          const SizedBox(width: 28),
          StreamBuilder<bool>(
            stream: _player.stream.playing,
            initialData: _player.state.playing,
            builder: (BuildContext context, AsyncSnapshot<bool> snap) {
              final bool playing = snap.data ?? false;
              return _RoundButton(
                icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 60,
                iconSize: 34,
                accent: accent,
                tooltip: playing ? 'Pause' : 'Play',
                onTap: _togglePlay,
              );
            },
          ),
          const SizedBox(width: 28),
          _RoundButton(
            icon: Icons.forward_10_rounded,
            size: 48,
            iconSize: 26,
            accent: accent,
            tooltip: 'Forward 10 seconds',
            onTap: () => unawaited(_seekBy(10, showFlash: true)),
          ),
        ],
      ),
    );
  }

  /// Double-tap seek feedback: a brief dark badge on the tapped side
  /// ("-10s" / "+10s") or a play/pause flash in the center.
  Widget _buildSeekFlash() {
    final bool? left = _seekFlashLeft;
    final Alignment alignment = left == null
        ? Alignment.center
        : left
        ? const Alignment(-0.55, 0)
        : const Alignment(0.55, 0);
    final Widget child = left == null
        ? Icon(
            _player.state.playing
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 36,
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                left ? Icons.replay_10_rounded : Icons.forward_10_rounded,
                color: Colors.white,
                size: 30,
              ),
              const SizedBox(height: 2),
              Text(
                '${left ? '-' : '+'}$_seekFlashAmount s',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          );
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  /// Top row, floating over the video: small back arrow + title +
  /// episode (left), episode-list + PiP round buttons (right).
  /// No bar behind anything.
  Widget _buildTopBar(Color accent) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: <Widget>[
            IconButton(
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 26,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: GestureDetector(
                onTap: _showEpisodeSheet,
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
                        shadows: <Shadow>[
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Episode ${_currentEpisode.number} · ${_currentEpisode.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        shadows: <Shadow>[
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _RoundButton(
              icon: Icons.list_rounded,
              size: 40,
              iconSize: 22,
              accent: accent,
              tooltip: 'Episodes',
              onTap: _showEpisodeSheet,
            ),
            const SizedBox(width: 8),
            _RoundButton(
              icon: Icons.picture_in_picture_alt_rounded,
              size: 40,
              iconSize: 22,
              accent: accent,
              active: _inPip,
              tooltip: 'Picture-in-Picture',
              onTap: _inPip
                  ? () async {
                      final AnibeeMpvPip? bridge = _pipBridge;
                      if (bridge != null) await bridge.exitPiP();
                    }
                  : _enterPip,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  /// Bottom, floating over the video: the ONLY full-width element is
  /// the thin seek bar (time left / total right). Below it, ONE row of
  /// small dark round buttons anchored to the BOTTOM-RIGHT corner —
  /// nothing at the bottom-left or bottom-center. Next is the very
  /// last button at the far corner.
  Widget _buildBottomBar(Color accent) {
    final bool subtitlesOn = _player.state.track.subtitle.id != 'no';
    final String rateLabel =
        '${_rate.toStringAsFixed(_rate.truncateToDouble() == _rate ? 0 : 2)}x';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        shadows: <Shadow>[
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: accent,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: accent,
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        shadows: <Shadow>[
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                _RoundButton(
                  icon: Icons.closed_caption_rounded,
                  size: 32,
                  iconSize: 17,
                  accent: accent,
                  active: subtitlesOn,
                  tooltip: 'Subtitles',
                  onTap: _showSubtitlesPanel,
                ),
                const SizedBox(width: 4),
                _RoundButton(
                  icon: Icons.music_note_rounded,
                  size: 32,
                  iconSize: 17,
                  accent: accent,
                  tooltip: 'Audio',
                  onTap: _showAudioPanel,
                ),
                const SizedBox(width: 4),
                _RoundButton(
                  icon: Icons.storage_rounded,
                  size: 32,
                  iconSize: 17,
                  accent: accent,
                  tooltip: 'Server',
                  onTap: _showSourcesPanel,
                ),
                const SizedBox(width: 4),
                _RoundButton(
                  icon: Icons.tune_rounded,
                  size: 32,
                  iconSize: 17,
                  accent: accent,
                  tooltip: 'Quality',
                  onTap: _showQualityPanel,
                ),
                const SizedBox(width: 4),
                _RoundButton(
                  icon: Icons.volume_up_rounded,
                  size: 32,
                  iconSize: 17,
                  accent: accent,
                  tooltip: 'Volume',
                  onTap: _showVolumeSheet,
                ),
                const SizedBox(width: 4),
                _RoundButton(
                  label: rateLabel,
                  size: 32,
                  accent: accent,
                  tooltip: 'Playback speed',
                  onTap: _cycleSpeed,
                ),
                const SizedBox(width: 4),
                _RoundButton(
                  icon: Icons.lock_rounded,
                  size: 32,
                  iconSize: 17,
                  accent: accent,
                  tooltip: 'Lock controls',
                  onTap: () {
                    setState(() => _controlsLocked = true);
                  },
                ),
                const SizedBox(width: 4),
                _RoundButton(
                  icon: Icons.aspect_ratio_rounded,
                  size: 32,
                  iconSize: 17,
                  accent: accent,
                  active: _videoFit != BoxFit.contain,
                  tooltip: 'Aspect ratio ($_aspectLabel)',
                  onTap: _cycleAspect,
                ),
                const SizedBox(width: 4),
                _RoundButton(
                  icon: Icons.skip_next_rounded,
                  size: 32,
                  iconSize: 19,
                  accent: accent,
                  tooltip: 'Next episode',
                  enabled: _nextEpisode != null,
                  onTap: _nextEpisode == null
                      ? null
                      : () => _selectEpisode(_nextEpisode!),
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

/// One player control button — FLAT floating icon (0.2.5): the icon
/// (or the speed label) floats directly over the video with NO
/// circular background — no glossy gradient, no border, no circle,
/// no shadow blob. Only a soft drop shadow under the glyph itself,
/// so it stays readable over bright video (same trick as the title
/// text above it). The tap hit area stays the same size as before;
/// only the visible circle goes. The icon turns the Settings accent
/// color when the control is active (e.g. subtitles on) — the player
/// color follows the accent picker, never a hardcoded color.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    this.icon,
    this.label,
    required this.size,
    this.iconSize = 22,
    required this.accent,
    this.active = false,
    this.accentIcon = false,
    this.enabled = true,
    this.tooltip,
    this.onTap,
  });

  final IconData? icon;
  final String? label;
  final double size;
  final double iconSize;
  final Color accent;
  final bool active;
  final bool accentIcon;
  final bool enabled;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool useAccent = active || accentIcon;
    final Color iconColor = useAccent
        ? accent
        : enabled
        ? Colors.white
        : Colors.white38;
    final Widget content = SizedBox(
      width: size,
      height: size,
      child: Center(
        child: label != null
            ? Text(
                label!,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  shadows: const <Shadow>[
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              )
            : _ShadowIcon(icon: icon!, size: iconSize, color: iconColor),
      ),
    );
    final Widget button = InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: content,
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// An icon with a soft drop shadow and no background of its own:
/// the glyph twice, a dark copy offset 1px down behind the real one.
class _ShadowIcon extends StatelessWidget {
  const _ShadowIcon({
    required this.icon,
    required this.size,
    required this.color,
  });

  final IconData icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        Transform.translate(
          offset: const Offset(0, 1),
          child: Icon(
            icon,
            size: size,
            color: Colors.black.withValues(alpha: 0.45),
          ),
        ),
        Icon(icon, size: size, color: color),
      ],
    );
  }
}

/// Accent radio used for the selected row in a side panel (0.2.4):
/// filled accent circle with a white dot when selected, outlined
/// when not. Never a hardcoded gold.
class _PanelRadio extends StatelessWidget {
  const _PanelRadio({required this.selected, required this.accent});

  final bool selected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? accent : Colors.transparent,
        border: Border.all(color: selected ? accent : Colors.white38, width: 2),
      ),
      alignment: Alignment.center,
      child: selected
          ? Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}

/// Small round - / + button for the panel steppers (size, opacity).
class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}

enum _HudKind { volume, brightness, seek }

/// One gesture-HUD state: volume / brightness carry a 0..1 value for
/// the animated bar; seek carries only a label ("+12 s").
class _HudState {
  const _HudState.volume({required this.value, required this.label})
    : kind = _HudKind.volume;
  const _HudState.brightness({required this.value, required this.label})
    : kind = _HudKind.brightness;
  const _HudState.seek({required this.label})
    : kind = _HudKind.seek,
      value = null;

  final _HudKind kind;
  final double? value;
  final String label;
}

/// Centered animated gesture HUD (MX Player / VLC style): big icon +
/// label + a smoothly animated progress bar for volume/brightness.
/// Fades in while swiping, fades out shortly after the swipe ends.
/// The last state is kept during the fade-out so it doesn't vanish
/// abruptly.
class _GestureHud extends StatefulWidget {
  const _GestureHud({required this.state, required this.accent});

  final _HudState? state;
  final Color accent;

  @override
  State<_GestureHud> createState() => _GestureHudState();
}

class _GestureHudState extends State<_GestureHud> {
  _HudState? _last;

  @override
  void didUpdateWidget(_GestureHud oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state != null) _last = widget.state;
  }

  @override
  Widget build(BuildContext context) {
    final _HudState? shown = widget.state ?? _last;
    final bool visible = widget.state != null;
    return Center(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 250),
        child: shown == null
            ? const SizedBox.shrink()
            : Container(
                width: 176,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(_iconFor(shown), color: Colors.white, size: 36),
                    const SizedBox(height: 10),
                    Text(
                      shown.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (shown.value != null) ...<Widget>[
                      const SizedBox(height: 12),
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(end: shown.value),
                        duration: const Duration(milliseconds: 150),
                        builder:
                            (BuildContext context, double value, Widget? _) {
                              return Container(
                                width: 136,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  width: 136 * value.clamp(0, 1),
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: widget.accent,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              );
                            },
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  IconData _iconFor(_HudState state) {
    switch (state.kind) {
      case _HudKind.volume:
        final double v = state.value ?? 0;
        if (v <= 0) return Icons.volume_off_rounded;
        if (v < 0.5) return Icons.volume_down_rounded;
        return Icons.volume_up_rounded;
      case _HudKind.brightness:
        return Icons.wb_sunny_rounded;
      case _HudKind.seek:
        return state.label.startsWith('-')
            ? Icons.fast_rewind_rounded
            : Icons.fast_forward_rounded;
    }
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
                'The video could not load. Check your connection and '
                'try again.',
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

  /// Seconds left on the autoplay countdown, or null when the
  /// player is paused at EOF with autoplay OFF — the card waits for
  /// the user instead of counting down (0.2.10).
  final int? countdown;
  final Episode? next;
  final Color accent;
  final VoidCallback onPlayNow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 150,
      // 0.2.9: the card itself is tappable to cancel. Before this,
      // only the two buttons responded: the Container has a
      // decoration so it IS hit-testable, but it carried no
      // recognizer, and the Stack stops hit-testing at the overlay —
      // so a tap on the title, the countdown text, the padding, or
      // the gap between the buttons was swallowed completely (not
      // even the controls toggle fired). A finger aiming at the
      // small grey Cancel text easily lands a few px off it. Any tap
      // on the card now dismisses it; the buttons still fire their
      // own handlers too (both recognizers winning is harmless —
      // onCancel is idempotent, and onPlayNow still switches).
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onCancel,
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
                countdown != null
                    ? 'Playing in $countdown s'
                    : 'Paused — tap Play now or Cancel',
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
                    // 0.2.9: a proper finger-sized target — the bare
                    // text was ~36pt tall and easy to miss.
                    style: TextButton.styleFrom(
                      minimumSize: const Size(64, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
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
      ),
    );
  }
}

/// One episode cell in the in-player chooser sheet (0.2.10): the
/// accent-filled selected cell + tap-to-select, shared by the grid
/// and the single row so both look and behave the same.
class _EpisodeCell extends StatelessWidget {
  const _EpisodeCell({
    required this.episode,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final Episode episode;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? accent : const Color(0xFF23232F),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '${episode.number}',
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Single horizontal episode row (0.2.10): short anime (<= 12
/// episodes) show all episodes in ONE line instead of a grid, so
/// the sheet stays short. Fixed 52pt row height; scrolls
/// horizontally when the cells don't fit (12 cells).
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episodes,
    required this.current,
    required this.accent,
    required this.onSelect,
  });

  final List<Episode> episodes;
  final Episode current;
  final Color accent;
  final ValueChanged<Episode> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        itemCount: episodes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final Episode ep = episodes[index];
          return SizedBox(
            width: 64,
            child: _EpisodeCell(
              episode: ep,
              selected: ep.number == current.number,
              accent: accent,
              onTap: () => onSelect(ep),
            ),
          );
        },
      ),
    );
  }
}
