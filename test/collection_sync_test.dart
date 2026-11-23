import 'package:anibee/models.dart';
import 'package:anibee/screens/collection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.11: Collection merges the bundled catalogue with the
/// AniList-synced titles — a synced title with the same AniList id
/// wins (fresher metadata), everything else is appended, and nothing
/// is duplicated.
void main() {
  Anime anime(String id, {int? anilistId, String title = 'Anime'}) => Anime(
    id: id,
    title: title,
    rating: 4.0,
    year: 2024,
    episodeCount: 12,
    genres: const <String>['Action'],
    synopsis: 'Test.',
    gradient: const <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    anilistId: anilistId,
  );

  test('synced entry replaces the catalogue entry with the same id', () {
    final Anime catalogueJjk = anime('anilist-113415', anilistId: 113415);
    final Anime syncedJjk = anime(
      'anilist-113415',
      anilistId: 113415,
      title: 'Jujutsu Kaisen (synced)',
    );
    final List<Anime> merged = CollectionScreen.mergeCatalogue(
      <Anime>[catalogueJjk, anime('anilist-1', anilistId: 1)],
      <Anime>[syncedJjk],
    );
    expect(merged.length, 2);
    expect(merged.first.title, 'Jujutsu Kaisen (synced)');
  });

  test('synced-only titles are appended, no duplicates', () {
    final List<Anime> merged = CollectionScreen.mergeCatalogue(
      <Anime>[anime('anilist-1', anilistId: 1)],
      <Anime>[
        anime('anilist-2', anilistId: 2),
        anime('anilist-2', anilistId: 2),
      ],
    );
    expect(merged.length, 2);
    expect(merged.map((Anime a) => a.anilistId), <int>[1, 2]);
  });

  test('empty synced list returns the catalogue unchanged', () {
    final List<Anime> catalogue = <Anime>[
      anime('anilist-1', anilistId: 1),
      anime('anilist-2', anilistId: 2),
    ];
    expect(CollectionScreen.mergeCatalogue(catalogue, <Anime>[]), catalogue);
  });
}
