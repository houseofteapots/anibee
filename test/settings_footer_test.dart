import 'package:anibee/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.12 Settings footer: Developer Toji, tappable GitHub link,
/// and the REAL build version (PackageInfo, never a hardcoded
/// string). The `versionLabel` seam lets the test pass a label
/// without the PackageInfo platform channel. The link is NOT
/// tapped in tests (url_launcher platform channel unmocked).
void main() {
  testWidgets('footer renders developer, GitHub, and the real version',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SettingsFooter(versionLabel: '0.2.12+16'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('AniBee 0.2.12+16 • Personal build'), findsOneWidget);
    expect(find.text('Developer Toji'), findsOneWidget);
    expect(find.text('github.com/sezkc16'), findsOneWidget);
  });

  testWidgets('footer without a version still shows developer + GitHub',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SettingsFooter(versionLabel: '')),
      ),
    );
    await tester.pump();

    expect(find.text('AniBee • Personal build'), findsOneWidget);
    expect(find.text('Developer Toji'), findsOneWidget);
    expect(find.text('github.com/sezkc16'), findsOneWidget);
  });
}
