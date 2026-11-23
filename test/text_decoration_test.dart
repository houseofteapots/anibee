// YELLOW UNDERLINE (0.2.10, item 3): hardening — the user reports a
// yellow line under text (splash wordmark, then the top-banner
// "Logged out of AniList." text). No Dart code in the app draws a
// decoration, and the line does NOT reproduce in the VM — so this
// test pins the hardening in place: the theme's text styles and the
// banner Texts must resolve with decoration NONE, dark + light.
// The phone test is the authority; this test only proves the
// hardening landed.
import 'package:anibee/theme.dart';
import 'package:anibee/widgets/top_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('theme text styles resolve with no decoration', () {
    for (final (String name, ThemeData theme) in <(String, ThemeData)>[
      ('dark', AppTheme.dark(Colors.blue)),
      ('light', AppTheme.light(Colors.blue)),
    ]) {
      test('$name: bodyMedium + titleLarge + bodySmall are none', () {
        final TextTheme textTheme = theme.textTheme;
        expect(textTheme.bodyMedium?.decoration, TextDecoration.none);
        expect(textTheme.titleLarge?.decoration, TextDecoration.none);
        expect(textTheme.bodySmall?.decoration, TextDecoration.none);
      });
    }
  });

  group('TopNotification banner Texts', () {
    testWidgets('message + detail Texts have decoration none', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () {
                  TopNotification.show(
                    context,
                    'Logged out of AniList.',
                    detail: 'Tap to log in again',
                  );
                },
                child: const Text('Show banner'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Show banner'));
      await tester.pump();

      expect(find.text('Logged out of AniList.'), findsOneWidget);
      expect(find.text('Tap to log in again'), findsOneWidget);

      final Text messageText =
          tester.widget<Text>(find.text('Logged out of AniList.'));
      expect(messageText.style?.decoration, TextDecoration.none);
      final Text detailText =
          tester.widget<Text>(find.text('Tap to log in again'));
      expect(detailText.style?.decoration, TextDecoration.none);

      TopNotification.hide();
      await tester.pump();
    });
  });
}
