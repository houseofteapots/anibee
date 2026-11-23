import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:anibee/player/subtitle_style.dart';

/// PROOF TEST (0.2.6): the subtitle editor's mpv delivery path, end to
/// end through the real media_kit Player + the real libmpv on this VM.
///
/// The user reports caption customization "still not working" on 0.2.5
/// even though the property map is proven correct in real mpv (frames
/// in ~/workspace/.tmp/subtest: sub-pos/sub-font-size/sub-color visibly
/// move/grow/recolour a VTT subtitle, and sub-ass-override=force does
/// the same for ASS while NOT breaking VTT). This test proves the
/// remaining link: the app's exact property values, applied through
/// `NativePlayer.setProperty` (the same call `_setMpvProperty` in
/// full_player_screen.dart makes), actually stick inside mpv while a
/// VTT subtitle track is loaded and playing — for the default style
/// and for a panel change (pos 20 / size 90 / red).
///
/// If this passes, the delivery mechanism is proven and a phone-only
/// failure must be in something this VM cannot reproduce (the iOS
/// libmpv build or the on-device timing); if it fails, the break is
/// here, in the open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'subtitle style properties stick in real mpv via media_kit',
    () async {
      MediaKit.ensureInitialized();
      final Player player = Player();
      addTearDown(player.dispose);

      final NativePlayer native = player.platform as NativePlayer;
      // Headless: no video window, no audio device.
      await native.setProperty('vo', 'null');
      await native.setProperty('ao', 'null');

      final String video =
          File('test/fixtures/test.mp4').absolute.uri.toString();
      final String vtt =
          File('test/fixtures/sub.vtt').absolute.uri.toString();
      await player.open(Media(video));
      await player.setSubtitleTrack(
        SubtitleTrack.uri(vtt, title: 'English'),
      );
      await player.play();

      // Wait until the player is actually playing (<= 10 s).
      bool playing = false;
      for (int i = 0; i < 100; i++) {
        if (player.state.playing) {
          playing = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(playing, isTrue, reason: 'player never started playing');

      // 1. The app's default style map, applied exactly as the
      // player screen applies it (one setProperty per entry).
      final Map<String, String> defaults = buildSubtitleMpvProperties(
        subSize: 18,
        subFont: 'Inter Semibold',
        subColor: Colors.white,
        subOpacity: 100,
        subBold: false,
        subOutline: 'medium',
        subBackgroundMode: 'off',
        subEncoding: 'auto',
        subDelayMs: 0,
        subPos: 80,
      );
      for (final MapEntry<String, String> e in defaults.entries) {
        await native.setProperty(e.key, e.value);
      }
      // Every value must read back as what was set (mpv returns
      // numbers in canonical double form, e.g. '36.000000').
      Future<double> num(String k) async =>
          double.parse(await native.getProperty(k));
      expect(await native.getProperty('sub-ass-override'), 'force');
      expect(await num('sub-font-size'), closeTo(36, 0.001));
      expect(await native.getProperty('sub-color'), '#FFFFFFFF');
      expect(await num('sub-pos'), closeTo(80, 0.001));
      expect(await num('sub-delay'), closeTo(0, 0.001));

      // 2. A panel change mid-playback: manual position slider to
      // 20 (top), size stepper to 90, colour to red — the exact
      // "nothing works" report. Each must stick.
      final Map<String, String> changed = buildSubtitleMpvProperties(
        subSize: 45,
        subFont: 'System',
        subColor: const Color(0xFFFF0000),
        subOpacity: 100,
        subBold: true,
        subOutline: 'thick',
        subBackgroundMode: 'solid',
        subEncoding: 'auto',
        subDelayMs: 500,
        subPos: 20,
      );
      for (final MapEntry<String, String> e in changed.entries) {
        await native.setProperty(e.key, e.value);
      }
      expect(await num('sub-pos'), closeTo(20, 0.001));
      expect(await num('sub-font-size'), closeTo(90, 0.001));
      expect(await native.getProperty('sub-color'), '#FFFF0000');
      expect(await native.getProperty('sub-bold'), 'yes');
      expect(await num('sub-delay'), closeTo(0.5, 0.001));
      expect(await native.getProperty('sub-back-color'), '#FF000000');
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
