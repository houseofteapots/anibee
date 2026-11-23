import 'package:anibee/models.dart';
import 'package:anibee/settings_store.dart';
import 'package:anibee/widgets/episode_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.12 grid white glitch: AniList `episodes` is null for
/// unreleased seasons (Black Clover Season 2 from AIRING SOON) so
/// episodeCount is 0, mockEpisodes generates 0 episodes, and tapping
/// the grid toggle called `_rangeLabel` with total 0 — `(100).clamp
/// (1, 0)` THROWS ArgumentError and the whole section build failed
/// (release-mode blank grey area + endless scroll). Now: zero
/// episodes show the airing empty state (upcoming EP + air date),
/// the grid toggle is hidden, and `_rangeLabel` never throws.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  const Anime airingSeason = Anime(
    id: 'black-clover-s2',
    title: 'Black Clover Season 2',
    rating: 4.2,
    year: 2026,
    episodeCount: 0,
    genres: <String>['Action'],
    synopsis: 'Unreleased season.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    anilistId: 97940,
    nextEpisode: 9,
    nextEpisodeIn: '6d 20h',
    nextEpisodeAt: 'Nov 29 at 22:05',
  );

  const Anime noInfo = Anime(
    id: 'no-info',
    title: 'Untitled Season',
    rating: 4.0,
    year: 2026,
    episodeCount: 0,
    genres: <String>['Action'],
    synopsis: 'No airing info.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
  );

  Future<void> pumpSection(
    WidgetTester tester,
    Anime anime,
    List<Episode> episodes,
  ) async {
    // 0.2.17: the section is a fixed header + scrolling ListView —
    // the surface itself must be tall (800x3000, like the airing
    // harness) for below-fold rows to be built. A tall SizedBox
    // inside the default 600pt window does NOT work: the box is
    // clamped to the window and the ListView only builds ~one
    // window of children.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final SettingsStore store = await SettingsStore.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 3000,
            child: EpisodeSection(
              anime: anime,
              episodes: episodes,
              store: store,
              onPlay: (_) {},
              onToggleDownload: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('zero episodes shows the airing empty state, no toggle', (
    WidgetTester tester,
  ) async {
    await pumpSection(tester, airingSeason, <Episode>[]);
    expect(find.text('No episodes yet'), findsOneWidget);
    expect(find.text("Episode 9 hasn't aired yet"), findsOneWidget);
    expect(find.text('Airs Nov 29 at 22:05 · in 6d 20h'), findsOneWidget);
    // No grid toggle, no range controls, no dead "0 Episodes".
    expect(find.text('0 Episodes'), findsNothing);
    expect(find.byTooltip('Show as grid'), findsNothing);
    expect(find.byTooltip('Show as cards'), findsNothing);
  });

  testWidgets('zero episodes without airing info is neutral', (
    WidgetTester tester,
  ) async {
    await pumpSection(tester, noInfo, <Episode>[]);
    expect(find.text('No episodes yet'), findsOneWidget);
    expect(find.text('No episodes available yet'), findsOneWidget);
    expect(find.text("hasn't aired yet"), findsNothing);
  });

  testWidgets('non-empty list still renders the grid + toggle', (
    WidgetTester tester,
  ) async {
    const Anime longAnime = Anime(
      id: 'long',
      title: 'Long Anime',
      rating: 4.0,
      year: 2020,
      episodeCount: 30,
      genres: <String>['Action'],
      synopsis: 'Test anime.',
      gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    );
    await pumpSection(tester, longAnime, mockEpisodes(longAnime));
    expect(find.text('30 Episodes'), findsOneWidget);
    expect(find.byTooltip('Show as cards'), findsOneWidget);
    expect(find.text('001-030'), findsOneWidget);
  });

  testWidgets('aired episodes show + upcoming EP banner (0.2.13)', (
    WidgetTester tester,
  ) async {
    // A currently-airing series: 8 episodes have aired (next EP
    // is 9), so the list shows 1–8 AND the next-episode countdown
    // bar — never the empty state.
    const Anime airingNow = Anime(
      id: 'airing-now',
      title: 'Airing Show',
      rating: 4.2,
      year: 2026,
      episodeCount: 8,
      genres: <String>['Action'],
      synopsis: 'Currently airing.',
      gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
      anilistId: 12345,
      nextEpisode: 9,
      nextEpisodeIn: '6d 20h',
      nextEpisodeAt: 'Nov 29 at 22:05',
    );
    await pumpSection(tester, airingNow, mockEpisodes(airingNow));
    expect(find.text('8 Episodes'), findsOneWidget);
    expect(find.text('No episodes yet'), findsNothing);
    expect(find.text('No episodes available yet'), findsNothing);
    expect(find.text('Episode 9 in 6d 20h · Nov 29 at 22:05'), findsOneWidget);
  });
}
