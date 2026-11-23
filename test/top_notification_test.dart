import 'package:anibee/widgets/top_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.8: the top notification replaces every bottom SnackBar — a
/// dark-glass banner at the top with icon + message (+ optional detail
/// line), auto-dismiss after ~3s, tap to dismiss.
void main() {
  Future<void> pumpButton(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return ElevatedButton(
              onPressed: () {
                TopNotification.show(
                  context,
                  'AniList login failed — no token returned.',
                  detail: 'Last page: http://localhost/',
                );
              },
              child: const Text('Show'),
            );
          },
        ),
      ),
    );
  }

  testWidgets('shows message + detail at the top', (WidgetTester tester) async {
    await pumpButton(tester);
    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('AniList login failed — no token returned.'),
      findsOneWidget,
    );
    expect(find.text('Last page: http://localhost/'), findsOneWidget);
    // The banner sits at the top of the screen, not the bottom.
    final Offset topLeft = tester.getTopLeft(
      find.text('AniList login failed — no token returned.'),
    );
    expect(topLeft.dy, lessThan(200));
    TopNotification.hide();
    await tester.pump();
  });

  testWidgets('tap dismisses the banner', (WidgetTester tester) async {
    await pumpButton(tester);
    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('AniList login failed — no token returned.'),
      findsOneWidget,
    );
    await tester.tap(find.text('AniList login failed — no token returned.'));
    await tester.pump();
    expect(
      find.text('AniList login failed — no token returned.'),
      findsNothing,
    );
  });

  testWidgets('auto-dismisses after ~3s', (WidgetTester tester) async {
    await pumpButton(tester);
    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('AniList login failed — no token returned.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(
      find.text('AniList login failed — no token returned.'),
      findsNothing,
    );
  });
}
