import 'package:anibee/services/anilist_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.8 season selector: the chain builder is pure — a walked map of
/// season nodes (id → info + prequel/sequel neighbour ids) orders
/// into Season 1..N. No network here; fetchSeasons does the walking.
void main() {
  SeasonNode node(
    int id,
    int episodes, {
    int? prequelId,
    int? sequelId,
    String format = 'TV',
  }) {
    return SeasonNode(
      info: SeasonInfo(
        id: id,
        title: 'Season $id',
        format: format,
        episodes: episodes,
      ),
      prequelId: prequelId,
      sequelId: sequelId,
    );
  }

  group('buildSeasonChain', () {
    test('linear chain orders from Season 1', () {
      final Map<int, SeasonNode> byId = <int, SeasonNode>{
        1: node(1, 13, sequelId: 2),
        2: node(2, 25, prequelId: 1, sequelId: 3),
        3: node(3, 25, prequelId: 2),
      };
      final List<SeasonInfo> chain = AniListService.buildSeasonChain(2, byId);
      expect(chain.map((SeasonInfo s) => s.id).toList(), <int>[1, 2, 3]);
    });

    test('starting from the last season still finds Season 1', () {
      final Map<int, SeasonNode> byId = <int, SeasonNode>{
        1: node(1, 13, sequelId: 2),
        2: node(2, 25, prequelId: 1, sequelId: 3),
        3: node(3, 25, prequelId: 2),
      };
      final List<SeasonInfo> chain = AniListService.buildSeasonChain(3, byId);
      expect(chain.map((SeasonInfo s) => s.id).toList(), <int>[1, 2, 3]);
    });

    test('single season means no selector (empty chain)', () {
      final Map<int, SeasonNode> byId = <int, SeasonNode>{1: node(1, 12)};
      expect(AniListService.buildSeasonChain(1, byId), isEmpty);
    });

    test('movies and zero-episode entries are not seasons', () {
      final Map<int, SeasonNode> byId = <int, SeasonNode>{
        1: node(1, 13, sequelId: 2),
        2: node(2, 25, prequelId: 1, sequelId: 9),
        // A movie sequel in the middle of the chain.
        9: node(9, 1, prequelId: 2, sequelId: 3, format: 'MOVIE'),
        3: node(3, 25, prequelId: 9),
      };
      final List<SeasonInfo> chain = AniListService.buildSeasonChain(2, byId);
      expect(chain.map((SeasonInfo s) => s.id).toList(), <int>[1, 2, 3]);
    });

    test('a cycle cannot loop forever', () {
      final Map<int, SeasonNode> byId = <int, SeasonNode>{
        1: node(1, 13, prequelId: 2, sequelId: 2),
        2: node(2, 25, prequelId: 1, sequelId: 1),
      };
      final List<SeasonInfo> chain = AniListService.buildSeasonChain(1, byId);
      expect(chain.length, 2);
    });
  });
}
