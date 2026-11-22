import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
class TrailerPlayer extends ChangeNotifier {
  TrailerPlayer() {
    _player = Player();
    _controller = VideoController(_player);
  }

  late final Player _player;
  late final VideoController _controller;

  VideoController get controller => _controller;
  Player get player => _player;

  String? _url;
  bool _inlineActive = true;
  bool _loaded = false;

  /// Whether the Detail hero should render its inline Video widget.
  /// False while the full player screen owns the video surface.
  bool get inlineActive => _inlineActive;

  bool get loaded => _loaded;

  /// Load + autoplay the trailer inline (muted loop preview).
  Future<void> loadInline(String? url) async {
    if (url == null || url == _url) return;
    _url = url;
    _loaded = false;
    await _player.open(Media(url));
    await _player.setVolume(0);
    await _player.setPlaylistMode(PlaylistMode.loop);
    await _player.play();
    _loaded = true;
    notifyListeners();
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
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
