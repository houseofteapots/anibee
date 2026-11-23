import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/miruro_resolver.dart';

/// Dedup key for a subtitle track row (0.2.12): the normalized
/// VISIBLE label — what the user reads. Two tracks with the same
/// visible label are one row, whatever their ids or language codes:
/// mpv reports HLS rendition tracks with ISO 639-2 codes ('eng')
/// under fresh ids on every variant switch, and resolver-fetched
/// tracks carry no language at all. Pure — unit-tested.
String subtitleDedupKey(SubtitleTrack t) {
  final String label = (t.title != null && t.title!.isNotEmpty)
      ? t.title!
      : (t.language != null && t.language!.isNotEmpty)
      ? t.language!
      : 'Subtitle';
  return label.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Dedup a subtitle track list by visible label, keeping the first
/// track per label (mpv's own tracks come first — they are already
/// loaded in the player). Pure — unit-tested.
List<SubtitleTrack> dedupSubtitleTracks(Iterable<SubtitleTrack> tracks) {
  final List<SubtitleTrack> out = <SubtitleTrack>[];
  final Set<String> seen = <String>{};
  for (final SubtitleTrack t in tracks) {
    if (seen.add(subtitleDedupKey(t))) out.add(t);
  }
  return out;
}

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

/// The ONE libmpv player shared by the Detail screen and the full
/// player screen — same engine, same Player instance, handed between
/// the two Video widgets.
///
/// 0.2.5: the inline trailer preview is GONE (the YouTube embed
/// failed on the phone with Error 153) — the detail banner is a
/// poster image only. This class is now purely the full-player
/// engine: [loadStream] opens a resolved episode stream, the full
/// player owns the surface while it is open, and [backToInline] is
/// a no-op hand-back (the banner shows no video any more).
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
  String? _loadError;

  /// True when the loaded media is a real episode stream (M2).
  /// Retry re-opens the same stream.
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

  /// Load a real resolved episode stream (M2): the URL + playback
  /// headers (Referer/Origin) + subtitle tracks. Playback STOPS at
  /// the end of the episode (PlaylistMode.none) — 0.2.10: `single`
  /// means "loop the current media forever" in media_kit, which is
  /// what silently restarted EP 2 from 00:00 at EOF on the phone
  /// (2026-11-23 video); the full player owns the end-of-episode
  /// card and the next-episode advance. [muted] is false when the
  /// full player loads the stream (volume 100); the inline hero
  /// never loads streams. [subtitleLanguage] is the user's preferred
  /// subtitle language (Settings → Player).
  Future<void> loadStream(
    ResolvedStream stream, {
    bool muted = false,
    String subtitleLanguage = 'auto',
  }) async {
    _url = stream.url;
    _isStream = true;
    _streamHeaders = stream.headers;
    _subtitleLanguage = subtitleLanguage;
    // 0.2.12: the resolver can return the same label twice (e.g.
    // English from two subtitle endpoints) — dedup by normalized
    // label here, so the Subtitles panel never lists one language
    // twice for the same stream.
    final Map<String, SubtitleTrack> byLabel = <String, SubtitleTrack>{};
    for (final SubtitleInfo s in stream.subtitles) {
      byLabel.putIfAbsent(
        s.label.toLowerCase().trim(),
        () => SubtitleTrack.uri(s.url, title: s.label),
      );
    }
    _streamSubtitles = byLabel.values.toList();
    _loadError = null;
    _loaded = false;
    notifyListeners();
    try {
      await _player.open(Media(stream.url, httpHeaders: stream.headers));
      await _player.setVolume(muted ? 0 : 100);
      // 0.2.10: PlaylistMode.none — playback STOPS at EOF. `single`
      // loops the current media forever (the EP 2 restart bug).
      await _player.setPlaylistMode(PlaylistMode.none);
      await _player.play();
      _loaded = true;
      _loadError = null;
      if (_streamSubtitles.isNotEmpty) {
        try {
          final SubtitleTrack? picked = pickSubtitleTrack(
            _streamSubtitles,
            subtitleLanguage,
          );
          await _player.setSubtitleTrack(picked ?? SubtitleTrack.no());
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
    final SubtitleTrack track = SubtitleTrack.uri(info.url, title: info.label);
    // 0.2.12: dedup by URL (the id for uri tracks) AND by label —
    // a re-fetched English track can arrive under a new signed URL
    // with the same visible label, and the panel must not grow a
    // second "English" row for it.
    if (_streamSubtitles.any(
      (SubtitleTrack t) =>
          t.id == track.id || subtitleDedupKey(t) == subtitleDedupKey(track),
    )) {
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

  /// Hand the surface to the full player screen.
  Future<void> expandToFull() async {
    _inlineActive = false;
    notifyListeners();
    await _player.setVolume(100);
    // 0.2.10: none, not `single` (which loops the media — see
    // loadStream). The full player owns the end-of-episode card.
    await _player.setPlaylistMode(PlaylistMode.none);
    await _player.play();
  }

  /// Hand the surface back: 0.2.5 the banner is a poster, not a
  /// video — nothing plays here. Stops the stream so no audio keeps
  /// running after the player closes.
  Future<void> backToInline() async {
    _inlineActive = true;
    await _player.stop();
    _loaded = false;
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

  /// Force a reload of the current stream (Retry button after a load
  /// error). Streams re-open with their headers/subtitles.
  Future<void> retry() async {
    final String? u = _url;
    if (u == null || !_isStream) return;
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
  }

  @override
  void dispose() {
    _errorSub.cancel();
    _player.dispose();
    super.dispose();
  }
}
