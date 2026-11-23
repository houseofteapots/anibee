import 'package:anibee/widgets/glass_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_bottom_nav/liquid_glass_bottom_nav.dart';

/// 0.2.13 Liquid Glass nav: 0.2.12 only copied the package's
/// blur/surface VALUES into a hand-rolled pill, so the phone saw
/// plain transparency ("transparent toh huwa lekin liquid glass
/// type nahi huwa"). The look comes from the package's shader
/// refraction, not values — so 'glass' now renders the REAL
/// `LiquidGlassNavBar` (same forked 0.0.14 package Zeus uses,
/// vendored at packages/liquid_glass_bottom_nav), and 'blurry'
/// keeps the old frosted BackdropFilter pill.
void main() {
  Future<void> pumpNav(
    WidgetTester tester, {
    required String navStyle,
    required bool isDark,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: isDark ? Brightness.dark : Brightness.light,
        ),
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

  testWidgets('glass renders the real package bar, not a fake blur',
      (WidgetTester tester) async {
    await pumpNav(tester, navStyle: 'glass', isDark: true);
    // The package bar itself — shader refraction, not BackdropFilter.
    expect(find.byType(LiquidGlassNavBar), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    final LiquidGlassNavBar bar =
        tester.widget<LiquidGlassNavBar>(find.byType(LiquidGlassNavBar));
    expect(bar.items.length, 5);
    expect(
      bar.items.map((LiquidGlassNavItem i) => i.label).toList(),
      <String>['Home', 'Search', 'Collection', 'Downloads', 'Settings'],
    );
    expect(bar.activeColor, const Color(0xFF34C759));
    expect(bar.selectedIndex, 0);
    expect(bar.insets, 0); // shell already insets 16 pt each side
    expect(bar.borderRadius, GlassNavBar.pillRadius);
    // The thin white rim sits above the glass.
    expect(find.byType(IgnorePointer), findsWidgets);
  });

  testWidgets('glass on a light theme still uses the clear dark pill',
      (WidgetTester tester) async {
    await pumpNav(tester, navStyle: 'glass', isDark: false);
    expect(find.byType(LiquidGlassNavBar), findsOneWidget);
    // The bar is wrapped in a dark-brightness Theme (Zeus's
    // clearNavGlassFor) so the package paints its clear pill
    // instead of the milky light-mode one.
    final Iterable<Theme> themes = tester.widgetList<Theme>(
      find.ancestor(
        of: find.byType(LiquidGlassNavBar),
        matching: find.byType(Theme),
      ),
    );
    expect(
      themes.any((Theme t) => t.data.brightness == Brightness.dark),
      isTrue,
    );
  });

  testWidgets('blurry keeps the frosted BackdropFilter pill',
      (WidgetTester tester) async {
    await pumpNav(tester, navStyle: 'blurry', isDark: true);
    expect(find.byType(LiquidGlassNavBar), findsNothing);
    expect(find.byType(BackdropFilter), findsOneWidget);
    final Container container = tester.widget<Container>(
      find.descendant(
        of: find.byType(BackdropFilter),
        matching: find.byType(Container),
      ),
    );
    final BoxDecoration decoration = container.decoration as BoxDecoration;
    expect(decoration.color, GlassNavBar.blurrySurfaceDark);
    expect(GlassNavBar.blurryBlurSigma, 4.0);
  });
}
