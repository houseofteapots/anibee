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
    // Phone-size surface (390x844): the shell Stack must be the
    // full phone screen or the 844-tall box gets clamped to the
    // default 800x600 test viewport and the bottom: 20 math breaks.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

  /// 0.2.14 REGRESSION ("navigation hi gayeb?", user 2026-11-24
  /// 01:00): the 0.2.13 glass branch wrapped the package bar in a
  /// Stack whose children were ALL positioned (the bar's root
  /// `Positioned` + the rim's `Positioned.fill`), so the Stack sized
  /// to 0x0 and `Clip.hardEdge` clipped the whole nav away on the
  /// phone — the 0.2.13 tests only checked the bar was PRESENT,
  /// never its size. These tests pump the nav the way app_shell does
  /// (Stack + Positioned left:16 / right:16 / bottom:20) and assert
  /// REAL geometry — height, position, tappability — not presence.
  Future<void> pumpNavInShell(
    WidgetTester tester, {
    required String navStyle,
    required bool isDark,
    required ValueChanged<int> onTap,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    // Same phone-size surface as pumpNav — the shell Stack must be
    // the full 390x844 screen or the box clamps to the 800x600 test
    // viewport and the bottom: 20 math breaks.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: isDark ? Brightness.dark : Brightness.light,
        ),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(padding: padding),
            child: SizedBox(
              width: 390,
              height: 844,
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 20,
                    child: GlassNavBar(
                      currentIndex: 0,
                      onTap: onTap,
                      accent: const Color(0xFF34C759),
                      isDark: isDark,
                      navStyle: navStyle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('0.2.14: glass nav has real 63pt height in the shell',
      (WidgetTester tester) async {
    await pumpNavInShell(
      tester,
      navStyle: 'glass',
      isDark: true,
      onTap: (_) {},
    );
    final Rect rect = tester.getRect(find.byType(GlassNavBar));
    expect(rect.height, GlassNavBar.glassPillHeight); // 63, never 0
    expect(rect.width, 358); // 390 - 16 - 16
    // Bottom edge sits exactly at the shell's bottom: 20.
    expect(rect.bottom, 844 - 20);
  });

  testWidgets(
      '0.2.14: glass nav keeps its height with home-indicator padding',
      (WidgetTester tester) async {
    await pumpNavInShell(
      tester,
      navStyle: 'glass',
      isDark: true,
      onTap: (_) {},
      padding: const EdgeInsets.only(bottom: 34),
    );
    final Rect rect = tester.getRect(find.byType(GlassNavBar));
    expect(rect.height, GlassNavBar.glassPillHeight);
    expect(rect.bottom, 844 - 20);
  });

  testWidgets('0.2.14: glass nav items are tappable',
      (WidgetTester tester) async {
    int tapped = -1;
    await pumpNavInShell(
      tester,
      navStyle: 'glass',
      isDark: true,
      onTap: (int i) => tapped = i,
    );
    // Two 'Search' labels exist (base layer + package bar, same
    // spot) — tap the coordinate; the topmost (package bar) must
    // answer.
    await tester.tapAt(
      tester.getCenter(find.text('Search').first),
    );
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('0.2.14: glass base layer is present under the package bar',
      (WidgetTester tester) async {
    await pumpNavInShell(
      tester,
      navStyle: 'glass',
      isDark: true,
      onTap: (_) {},
    );
    // The base pill (no BackdropFilter) is the fallback if the
    // package shader ever paints nothing — and it is what gives the
    // glass Stack its non-zero height.
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(LiquidGlassNavBar), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
  });

  testWidgets('0.2.14: blurry nav keeps 64pt height and taps work',
      (WidgetTester tester) async {
    int tapped = -1;
    await pumpNavInShell(
      tester,
      navStyle: 'blurry',
      isDark: true,
      onTap: (int i) => tapped = i,
    );
    final Rect rect = tester.getRect(find.byType(GlassNavBar));
    expect(rect.height, 64);
    expect(rect.bottom, 844 - 20);
    await tester.tapAt(
      tester.getCenter(find.text('Downloads').first),
    );
    await tester.pump();
    expect(tapped, 3);
  });

  /// 0.2.15 OPAQUE PILL (user 2026-11-24 01:21, from his 0.2.14
  /// phone test: "navigation k andar k icon ka reflect naho"): the
  /// 0.2.14 glass pill's ~4% fill let the poster grid bleed through
  /// behind the nav icons (year/episodes text visible behind them).
  /// The pill surface is now FULLY OPAQUE in both styles — dark
  /// 0xFF181C20 / solid white light — so no scrolling content can
  /// show behind the icons. Geometry, tabs and tappability are
  /// unchanged (the 0.2.14 tests above still cover them).
  group('0.2.15 opaque pill — no content behind the icons', () {
    testWidgets('blurry dark pill surface is opaque',
        (WidgetTester tester) async {
      await pumpNav(tester, navStyle: 'blurry', isDark: true);
      expect(GlassNavBar.blurrySurfaceDark.a, 1.0);
      final Container container = tester.widget<Container>(
        find.descendant(
          of: find.byType(BackdropFilter),
          matching: find.byType(Container),
        ),
      );
      final Color? color = (container.decoration as BoxDecoration).color;
      expect(color, GlassNavBar.blurrySurfaceDark);
      expect(color!.a, 1.0);
    });

    testWidgets('blurry light pill surface is opaque',
        (WidgetTester tester) async {
      await pumpNav(tester, navStyle: 'blurry', isDark: false);
      final Container container = tester.widget<Container>(
        find.descendant(
          of: find.byType(BackdropFilter),
          matching: find.byType(Container),
        ),
      );
      final Color? color = (container.decoration as BoxDecoration).color;
      expect(color, Colors.white);
      expect(color!.a, 1.0);
    });

    testWidgets('glass dark base layer is opaque',
        (WidgetTester tester) async {
      await pumpNavInShell(
        tester,
        navStyle: 'glass',
        isDark: true,
        onTap: (_) {},
      );
      // The base pill is the _buildPill Container whose fill is
      // blurrySurfaceDark — it sits behind the package bar's own
      // translucent fill and blocks everything behind it.
      final Iterable<Container> bases = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color ==
                  GlassNavBar.blurrySurfaceDark,
        ),
      );
      expect(bases, isNotEmpty);
      for (final Container c in bases) {
        expect((c.decoration as BoxDecoration).color!.a, 1.0);
      }
    });

    testWidgets('glass light base layer is opaque',
        (WidgetTester tester) async {
      await pumpNavInShell(
        tester,
        navStyle: 'glass',
        isDark: false,
        onTap: (_) {},
      );
      final Iterable<Container> bases = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == Colors.white,
        ),
      );
      expect(bases, isNotEmpty);
      for (final Container c in bases) {
        expect((c.decoration as BoxDecoration).color!.a, 1.0);
      }
    });
  });
}
