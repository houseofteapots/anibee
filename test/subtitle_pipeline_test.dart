import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:anibee/player/subtitle_style.dart';

/// PROOF TEST (0.2.7): the subtitle pipeline that still goes
/// through mpv — `sub-delay` (and `sub-codepage`) — actually
/// reaches the subtitle text the overlay reads.
///
/// 0.2.5/0.2.6 proved the `sub-*` STYLE properties stick inside
/// mpv, yet nothing changed on the phone — because with the
/// default `PlayerConfiguration` (`libass: false`) mpv never
/// renders subtitles at all; the visible caption was
/// media_kit_video's fixed-style `SubtitleView` overlay. The app
/// now renders its own overlay from `player.stream.subtitle`
/// (mpv's `sub-text`), so the only mpv write that can still move
/// the picture is the timing: `sub-delay` shifts when `sub-text`
/// is emitted. This test proves that link with the real player +
/// the real libmpv on this VM, using the fixture VTT (cue 1
/// "Hello subtitle world" 0.5–3.5 s, cue 2 "Second line here"
/// 4.0–7.5 s):
/// - delay 0 at 2 s -> "Hello subtitle world" is showing;
/// - delay +5 at 2 s -> nothing is showing (the cue moved to
///   5.5–8.5 s);
/// - delay +5 at 6 s -> "Hello subtitle world" is showing again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'sub-delay shifts the subtitle text the overlay reads',
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

      // The pipeline map the player screen applies.
      final Map<String, String> pipeline =
          buildSubtitlePipelineProperties(subDelayMs: 0, subEncoding: 'auto');
      for (final MapEntry<String, String> e in pipeline.entries) {
        await native.setProperty(e.key, e.value);
      }
      expect(
        double.parse(await native.getProperty('sub-delay')),
        closeTo(0, 0.001),
      );

      Future<List<String>> subtitleAfterSeek(
        double seconds, {
        Duration settle = const Duration(milliseconds: 800),
      }) async {
        await player.seek(Duration(milliseconds: (seconds * 1000).round()));
        // Let the seek land and the sub-text observer catch up.
        await Future<void>.delayed(settle);
        return player.state.subtitle;
      }

      // Delay 0, inside cue 1 -> the cue text is showing.
      List<String> lines = await subtitleAfterSeek(2.0);
      expect(
        lines.join(' '),
        contains('Hello subtitle world'),
        reason: 'cue 1 should show at 2 s with delay 0, got $lines',
      );

      // Delay +5 shifts cue 1 to 5.5–8.5 s: at 2 s nothing shows.
      await native.setProperty('sub-delay', '5');
      lines = await subtitleAfterSeek(2.0);
      expect(
        lines.where((String l) => l.trim().isNotEmpty),
        isEmpty,
        reason: 'cue 1 should be shifted away at 2 s with delay +5, '
            'got $lines',
      );

      // Same delay, inside the shifted cue -> the text is back.
      lines = await subtitleAfterSeek(6.0);
      expect(
        lines.join(' '),
        contains('Hello subtitle world'),
        reason: 'shifted cue 1 should show at 6 s with delay +5, '
            'got $lines',
      );

      // Delay back to 0 at 6 s -> cue 2 ("Second line here", 4–7.5 s).
      await native.setProperty('sub-delay', '0');
      lines = await subtitleAfterSeek(6.0);
      expect(
        lines.join(' '),
        contains('Second line here'),
        reason: 'cue 2 should show at 6 s with delay 0, got $lines',
      );
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
