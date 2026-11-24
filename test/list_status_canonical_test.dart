// 0.2.18: list status is keyed by the CANONICAL key (keyFor),
// not the raw anime.id.
//
// User report 2026-11-24 (video): "Move to To Be Watched" on the
// Gintama card in Continue Watching showed the checkmark, Detail
// showed "To Be Watched", but Collection -> "To Be Watched (1)"
// listed only Demon Slayer. Root cause: the same title has
// DIFFERENT raw ids across entry points — animeFromMedia builds
// id 'anilist-918' while mockCatalogue uses 'gintama', and
// mergeCatalogue replaces the catalogue entry with the synced one,
// so the tab's object reads listStatus['anilist-918'] while the
// sheet wrote listStatus['gintama']. All four sheet options
// (Move to Watching / Finished / To Be Watched / Remove from list)
// failed the same way — only "Remove from Continue Watching"
// worked, because it removes the watch entry, not list status.
//
// Extension (same report, screenshot): "Remove from list" ALSO
// did nothing on its own — setListStatus(id, null) only cleared
// the explicit status, and statusOf's derived branch put a
// started title straight back into Watching (progress /
// currentEpisode). Removal is now explicit (a canonical removal
// marker) and beats the derived branch, without touching watch
// progress or the Continue Watching entry.
import 'dart:convert';

import 'package:anibee/models.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // Gintama as the user actually has it: catalogue shape
  // (id 'gintama') vs synced shape (animeFromMedia id
  // 'anilist-918'). Same title, same anilistId 918 (the catalogue value).
  const Anime gintamaCatalogue = Anime(
    id: 'gintama',
    title: 'Gintama',
    rating: 4.5,
    year: 2006,
    episodeCount: 367,
    genres: <String>['Action', 'Comedy'],
    synopsis: 'Test anime.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    anilistId: 918,
  );
  const Anime gintamaSynced = Anime(
    id: 'anilist-918',
    title: 'Gintama',
    rating: 4.5,
    year: 2006,
    episodeCount: 367,
    genres: <String>['Action', 'Comedy'],
    synopsis: 'Test anime.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    anilistId: 918,
  );

  test('legacy raw-id write is read from the synced shape', () async {
    // A pre-0.2.18 write, persisted under the raw catalogue id —
    // the user's existing 'gintama' -> 'plan' entry. Load must
    // migrate it to the canonical key, so the Collection tab
    // (which reads the synced-shape object) sees it.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'list_status': jsonEncode(<String, String>{'gintama': 'plan'}),
      'saved_ids': <String>['gintama'],
    });
    final SettingsStore store = await SettingsStore.load();
    expect(store.listStatus['al:918'], 'plan');
    expect(store.statusOf(gintamaSynced), 'plan');
    expect(store.statusOf(gintamaCatalogue), 'plan');
  });

  test('every list move reads the same from both id shapes', () async {
    final SettingsStore store = await SettingsStore.load();
    for (final String status in <String>['watching', 'finished', 'plan']) {
      // Write via the synced shape, read via the catalogue shape.
      await store.setListStatus(gintamaSynced, status);
      expect(store.statusOf(gintamaCatalogue), status);
      expect(store.statusOf(gintamaSynced), status);
      // And the reverse direction.
      await store.setListStatus(gintamaCatalogue, status);
      expect(store.statusOf(gintamaSynced), status);
      expect(store.statusOf(gintamaCatalogue), status);
    }
  });

  test('Move to To Be Watched from the Continue Watching sheet lands',
      () async {
    final SettingsStore store = await SettingsStore.load();
    // The user watched Gintama from the catalogue entry, so the
    // watch entry carries animeId 'gintama' — the sheet's anime
    // is entry.toAnime(), id 'gintama', anilistId 918.
    await store.recordWatch(
      anime: gintamaCatalogue,
      episode: 1,
      positionSeconds: 100,
      durationSeconds: 1400,
    );
    final Anime sheetAnime = store.watchHistory.first.toAnime();
    expect(sheetAnime.id, 'gintama');
    await store.setListStatus(sheetAnime, 'plan');
    // The Collection tab reads the merged (synced-shape) object.
    expect(store.statusOf(gintamaSynced), 'plan');
    expect(store.statusOf(gintamaCatalogue), 'plan');
  });

  test('Remove from list clears every tab but keeps progress + entry',
      () async {
    final SettingsStore store = await SettingsStore.load();
    await store.recordWatch(
      anime: gintamaCatalogue,
      episode: 1,
      positionSeconds: 100,
      durationSeconds: 1400,
    );
    await store.setListStatus(gintamaCatalogue, 'watching');
    expect(store.statusOf(gintamaSynced), 'watching');

    await store.setListStatus(gintamaSynced, null);
    // In NO tab now — the derived progress branch must not put
    // the started title back into Watching.
    expect(store.statusOf(gintamaSynced), isNull);
    expect(store.statusOf(gintamaCatalogue), isNull);
    // …but the watch progress and the Continue Watching entry
    // are untouched (only list membership goes).
    expect(store.progressEpisodeFor(gintamaSynced), 1);
    expect(store.watchHistory, hasLength(1));
    expect(store.watchHistory.first.animeId, 'gintama');

    // Re-listing after a removal works again (marker cleared).
    await store.setListStatus(gintamaCatalogue, 'plan');
    expect(store.statusOf(gintamaSynced), 'plan');
  });

  test('toggleSaved round-trips through one canonical entry', () async {
    final SettingsStore store = await SettingsStore.load();
    await store.recordWatch(
      anime: gintamaCatalogue,
      episode: 1,
      positionSeconds: 100,
      durationSeconds: 1400,
    );

    await store.toggleSaved(gintamaCatalogue);
    expect(store.isSaved(gintamaSynced), isTrue);
    expect(store.statusOf(gintamaSynced), 'plan');

    // Unsaving removes it from every list even with progress.
    await store.toggleSaved(gintamaSynced);
    expect(store.isSaved(gintamaCatalogue), isFalse);
    expect(store.statusOf(gintamaSynced), isNull);
    expect(store.progressEpisodeFor(gintamaSynced), 1);
  });
}
