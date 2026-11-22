import 'package:anibee/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// M1.1 catalogue checks: 39 real titles, unique ids, every card has a
/// real poster URL, and search (title + genre) finds real titles.
void main() {
  group('mockCatalogue (M1.1 real titles)', () {
    final List<Anime> catalogue = mockCatalogue();

    test('has 39 titles', () {
      expect(catalogue.length, 39);
    });

    test('ids are unique', () {
      final Set<String> ids = catalogue.map((Anime a) => a.id).toSet();
      expect(ids.length, catalogue.length);
    });

    test('every title has a real http(s) poster URL', () {
      for (final Anime anime in catalogue) {
        expect(
          anime.posterUrl,
          isNotNull,
          reason: '${anime.title} has no posterUrl',
        );
        expect(
          anime.posterUrl,
          startsWith('http'),
          reason: '${anime.title} poster is not a URL',
        );
      }
    });

    test('no M1 mock titles remain', () {
      const List<String> mockTitles = <String>[
        'Demon Crest',
        'Spy×Codex',
        'Jujutsu Warden',
        'Cyber Ninja',
        'Skybound Sailors',
        'Summer Phantom',
      ];
      for (final String title in mockTitles) {
        expect(
          catalogue.any((Anime a) => a.title == title),
          isFalse,
          reason: 'mock title $title still in catalogue',
        );
      }
    });

    test('search finds real titles by name', () {
      List<Anime> search(String query) {
        final String q = query.toLowerCase();
        return catalogue
            .where(
              (Anime a) =>
                  a.title.toLowerCase().contains(q) ||
                  a.genres.any((String g) => g.toLowerCase().contains(q)),
            )
            .toList();
      }

      expect(
        search('one piece').map((Anime a) => a.title),
        contains('One Piece'),
      );
      expect(
        search('solo').map((Anime a) => a.title),
        contains('Solo Leveling'),
      );
      expect(search('sports'), isNotEmpty);
      expect(search('zzz-no-such-anime'), isEmpty);
    });

    test('long anime keeps the number-grid shape', () {
      final Anime onePiece =
          catalogue.firstWhere((Anime a) => a.title == 'One Piece');
      expect(onePiece.episodeCount, greaterThanOrEqualTo(300));
    });
  });
}
