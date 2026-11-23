import 'dart:async';

import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/services/miruro_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'player_skip_times_harness.dart';

/// 0.2.12 Subtitles panel glitch (user video 2026-11-23, Demon
/// Slayer EP 7): the track list grew while playing — English x3,
/// Portuguese x3 — and rows overlapped. Cause: dedup by id only,
/// while the same language arrives under several ids (one per HLS
/// rendition variant, plus the resolver-fetched copy). Now dedup is
/// by visible label, every row has a stable key, and the panel shows
/// each distinct track exactly once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(configureSkipTestBindings);

  group('subtitleDedupKey / dedupSubtitleTracks (pure)', () {
    test('same label, different ids → one row', () {
      final List<SubtitleTrack> tracks = dedupSubtitleTracks(
        <SubtitleTrack>[
          SubtitleTrack('1', 'English', 'eng'),
          SubtitleTrack('2', 'English', 'eng'),
          SubtitleTrack.uri(
            'https://cdn.example.com/en.srt',
            title: 'English',
          ),
          SubtitleTrack('4', 'Portuguese', 'por'),
          SubtitleTrack('5', 'Portuguese', 'por'),
          SubtitleTrack.uri(
            'https://cdn.example.com/pt.srt',
            title: 'Portuguese',
          ),
          SubtitleTrack('7', 'Spanish', 'spa'),
        ],
      );
      expect(
        tracks.map((SubtitleTrack t) => subtitleDedupKey(t)).toList(),
        <String>['english', 'portuguese', 'spanish'],
      );
    });

    test('mpv ISO code vs resolver no-language, same label → one row',
        () {
      expect(
        subtitleDedupKey(SubtitleTrack('1', 'English', 'eng')),
        subtitleDedupKey(
          SubtitleTrack.uri('https://cdn.example.com/en.srt', title: 'English'),
        ),
      );
      expect(
        dedupSubtitleTracks(<SubtitleTrack>[
          SubtitleTrack('1', 'English', 'eng'),
          SubtitleTrack.uri('https://cdn.example.com/en.srt', title: 'English'),
        ]).length,
        1,
      );
    });

    test('distinct labels are kept, first track wins per label', () {
      final List<SubtitleTrack> tracks = dedupSubtitleTracks(
        <SubtitleTrack>[
          SubtitleTrack('mpv-1', 'English', 'eng'),
          SubtitleTrack.uri('https://cdn.example.com/en.srt', title: 'English'),
          SubtitleTrack('mpv-2', 'Portuguese (- Português (Brasil))', 'por'),
        ],
      );
      expect(tracks.length, 2);
      // The mpv track (already loaded in the player) wins.
      expect(tracks.first.id, 'mpv-1');
    });

    test('title-less tracks fall back to language', () {
      expect(subtitleDedupKey(SubtitleTrack('1', null, 'eng')), 'eng');
      expect(subtitleDedupKey(SubtitleTrack('1', null, null)), 'subtitle');
    });
  });

  group('Subtitles panel (widget)', () {
    testWidgets('duplicate-label tracks render once each',
        (WidgetTester tester) async {
      final SkipPlayerHarness harness = SkipPlayerHarness();
      await harness.pumpPlayer(tester, anime: mha);
      // The Demon Slayer EP 7 shape: English x3 + Portuguese x3
      // under different ids/URLs, as the panel would receive them
      // from mpv rendition tracks + resolver fetches.
      //
      // The calls are fired UNAWAITED on purpose: addExternalSubtitle
      // appends to streamSubtitles synchronously, then awaits
      // `Player.setSubtitleTrack` — and mpv's `sub-add` NEVER returns
      // in this headless env (proven with http + file:// URLs, loaded
      // clip or not: the command stalls on mpv's headless audio
      // init). On the phone media is loaded and audio init works,
      // so the call completes there. Awaiting it here would hang the
      // test forever; the panel reads the already-appended list.
      // No tearDown dispose (same as player_double_tap_test): the
      // orphaned setSubtitleTrack futures die with the test process.
      const List<SubtitleInfo> dupes = <SubtitleInfo>[
        SubtitleInfo(label: 'English', url: 'http://127.0.0.1:9/en-a.srt'),
        SubtitleInfo(label: 'English', url: 'http://127.0.0.1:9/en-b.srt'),
        SubtitleInfo(
          label: 'Portuguese',
          url: 'http://127.0.0.1:9/pt-a.srt',
        ),
        SubtitleInfo(
          label: 'Portuguese',
          url: 'http://127.0.0.1:9/pt-b.srt',
        ),
        SubtitleInfo(label: 'Spanish', url: 'http://127.0.0.1:9/es.srt'),
      ];
      for (final SubtitleInfo info in dupes) {
        unawaited(harness.trailer.addExternalSubtitle(info));
      }
      await tester.pump();
      // The trailer itself never holds the same label twice.
      expect(harness.trailer.streamSubtitles.length, 3);

      // Open the Subtitles slide-over panel.
      if (!harness.playerState(tester).controlsVisibleForTest) {
        await tester.tapAt(const Offset(400, 300));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
      }
      await tester.tap(find.byTooltip('Subtitles'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(find.text('Subtitles'), findsWidgets);
      // Each distinct track exactly once — no English x3.
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Portuguese'), findsOneWidget);
      expect(find.text('Spanish'), findsOneWidget);
      expect(find.text('Load subtitle file'), findsOneWidget);
    });
  });
}
