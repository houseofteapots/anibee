// END-OF-EPISODE (0.2.10, item 1): the player must PAUSE at the end
// of an episode and show the Up-next card — Cancel / next episode —
// never silently restart the same episode. The next episode is
// resolved BY EPISODE NUMBER, so it works even when the initial
// episode object is a different instance from the list element
// (Detail rebuilds _episodes during resolve — the old identity-based
// indexOf returned -1 and the overlay never showed; PlaylistMode
// .single looped the media forever).
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
    id: 'eof-test',
    anilistId: 999991,
    title: 'EOF Test Anime',
    rating: 4.0,
    year: 2024,
    episodeCount: 12,
    genres: <String>['Action'],
    synopsis: 'Test anime for end-of-episode behaviour.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
  );

  late SettingsStore store;
  late TrailerPlayer trailer;

  dynamic playerState(WidgetTester tester) =>
      tester.state(find.byType(FullPlayerScreen)) as dynamic;

  // Pump the player with a chosen initial episode. By default the
  // initial episode is a COPY of episodes[0] — same number, different
  // instance — exactly what Detail hands the player after a rebuild.
  Future<void> pumpPlayer(WidgetTester tester, {bool copyInitial = true}) async {
    store = await SettingsStore.load();
    await tester.runAsync(() async {
      trailer = TrailerPlayer();
    });
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    final List<Episode> episodes = mockEpisodes(anime);
    final Episode initial = copyInitial
        ? episodes[0].copyWith()
        : episodes.first;
    await tester.pumpWidget(
      MaterialApp(
        home: FullPlayerScreen(
          trailer: trailer,
          store: store,
          anime: anime,
          episodes: episodes,
          initialEpisode: initial,
          // Quiet AniSkip: no real network, no skip segments.
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
  }

  Future<void> endEpisode(WidgetTester tester) async {
    playerState(tester).simulateEndForTest();
    await tester.pump();
  }

  group('nextEpisodeAfter (by number)', () {
    test('finds the next episode from a non-identical instance', () {
      final List<Episode> episodes = mockEpisodes(anime);
      final Episode copy = episodes[0].copyWith();
      expect(identical(copy, episodes[0]), isFalse);
      expect(nextEpisodeAfter(episodes, copy.number)?.number, 2);
      expect(nextEpisodeAfter(episodes, 12), isNull);
      expect(nextEpisodeAfter(episodes, 99), isNull);
    });
  });

  group('end of episode', () {
    testWidgets('autoplay ON: card + countdown, advances to EP 2', (
      WidgetTester tester,
    ) async {
      await pumpPlayer(tester);
      expect(playerState(tester).currentEpisodeForTest, 1);
      await endEpisode(tester);
      expect(find.text('Up next: Episode 2'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.textContaining('Playing in'), findsOneWidget);
      // 5 s countdown elapses -> advances, does NOT restart EP 1.
      await tester.pump(const Duration(seconds: 6));
      expect(playerState(tester).currentEpisodeForTest, 2);
      expect(playerState(tester).autoplayVisibleForTest, isFalse);
    });

    testWidgets('autoplay ON: Cancel stays on EP 1, no auto-advance', (
      WidgetTester tester,
    ) async {
      await pumpPlayer(tester);
      await endEpisode(tester);
      expect(find.text('Up next: Episode 2'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('Up next: Episode 2'), findsNothing);
      expect(playerState(tester).autoplayVisibleForTest, isFalse);
      expect(playerState(tester).currentEpisodeForTest, 1);
      // Past the whole countdown window: still on EP 1.
      await tester.pump(const Duration(seconds: 6));
      expect(playerState(tester).currentEpisodeForTest, 1);
    });

    testWidgets('autoplay OFF: paused card, no countdown, Play now -> EP 2',
        (WidgetTester tester) async {
      await pumpPlayer(tester);
      await store.setAutoplayNext(false);
      await tester.pump();
      await endEpisode(tester);
      expect(find.text('Up next: Episode 2'), findsOneWidget);
      expect(find.text('Paused — tap Play now or Cancel'), findsOneWidget);
      expect(find.textContaining('Playing in'), findsNothing);
      // Waits for the user: no auto-advance.
      await tester.pump(const Duration(seconds: 6));
      expect(playerState(tester).currentEpisodeForTest, 1);
      expect(find.text('Up next: Episode 2'), findsOneWidget);
      await tester.tap(find.text('Play now'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(playerState(tester).currentEpisodeForTest, 2);
      expect(playerState(tester).autoplayVisibleForTest, isFalse);
    });

    testWidgets('EOF with the identical initial episode still shows EP 2',
        (WidgetTester tester) async {
      await pumpPlayer(tester, copyInitial: false);
      await endEpisode(tester);
      expect(find.text('Up next: Episode 2'), findsOneWidget);
    });
  });
}
