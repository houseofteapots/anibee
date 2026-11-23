import 'package:anibee/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'player_skip_times_harness.dart';

/// 0.2.9 in-player episode chooser: the 0.7-height sheet dominated
/// the landscape screen (SPY x FAMILY, 19:43 phone report) — it is
/// now 0.55 of the screen height with tighter padding/spacing and a
/// 16px title. The 5-column grid, accent selected cell and
/// tap-to-select are unchanged.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(configureSkipTestBindings);

  const Anime spy = Anime(
    id: 'sheet-spy',
    title: 'SPY x FAMILY',
    rating: 4.5,
    year: 2022,
    episodeCount: 20,
    genres: <String>['Comedy'],
    synopsis: 'Test anime for the episode sheet size test.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
  );

  testWidgets('episode sheet is compact (0.55 height) and still selects',
      (WidgetTester tester) async {
    final SkipPlayerHarness harness = SkipPlayerHarness();
    await harness.pumpPlayer(tester, anime: spy);

    // The top bar (Episodes button) lives in the controls layer —
    // make sure it is visible before tapping.
    if (!harness.playerState(tester).controlsVisibleForTest) {
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
    }
    expect(
      harness.playerState(tester).controlsVisibleForTest,
      isTrue,
    );

    await tester.tap(find.byTooltip('Episodes'));
    // The tap's onTap fires during the first pump, which only
    // STARTS the sheet's entrance animation — a second pump with
    // duration is needed to advance it (otherwise the sheet sits
    // translated below the viewport and its cells are untappable).
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // Compact sheet: 0.55 of the 600pt test viewport = 330pt
    // (the old 0.7 sheet was 420pt).
    expect(find.text('Episodes — SPY x FAMILY'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is SizedBox && w.height == 330.0,
      ),
      findsOneWidget,
    );
    // The grid still shows all 20 episodes.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);

    // Tap-to-select still works: sheet closes, episode switches.
    // Same double-pump: the first pump processes the tap and starts
    // the sheet's exit animation; the second advances it to done.
    await tester.tap(find.text('5'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Episodes — SPY x FAMILY'), findsNothing);
    expect(harness.playerState(tester).currentEpisodeForTest, 5);

    await harness.disposePlayer(tester);
  });
}
