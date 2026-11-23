import 'package:anibee/widgets/glass_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.12 Liquid Glass nav: the 0.2.9 "fix" (blur sigma 4, dark
/// surface 0x0A181C20, border 0.28) STILL read as blurry on the
/// phone, so the looks swapped — what 'glass' rendered in
/// 0.2.9–0.2.11 became 'blurry', and 'glass' was rebuilt to
/// crystal clear like Zeus's Frost nav, MEASURED from Zeus
/// (`~/workspace/zeus-v101` + liquid_glass_bottom_nav 0.0.14):
/// dark pill = white 0.04 fill, blur sigma 1, white 0.18 rim
/// (the 0.2.9 comment claiming Zeus uses "blur 5" was wrong —
/// the package uses blur 1). The numbers below are the proof.
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

  testWidgets('glass is crystal clear like Zeus Frost, blurry is frosted (dark)',
      (WidgetTester tester) async {
    // Design values: glass blur 1 (Zeus Frost 1) vs blurry blur 4
    // (the old glass blur).
    expect(GlassNavBar.glassBlurSigma, 1.0);
    expect(GlassNavBar.blurryBlurSigma, 4.0);
    expect(
      GlassNavBar.glassBlurSigma,
      lessThanOrEqualTo(1.0),
    );
    // Blurry is exactly the old Liquid Glass surface.
    expect(GlassNavBar.blurrySurfaceDark, const Color(0x0A181C20));

    await pumpNav(tester, navStyle: 'glass', isDark: true);
    expect(find.byType(BackdropFilter), findsOneWidget);
    // Glass surface: white 0x0A (~4%) — near-transparent, and
    // WHITE, not the old near-black 0x0A181C20 (the "Glass lesson"
    // failure mode: near-black high-alpha renders as a solid card).
    expect(pillColor(tester), GlassNavBar.glassSurfaceDark);
    expect(pillColor(tester).a, closeTo(0x0A / 0xFF, 0.01));
    expect(pillColor(tester).r, greaterThan(0.9));
    // Thin bright Zeus rim on the clear glass.
    expect(borderAlpha(tester), closeTo(0.18, 0.01));

    await pumpNav(tester, navStyle: 'blurry', isDark: true);
    expect(find.byType(BackdropFilter), findsOneWidget);
    // Blurry surface == the 0.2.9–0.2.11 glass surface.
    expect(pillColor(tester), GlassNavBar.blurrySurfaceDark);
    expect(borderAlpha(tester), closeTo(0.28, 0.01));
  });

  testWidgets('glass is dark glass in both themes, blurry frosted (light)',
      (WidgetTester tester) async {
    // The pill is dark glass in BOTH themes when glass is on
    // (Zeus hands light themes a dark brightness too).
    await pumpNav(tester, navStyle: 'glass', isDark: false);
    expect(pillColor(tester), GlassNavBar.glassSurfaceDark);
    expect(pillColor(tester).a, closeTo(0x0A / 0xFF, 0.01));
    expect(borderAlpha(tester), closeTo(0.18, 0.01));

    await pumpNav(tester, navStyle: 'blurry', isDark: false);
    expect(pillColor(tester).a, closeTo(0.30, 0.01));
    expect(borderAlpha(tester), closeTo(0.45, 0.01));
  });

  testWidgets('both modes keep the same pill shape and icons',
      (WidgetTester tester) async {
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
