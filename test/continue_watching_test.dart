import 'package:anibee/models.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.3: Continue Watching must be driven by REAL persisted progress
/// — the row showed mock values (Solo Leveling EP 7, JJK EP 5, Demon
/// Slayer EP 5) while the user had actually watched JJK EP 1 and
/// Chainsaw Man EP 2. These tests pin the real-progress behaviour:
/// record → history entry, resume round-trip across a fresh store
/// instance, canonical identity (Home id vs Search id), most-recent
/// ordering, and Clear All.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Anime anime({
    required String id,
    int? anilistId,
    String title = 'JUJUTSU KAISEN',
  }) {
    return Anime(
      id: id,
      title: title,
      rating: 8.5,
      year: 2023,
      episodeCount: 24,
      genres: const <String>['Action'],
      synopsis: '',
      gradient: const <Color>[Colors.black],
      anilistId: anilistId,
    );
  }

  late SettingsStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = await SettingsStore.load();
  });

  test('recordWatch creates a real entry (episode, position, minutes left)', () async {
    final Anime jjk = anime(id: 'jujutsu-kaisen', anilistId: 113415);
    await store.recordWatch(
      anime: jjk,
      episode: 1,
      positionSeconds: 332,
      durationSeconds: 1420,
    );
    expect(store.watchHistory, hasLength(1));
    final WatchEntry entry = store.watchHistory.first;
    expect(entry.episode, 1);
    expect(entry.positionSeconds, 332);
    expect(entry.durationSeconds, 1420);
    // (1420 - 332) / 60 = 18.13 -> ceil = 19 minutes left.
    expect(entry.minutesLeft, 19);
    expect(entry.title, 'JUJUTSU KAISEN');
    expect(entry.key, 'al:113415');
    expect(entry.progress, closeTo(332 / 1420, 0.001));
  });

  test('resume position round-trips across a fresh store instance', () async {
    final Anime jjk = anime(id: 'jujutsu-kaisen', anilistId: 113415);
    await store.setResumeSeconds(store.resumeKeyFor(jjk, 1), 332);
    await store.recordWatch(
      anime: jjk,
      episode: 1,
      positionSeconds: 332,
      durationSeconds: 1420,
    );

    // A fresh store reading the same persisted prefs sees the same
    // position — this is what the player restores on return.
    final SettingsStore reopened = await SettingsStore.load();
    expect(reopened.resumePositionFor(jjk, 1), 332);
    expect(reopened.progressEpisodeFor(jjk), 1);
    expect(reopened.watchHistory, hasLength(1));
    expect(reopened.watchHistory.first.episode, 1);
  });

  test('Home id and Search id share one canonical key', () async {
    // Home opens JJK as 'jujutsu-kaisen'; Search opens the same title
    // as 'anilist-113415'. Both carry anilistId 113415, so progress
    // recorded under one must be visible under the other.
    final Anime fromHome = anime(id: 'jujutsu-kaisen', anilistId: 113415);
    final Anime fromSearch = anime(id: 'anilist-113415', anilistId: 113415);
    expect(SettingsStore.keyFor(fromHome), SettingsStore.keyFor(fromSearch));
    expect(SettingsStore.keyFor(fromHome), 'al:113415');

    await store.setResumeSeconds(store.resumeKeyFor(fromHome, 1), 120);
    expect(store.resumePositionFor(fromSearch, 1), 120);
    expect(store.progressEpisodeFor(fromSearch), isNull);

    await store.recordWatch(
      anime: fromHome,
      episode: 1,
      positionSeconds: 120,
      durationSeconds: 1400,
    );
    expect(store.progressEpisodeFor(fromSearch), 1);
  });

  test('playing episodes then leaving updates the row, most recent first', () async {
    // The user's real case: JJK EP 1, then Chainsaw Man EP 2.
    final Anime jjk = anime(id: 'jujutsu-kaisen', anilistId: 113415);
    final Anime csm = anime(
      id: 'chainsaw-man',
      anilistId: 131681,
      title: 'Chainsaw Man',
    );
    await store.recordWatch(
      anime: jjk,
      episode: 1,
      positionSeconds: 300,
      durationSeconds: 1400,
    );
    await store.recordWatch(
      anime: csm,
      episode: 2,
      positionSeconds: 600,
      durationSeconds: 1400,
    );
    expect(store.watchHistory, hasLength(2));
    expect(store.watchHistory.first.title, 'Chainsaw Man');
    expect(store.watchHistory.first.episode, 2);
    expect(store.watchHistory.last.title, 'JUJUTSU KAISEN');
    expect(store.watchHistory.last.episode, 1);

    // Re-watching JJK moves it back to the front, same episode.
    await store.recordWatch(
      anime: jjk,
      episode: 1,
      positionSeconds: 900,
      durationSeconds: 1400,
    );
    expect(store.watchHistory, hasLength(2));
    expect(store.watchHistory.first.title, 'JUJUTSU KAISEN');
    expect(store.watchHistory.first.positionSeconds, 900);
  });

  test('markProgress keeps the resume episode in step', () async {
    final Anime jjk = anime(id: 'jujutsu-kaisen', anilistId: 113415);
    await store.markProgress(jjk, 3);
    expect(store.progressEpisodeFor(jjk), 3);
  });

  test('clearWatchHistory empties the row and the resume episode', () async {
    final Anime jjk = anime(id: 'jujutsu-kaisen', anilistId: 113415);
    await store.recordWatch(
      anime: jjk,
      episode: 1,
      positionSeconds: 300,
      durationSeconds: 1400,
    );
    await store.markProgress(jjk, 1);
    expect(store.watchHistory, isNotEmpty);

    await store.clearWatchHistory();
    expect(store.watchHistory, isEmpty);
    expect(store.progressEpisodeFor(jjk), isNull);

    final SettingsStore reopened = await SettingsStore.load();
    expect(reopened.watchHistory, isEmpty);
  });
}
