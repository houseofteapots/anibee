import 'package:anibee/models.dart';
import 'package:anibee/widgets/poster.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.3: search results rendered BLANK on the phone — "20 results for
/// 'one piece'" but the grid below was empty. The grid feeds PosterCard
/// with width: double.infinity (same as Collection), and PosterCard
/// computed the poster height as `width * 1.35` = infinity, so the
/// layout failed and every card rendered as nothing in release builds.
/// Home's grid works because it uses its own _GridCard (Expanded).
void main() {
  group('PosterCard in a search-style grid', () {
    final List<Anime> results = mockCatalogue().take(6).toList();

    Future<void> pumpGrid(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.62,
              ),
              itemCount: results.length,
              itemBuilder: (BuildContext context, int index) {
                return PosterCard(
                  anime: results[index],
                  width: double.infinity,
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('renders each result title + poster', (WidgetTester tester) async {
      await pumpGrid(tester);
      // Title appears twice per card (PosterArt overlay + card label).
      expect(find.text('SOLO LEVELING'), findsWidgets);
      expect(find.text('JUJUTSU KAISEN'), findsWidgets);
      expect(find.text('ONE PIECE'), findsWidgets);
      expect(find.byType(PosterArt), findsNWidgets(6));
    });

    testWidgets('poster art has a finite, non-zero size', (
      WidgetTester tester,
    ) async {
      await pumpGrid(tester);
      final Size size = tester.getSize(find.byType(PosterArt).first);
      expect(size.width, greaterThan(50));
      expect(size.height, greaterThan(50));
      expect(size.height.isFinite, isTrue);
    });
  });
}
