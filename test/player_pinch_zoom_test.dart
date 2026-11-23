// PINCH ZOOM (0.2.10, item 4): the pinch scale is clamped to
// 1.0 – 3.0 (fit to 3x). Zooming out used to shrink the video to
// 0.5x, which exposed the PosterArt layer behind it — the
// "background" in the user's video. The poster stays (it is still
// needed while the stream loads / on error); the clamp is what
// keeps it covered.
import 'package:anibee/models.dart';
import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/screens/full_player_screen.dart';
import 'package:anibee/services/aniskip_service.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'player_skip_times_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  configureSkipTestBindings();

  const Anime anime = Anime(
    id: 'pinch-test',
    anilistId: 999992,
    title: 'Pinch Test Anime',
    rating: 4.0,
    year: 2024,
    episodeCount: 12,
    genres: <String>['Action'],
    synopsis: 'Test anime for pinch zoom clamping.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
  );

  late SettingsStore store;
  late TrailerPlayer trailer;

  dynamic playerState(WidgetTester tester) =>
      tester.state(find.byType(FullPlayerScreen)) as dynamic;

  Future<void> pumpPlayer(WidgetTester tester) async {
    store = await SettingsStore.load();
    await tester.runAsync(() async {
      trailer = TrailerPlayer();
    });
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    final List<Episode> episodes = mockEpisodes(anime);
    await tester.pumpWidget(
      MaterialApp(
        home: FullPlayerScreen(
          trailer: trailer,
          store: store,
          anime: anime,
          episodes: episodes,
          initialEpisode: episodes.first,
          aniSkip: AniSkipService(
            client: MockClient(
              (_) async => http.Response('{"found":false}', 404),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // Pinch only reaches the Listener when the controls layer is
    // hidden: the Stack hit-tests topmost-first, and the controls
    // overlay (above the pinch Listener) swallows pointer downs
    // while visible. On the phone the user pinches during playback,
    // controls auto-hidden — same state here.
    playerState(tester).hideControlsForTest();
    await tester.pump();
    expect(playerState(tester).controlsVisibleForTest, isFalse);
  }

  // Two-finger pinch: start at (a, b), then move the fingers so the
  // distance becomes (a', b'). Returns the resulting video scale.
  // NOTE: startGesture defaults to pointer 1 — the two fingers need
  // DISTINCT pointer ids, or the Listener's pointer map never sees
  // two pointers and no pinch happens.
  Future<double> pinch(
    WidgetTester tester,
    Offset a,
    Offset b,
    Offset moveA,
    Offset moveB,
  ) async {
    final TestGesture g1 = await tester.startGesture(a, pointer: 1);
    final TestGesture g2 = await tester.startGesture(b, pointer: 2);
    await g1.moveBy(moveA);
    await g2.moveBy(moveB);
    await tester.pump();
    final double scale = playerState(tester).videoScaleForTest as double;
    await g1.up();
    await g2.up();
    // Flush the double-tap window timer the GestureDetector arms on
    // the ups, or teardown fails on a pending Timer.
    await tester.pump(const Duration(milliseconds: 400));
    return scale;
  }

  group('pinch zoom clamp 1.0 - 3.0', () {
    testWidgets('pinch out below 1.0 stays at 1.0 (poster never exposed)',
        (WidgetTester tester) async {
      await pumpPlayer(tester);
      expect(playerState(tester).videoScaleForTest, 1.0);
      // 400pt apart -> 100pt apart: scale 0.25, clamped to 1.0.
      final double scale = await pinch(
        tester,
        const Offset(200, 300),
        const Offset(600, 300),
        const Offset(150, 0),
        const Offset(-150, 0),
      );
      expect(scale, 1.0);
    });

    testWidgets('pinch in above 3.0 stays at 3.0', (
      WidgetTester tester,
    ) async {
      await pumpPlayer(tester);
      // 100pt apart -> 600pt apart: scale 6.0, clamped to 3.0.
      final double scale = await pinch(
        tester,
        const Offset(350, 300),
        const Offset(450, 300),
        const Offset(-250, 0),
        const Offset(250, 0),
      );
      expect(scale, 3.0);
    });

    testWidgets('a moderate pinch still zooms', (
      WidgetTester tester,
    ) async {
      await pumpPlayer(tester);
      // 200pt apart -> 400pt apart: scale 2.0.
      final double scale = await pinch(
        tester,
        const Offset(300, 300),
        const Offset(500, 300),
        const Offset(-100, 0),
        const Offset(100, 0),
      );
      expect(scale, 2.0);
    });
  });
}
