import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models.dart';
import '../services/miruro_resolver.dart';

/// Pick the subtitle track for the user's preferred language
/// (Settings → Player → Subtitle language): 'auto' | 'en' | 'hi' |
/// 'ar' | 'off'. 'auto' means English. A missing language falls back
/// to English, then the first track. Returns null for 'off' (no
/// subtitles) or an empty list.
SubtitleTrack? pickSubtitleTrack(List<SubtitleTrack> tracks, String language) {
  if (language == 'off' || tracks.isEmpty) return null;
  bool matches(String lang, SubtitleTrack track) {
    final String label = (track.title ?? '').trim().toLowerCase();
    final String code = (track.language ?? '').trim().toLowerCase();
    switch (lang) {
      case 'en':
        return MiruroResolver.isEnglishLabel(track.title) ||
            code == 'en' ||
            code == 'eng';
      case 'hi':
        return label.contains('hindi') ||
            label == 'hi' ||
            label.startsWith('hi ') ||
            code == 'hi' ||
            code == 'hin';
      case 'ar':
        return label.contains('arabic') ||
            label == 'ar' ||
            label.startsWith('ar ') ||
            code == 'ar' ||
            code == 'ara';
      default:
        return false;
    }
  }
  if (language != 'auto') {
    for (final SubtitleTrack track in tracks) {
      if (matches(language, track)) return track;
    }
  }
  // 'auto' = English; also the fallback for a missing language.
  for (final SubtitleTrack track in tracks) {
    if (matches('en', track)) return track;
  }
  return tracks.first;
}

/// Default subtitle track for a freshly loaded stream: prefer English
/// (matching the SUB selection) — sources list tracks in their own
/// order and Arabic can come first, so taking `.first` wrongly showed
/// Arabic subtitles (0.2.1, Chainsaw Man EP 2). Falls back to the
/// first track when no English track exists. [tracks] must be non-empty.
SubtitleTrack pickDefaultSubtitleTrack(List<SubtitleTrack> tracks) {
  return pickSubtitleTrack(tracks, 'auto') ?? tracks.first;
}

/// The ONE libmpv player shared by the Detail inline trailer and the full
/// player screen — same engine, same Player instance, handed between the
/// two Video widgets.
///
/// Flow (user-decided 2026-11-23 01:15):
/// - Detail banner plays the TRAILER preview inline (muted, looping).
/// - A button on the SIDE of the banner opens the trailer in the full
///   player (unmuted, with controls).
/// - Tapping the inline player also expands to the full player.
/// - Leaving the full player returns the player to the inline banner.
///
/// M1.1: the sample trailer URL is verified working (the old Google
/// bucket 403s). If it ever fails to load, the Apple HLS sample is tried
/// once; [loadError] surfaces so the UI shows a real state, never a
/// black void.
class TrailerPlayer extends ChangeNotifier {
  TrailerPlayer() {
    _player = Player();
    _controller = VideoController(_player);
    _errorSub = _player.stream.error.listen((Object? e) {
      if (e == null) return;
      _loadError = e.toString();
      notifyListeners();
    });
  }

  late final Player _player;
  late final VideoController _controller;
  late final StreamSubscription<dynamic> _errorSub;

  VideoController get controller => _controller;
  Player get player => _player;

  String? _url;
  bool _inlineActive = true;
  bool _loaded = false;
  bool _fallbackTried = false;
  String? _loadError;

  /// True when the loaded media is a real episode stream (M2) rather
  /// than the sample trailer — retry re-opens the stream, never the
  /// sample fallback.
  bool _isStream = false;
  Map<String, String> _streamHeaders = const <String, String>{};
  List<SubtitleTrack> _streamSubtitles = const <SubtitleTrack>[];

  /// Preferred subtitle language for the loaded stream ('auto' |
  /// 'en' | 'hi' | 'ar' | 'off') — kept so retry() re-applies it.
  String _subtitleLanguage = 'auto';

  /// Subtitle tracks of the loaded stream (incl. externally fetched
  /// ones added via [addExternalSubtitle]) — the player sheet merges
  /// these with mpv's own track list.
  List<SubtitleTrack> get streamSubtitles => _streamSubtitles;

  /// Whether the Detail hero should render its inline Video widget.
  /// False while the full player screen owns the video surface.
  bool get inlineActive => _inlineActive;

  bool get loaded => _loaded;

  /// Non-null when the current media failed to load (UI shows the
  /// never-blank fallback state instead of a black screen).
  String? get loadError => _loadError;

  /// The URL currently loaded (the PiP software player re-opens this).
  String? get url => _url;

  /// Apply the Hardware decoding setting (mpv hwdec) to this player.
  /// Best-effort: the public Player has no setProperty — the native
  /// platform player does (Zeus pattern).
  Future<void> applyHwdec(bool enabled) async {
    final PlatformPlayer? platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('hwdec', enabled ? 'auto' : 'no');
      } catch (_) {
        // Playback continues with the default decoder.
      }
    }
  }

  /// Load + autoplay the trailer inline (muted loop preview).
  Future<void> loadInline(String? url) async {
    if (url == null || (url == _url && !_isStream)) return;
    _url = url;
    _isStream = false;
    _streamHeaders = const <String, String>{};
    _streamSubtitles = const <SubtitleTrack>[];
    _fallbackTried = false;
    _loadError = null;
    _loaded = false;
    notifyListeners();
    await _openUrl(url);
  }

  /// Load a real resolved episode stream (M2): the URL + playback
  /// headers (Referer/Origin) + subtitle tracks. Single-play mode
  /// (no loop — it is a real episode, not the trailer preview).
  /// [muted] is false when the full player loads the stream (volume
  /// 100); the inline hero never loads streams. [subtitleLanguage] is
  /// the user's preferred subtitle language (Settings → Player).
  Future<void> loadStream(
    ResolvedStream stream, {
    bool muted = false,
    String subtitleLanguage = 'auto',
  }) async {
    _url = stream.url;
    _isStream = true;
    _streamHeaders = stream.headers;
    _subtitleLanguage = subtitleLanguage;
    _streamSubtitles = stream.subtitles
        .map(
          (SubtitleInfo s) => SubtitleTrack.uri(s.url, title: s.label),
        )
        .toList();
    _fallbackTried = true; // never fall back to the sample for streams
    _loadError = null;
    _loaded = false;
    notifyListeners();
    try {
      await _player.open(
        Media(stream.url, httpHeaders: stream.headers),
      );
      await _player.setVolume(muted ? 0 : 100);
      await _player.setPlaylistMode(PlaylistMode.single);
      await _player.play();
      _loaded = true;
      _loadError = null;
      if (_streamSubtitles.isNotEmpty) {
        try {
          final SubtitleTrack? picked = pickSubtitleTrack(
            _streamSubtitles,
            subtitleLanguage,
          );
          await _player.setSubtitleTrack(
            picked ?? SubtitleTrack.no(),
          );
        } catch (_) {
          // Subtitles are best-effort; playback continues without them.
        }
      }
    } catch (e) {
      _loadError = e.toString();
      _loaded = false;
    }
    notifyListeners();
  }

  /// Add an externally fetched subtitle (e.g. English fetched when
  /// the stream carried none) and select it. Joins [_streamSubtitles]
  /// so the sheet lists it and retry() keeps it.
  Future<void> addExternalSubtitle(SubtitleInfo info) async {
    final SubtitleTrack track = SubtitleTrack.uri(
      info.url,
      title: info.label,
    );
    if (_streamSubtitles.any((SubtitleTrack t) => t.id == track.id)) {
      return;
    }
    _streamSubtitles = <SubtitleTrack>[..._streamSubtitles, track];
    try {
      await _player.setSubtitleTrack(track);
    } catch (_) {
      // Best-effort; playback continues without it.
    }
    notifyListeners();
  }

  Future<void> _openUrl(String url) async {
    try {
      await _player.open(Media(url));
      await _player.setVolume(0);
      await _player.setPlaylistMode(PlaylistMode.loop);
      await _player.play();
      _loaded = true;
      _loadError = null;
    } catch (e) {
      _onLoadFailed(url, e);
    }
    notifyListeners();
  }

  Future<void> _onLoadFailed(String failedUrl, Object e) async {
    if (!_fallbackTried && failedUrl != kSampleTrailerFallbackUrl) {
      _fallbackTried = true;
      _url = kSampleTrailerFallbackUrl;
      await _openUrl(kSampleTrailerFallbackUrl);
      return;
    }
    _loadError = e.toString();
    _loaded = false;
  }

  /// Hand the surface to the full player screen.
  Future<void> expandToFull() async {
    _inlineActive = false;
    notifyListeners();
    await _player.setVolume(100);
    await _player.setPlaylistMode(PlaylistMode.single);
    await _player.play();
  }

  /// Hand the surface back to the inline banner.
  Future<void> backToInline() async {
    if (_url != null) {
      await _player.setVolume(0);
      await _player.setPlaylistMode(PlaylistMode.loop);
      await _player.play();
    }
    _inlineActive = true;
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    _loaded = false;
    _url = null;
    _isStream = false;
    _streamHeaders = const <String, String>{};
    _streamSubtitles = const <SubtitleTrack>[];
    notifyListeners();
  }

  /// Force a reload of the current URL (Retry button after a load
  /// error). Streams re-open with their headers/subtitles; the trailer
  /// re-opens inline as before.
  Future<void> retry() async {
    final String? u = _url;
    if (u == null) return;
    if (_isStream) {
      await loadStream(
        ResolvedStream(
          url: u,
          label: 'Retry',
          source: 'Miruro',
          headers: _streamHeaders,
          subtitles: _streamSubtitles
              .map(
                // SubtitleTrack.uri(url) stores the URL in `id`
                // (`uri` is just a bool flag).
                (SubtitleTrack t) =>
                    SubtitleInfo(label: t.title ?? '', url: t.id),
              )
              .where((SubtitleInfo s) => s.url.isNotEmpty)
              .toList(),
        ),
        subtitleLanguage: _subtitleLanguage,
      );
      return;
    }
    _url = null;
    _loadError = null;
    await loadInline(u);
  }

  @override
  void dispose() {
    _errorSub.cancel();
    _player.dispose();
    super.dispose();
  }
}
