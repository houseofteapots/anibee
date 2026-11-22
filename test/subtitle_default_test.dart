import 'package:anibee/player/trailer_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// 0.2.2: the default subtitle track must be English (matching the SUB
/// selection) — sources list tracks in their own order and Arabic can
/// come first, which wrongly showed Arabic subtitles (Chainsaw Man EP 2).
void main() {
  group('pickDefaultSubtitleTrack', () {
    SubtitleTrack track(String label) =>
        SubtitleTrack.uri('https://example.com/$label.vtt', title: label);

    test('prefers English when Arabic comes first', () {
      final List<SubtitleTrack> tracks = <SubtitleTrack>[
        track('Arabic'),
        track('English'),
        track('Spanish'),
      ];
      expect(pickDefaultSubtitleTrack(tracks).title, 'English');
    });

    test('matches English label variants', () {
      expect(
        pickDefaultSubtitleTrack(
          <SubtitleTrack>[track('Arabic'), track('English [SDH]')],
        ).title,
        'English [SDH]',
      );
      expect(
        pickDefaultSubtitleTrack(
          <SubtitleTrack>[track('Arabic'), track('en')],
        ).title,
        'en',
      );
    });

    test('falls back to first when no English track exists', () {
      final List<SubtitleTrack> tracks = <SubtitleTrack>[
        track('Arabic'),
        track('Spanish'),
      ];
      expect(pickDefaultSubtitleTrack(tracks).title, 'Arabic');
    });

    test('English first stays first', () {
      final List<SubtitleTrack> tracks = <SubtitleTrack>[
        track('English'),
        track('Arabic'),
      ];
      expect(pickDefaultSubtitleTrack(tracks).title, 'English');
    });
  });
}
