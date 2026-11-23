import 'package:anibee/widgets/glass_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.9 Liquid Glass nav: the old 'glass' rendered frosted on the
/// phone (milky grey pill, posters blurred behind it), so the
/// frosted look moved to 'blurry' and 'glass' became crystal clear
/// like Zeus's Frost nav (Zeus liquid-glass defaults: glass colour
/// alpha 0, blur 5). The numbers below are the proof: glass surface
/// alpha 0x0A + blur sigma 4 vs blurry surface 0x38 + blur sigma 18.
void main() {
  Color pillColor(WidgetTester tester) {
    final Container container = tester.widget<Container>(
      find.descendant(
        of: find.byType(BackdropFilter),
        matching: find.byType(Container),
      ),
    );
    final BoxDecoration decoration = container.decoration as BoxDecoration;
    return decoration.color!;
  }

  double borderAlpha(WidgetTester tester) {
    final Container container = tester.widget<Container>(
      find.descendant(
        of: find.byType(BackdropFilter),
        matching: find.byType(Container),
      ),
    );
    final BoxDecoration decoration = container.decoration as BoxDecoration;
    final Border border = decoration.border as Border;
    return border.top.color.a;
  }

  Future<void> pumpNav(
    WidgetTester tester, {
    required String navStyle,
    required bool isDark,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlassNavBar(
            currentIndex: 0,
            onTap: (_) {},
            accent: const Color(0xFF34C759),
            isDark: isDark,
            navStyle: navStyle,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('glass is crystal clear, blurry is frosted (dark)', (
    WidgetTester tester,
  ) async {
    // Design values: glass blur 4 (cf. Zeus 5) vs blurry blur 18.
    expect(GlassNavBar.glassBlurSigma, 4.0);
    expect(GlassNavBar.blurryBlurSigma, 18.0);
    expect(
      GlassNavBar.glassBlurSigma,
      lessThan(GlassNavBar.blurryBlurSigma / 4),
    );

    await pumpNav(tester, navStyle: 'glass', isDark: true);
    expect(find.byType(BackdropFilter), findsOneWidget);
    // Glass surface alpha 0x0A (~4%) — near-transparent.
    expect(pillColor(tester).a, closeTo(0x0A / 0xFF, 0.01));
    // Thin bright border on the clear glass.
    expect(borderAlpha(tester), closeTo(0.28, 0.01));

    await pumpNav(tester, navStyle: 'blurry', isDark: true);
    expect(find.byType(BackdropFilter), findsOneWidget);
    // Blurry surface alpha 0x38 (~22%) — the old frosted 'glass'.
    expect(pillColor(tester).a, closeTo(0x38 / 0xFF, 0.01));
    expect(
      pillColor(tester).a,
      greaterThan(GlassNavBar.glassSurfaceDark.a * 4),
    );
  });

  testWidgets('glass is crystal clear, blurry is frosted (light)', (
    WidgetTester tester,
  ) async {
    await pumpNav(tester, navStyle: 'glass', isDark: false);
    expect(pillColor(tester).a, closeTo(0.06, 0.01));

    await pumpNav(tester, navStyle: 'blurry', isDark: false);
    expect(pillColor(tester).a, closeTo(0.30, 0.01));
  });

  testWidgets('both modes keep the same pill shape and icons', (
    WidgetTester tester,
  ) async {
    await pumpNav(tester, navStyle: 'glass', isDark: true);
    final Size size = tester.getSize(
      find.descendant(
        of: find.byType(BackdropFilter),
        matching: find.byType(Container),
      ),
    );
    expect(size.height, 64);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
