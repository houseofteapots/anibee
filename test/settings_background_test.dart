import 'package:anibee/theme.dart';
import 'package:anibee/widgets/settings_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.8: the Settings background is a dark blurred poster collage in
/// dark mode, and the plain background in light mode (the mockup is
/// dark-only). The collage sources the posters the app already
/// fetches — the catalogue URLs — so it costs no extra fetch.
void main() {
  Future<void> pumpBackground(
    WidgetTester tester,
    ThemeMode mode,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(Colors.green),
        darkTheme: AppTheme.dark(Colors.green),
        themeMode: mode,
        home: const Scaffold(body: SettingsBackground()),
      ),
    );
    await tester.pump();
  }

  testWidgets('dark mode shows the poster collage grid', (
    WidgetTester tester,
  ) async {
    await pumpBackground(tester, ThemeMode.dark);
    expect(find.byType(GridView), findsOneWidget);
    // The collage is blurred + darkened (BackdropFilter over the grid).
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('light mode keeps the plain background', (
    WidgetTester tester,
  ) async {
    await pumpBackground(tester, ThemeMode.light);
    expect(find.byType(GridView), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
