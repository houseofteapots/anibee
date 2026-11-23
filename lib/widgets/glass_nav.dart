import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:liquid_glass_bottom_nav/liquid_glass_bottom_nav.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

import 'reicon_icon.dart';

/// The bottom navigation pill — the ONLY liquid-glass surface in the app.
/// Dark mode cards everywhere else are solid; this pill is translucent blur.
/// Positioned talks directly to the Stack (never wrap in Transform/Padding).
///
/// [navStyle] (Settings → Appearance): 'glass' = Liquid Glass — the REAL
/// `liquid_glass_bottom_nav` 0.0.14 package (same forked package Zeus
/// uses, vendored at packages/liquid_glass_bottom_nav); 'blurry' = the
/// frosted BackdropFilter look. (0.2.12: 'glass' only copied the
/// package's blur/surface VALUES into a hand-rolled pill, so the phone
/// saw plain transparency — the liquid-glass look comes from the
/// package's shader refraction, not from values. 0.2.13 uses the
/// package itself.)
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.accent,
    required this.isDark,
    this.navStyle = 'glass',
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color accent;
  final bool isDark;
  final String navStyle;

  /// Frosted design values — the blur sigma 4 of the 0.2.9–0.2.11
  /// 'glass' look, kept as the 'blurry' option (the default). The
  /// old blurry (colour-matrix + blur 18 over 0x38) is retired.
  ///
  /// 0.2.15: the dark surface is FULLY OPAQUE (0xFF181C20 — same
  /// RGB as the old 0x0A181C20, alpha 1.0). The user reported the
  /// poster grid bleeding through the pill behind the nav icons
  /// ("navigation k andar k icon ka reflect naho") — the old 4%
  /// fill let scrolling content show through. Readability wins
  /// over the see-through effect: no content may show behind the
  /// icons in either style.
  static const double blurryBlurSigma = 4.0;
  static const Color blurrySurfaceDark = Color(0xFF181C20);

  /// Pill geometry, shared by both styles so switching nav styles
  /// never moves the pill: 63 pt tall (the package's fixed height),
  /// radius 32 (AniBee's stadium pill), 16 pt side margins from the
  /// app shell's Positioned.
  static const double pillRadius = 32.0;

  /// Height of the Liquid Glass pill — the package bar's fixed
  /// 63 pt. The glass branch is built on a SizedBox of exactly this
  /// height (0.2.14) so the nav can NEVER collapse to zero height.
  static const double glassPillHeight = 63.0;

  // Navigation icons are Reicon Outline (reicon.dev, MIT) — no generic
  // Material icons on the nav pill.
  static final List<_NavItem> _items = <_NavItem>[
    _NavItem(Reicon.outline.home, 'Home'),
    _NavItem(Reicon.outline.search, 'Search'),
    _NavItem(Reicon.outline.bookmark, 'Collection'),
    _NavItem(Reicon.outline.download, 'Downloads'),
    _NavItem(Reicon.outline.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    if (navStyle != 'blurry') return _buildLiquidGlass(context);
    return _buildBlurry();
  }

  /// Liquid Glass (0.2.13, fixed 0.2.14): the real package bar — the
  /// same `LiquidGlassNavBar` Zeus renders. Its dark-mode pill is the
  /// clear one (4% fill); its light-mode pill is milky (76% white
  /// fill), so on light themes the bar is handed a dark brightness
  /// (Zeus's `clearNavGlassFor`) to get the same clear glass, and
  /// the icons use the dark set. A thin white 0.18 rim is overlaid
  /// on the pill's exact outline (Zeus's `_NavPillRim`). The shell
  /// already insets the pill 16 pt on each side, so the package's
  /// own `insets` is 0.
  ///
  /// 0.2.14 REGRESSION FIX (user 2026-11-24 01:00: "navigation hi
  /// gayeb?"): the package bar's build returns a `Positioned`
  /// (left/right/bottom, no top/height) — it is designed as a DIRECT
  /// child of the screen Stack, as in Zeus. 0.2.13 wrapped it in an
  /// intermediate `Stack` whose children were BOTH positioned (the
  /// bar + the rim's `Positioned.fill`), so that Stack sized to 0x0
  /// and its default `Clip.hardEdge` clipped the whole nav away on
  /// the phone. Fixed three ways, all in this method:
  /// (1) the branch is a `SizedBox` of exactly `glassPillHeight` and
  /// its first child is the frosted pill as a NON-positioned base
  /// layer, so the Stack takes its height from it — the nav can never
  /// collapse to zero height again;
  /// (2) the package bar is handed a MediaQuery with bottom padding
  /// zeroed, so its internal `Positioned(bottom: padding.bottom)` is
  /// bottom: 0 and the pill fills this box exactly, bottom-aligned
  /// with the blurry pill (the shell's bottom: 20 already handles
  /// the home indicator);
  /// (3) the base layer has no BackdropFilter — the glass shader does
  /// the refraction over it, and if the shader ever paints nothing on
  /// a device the plain pill + border still show. `clipBehavior:
  /// Clip.none` is belt and braces so the nav can never be clipped
  /// away again.
  ///
  /// 0.2.16: the base layer is BACKGROUND-ONLY (surface + border +
  /// sheen, no buttons — see `_buildPill`'s `includeButtons`). It
  /// used to render the same five `_NavButton`s the package bar
  /// renders, so every icon + label appeared TWICE, slightly offset
  /// — the "reflection" the user saw on 0.2.15 (the base copy showed
  /// through the package bar's translucent fill). The package bar is
  /// now the ONLY item renderer in the 'glass' style.
  Widget _buildLiquidGlass(BuildContext context) {
    final LiquidGlassNavBar bar = LiquidGlassNavBar(
      items: <LiquidGlassNavItem>[
        for (final _NavItem item in _items)
          LiquidGlassNavItem(
            id: item.label,
            label: item.label,
            // No explicit colour — ReiconIcon falls back to the
            // package's IconTheme, so the package drives the
            // active (accent) / inactive colours.
            iconWidget: ReiconIcon(item.icon, size: 24),
          ),
      ],
      selectedIndex: currentIndex,
      onTap: onTap,
      activeColor: accent,
      inactiveColor: isDark
          ? const Color(0xFFC7C7D1)
          : const Color(0xFF6E6E80),
      iconSize: 24,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        // Clear glass over a poster: a soft light halo keeps the
        // label readable without tinting the pill (Zeus).
        shadows: const <Shadow>[
          Shadow(color: Color(0xCCFFFFFF), blurRadius: 4),
        ],
      ),
      insets: 0,
      borderRadius: pillRadius,
    );
    final Widget glass = isDark
        ? bar
        : Theme(
            data: Theme.of(context).copyWith(brightness: Brightness.dark),
            child: bar,
          );
    // Zero the bottom padding for the package bar only (see the
    // 0.2.14 note above) — the shell's bottom: 20 is the only offset.
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final Widget glassInBox = MediaQuery(
      data: mediaQuery.copyWith(
        padding: mediaQuery.padding.copyWith(bottom: 0.0),
      ),
      child: glass,
    );
    return SizedBox(
      height: glassPillHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // BASE LAYER (0.2.16): background ONLY — surface + border +
          // sheen, NO buttons. The pill without blur, non-positioned
          // so the Stack takes its 63 pt height from it. It must
          // never render the nav items: the package bar below is the
          // only item renderer, and a second copy of the icons +
          // labels (slightly offset) is the "reflection" the user
          // saw on 0.2.15.
          _buildPill(
            height: glassPillHeight,
            blurred: false,
            includeButtons: false,
          ),
          glassInBox,
          // Thin neutral rim on the pill's exact outline, above the
          // glass so it reads on every theme. IgnorePointer so taps
          // still land on the bar.
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(pillRadius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Frosted (the default): plain blur sigma 4 over the opaque
  /// surface (0xFF181C20 dark / solid white light). The blur is
  /// kept for the frosted edge treatment; the surface itself is
  /// opaque (0.2.15) so no scrolling content shows behind the icons.
  Widget _buildBlurry() {
    return _buildPill(height: 64, blurred: true);
  }

  /// The pill's painted content (surface + border + sheen), shared
  /// by both styles so switching nav styles never moves the pill.
  /// [blurred] wraps it in the BackdropFilter for the frosted look;
  /// the glass base layer (0.2.14) skips the blur so the package
  /// shader refracts a clean pill — a blurred base would fog the
  /// liquid-glass look. [includeButtons] adds the five icon buttons
  /// (the 'blurry' style, which has no package bar, needs them);
  /// the glass base layer passes false (0.2.16) — the package bar
  /// renders the items, and a second copy in the base layer is the
  /// ghost "reflection" the user saw on 0.2.15.
  ///
  /// 0.2.15: the surface is FULLY OPAQUE in both styles (dark
  /// 0xFF181C20 / solid white light). The glass base layer is the
  /// same pill, so the package bar's own translucent fill can no
  /// longer let the poster grid bleed through behind the icons —
  /// the opaque base sits behind it and blocks everything.
  Widget _buildPill({
    required double height,
    required bool blurred,
    bool includeButtons = true,
  }) {
    final ImageFilter filter = ImageFilter.blur(
      sigmaX: blurryBlurSigma,
      sigmaY: blurryBlurSigma,
    );
    final Color bgColor = isDark ? blurrySurfaceDark : Colors.white;
    final Color borderColor = Colors.white.withValues(
      alpha: isDark ? 0.28 : 0.45,
    );
    final double sheenAlpha = isDark ? 0.08 : 0.20;
    final Widget pill = Container(
      height: height,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(pillRadius),
        border: Border.all(color: borderColor),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withValues(alpha: sheenAlpha),
            Colors.white.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: includeButtons
          ? Row(
              children: <Widget>[
                for (int i = 0; i < _items.length; i++)
                  Expanded(
                    child: _NavButton(
                      item: _items[i],
                      selected: i == currentIndex,
                      accent: accent,
                      isDark: isDark,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            )
          : null,
    );
    if (!blurred) return pill;
    return ClipRRect(
      borderRadius: BorderRadius.circular(pillRadius),
      child: BackdropFilter(
        filter: filter,
        child: pill,
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.label);

  /// Reicon outline path data (see Reicon.outline.*).
  final String icon;
  final String label;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Unselected icons are light grey (dark mode) so every icon is
    // clearly visible on the pill; selected = accent colour.
    final Color color = selected
        ? accent
        : (isDark ? const Color(0xFFC7C7D1) : const Color(0xFF6E6E80));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          ReiconIcon(item.icon, size: 24, color: color),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
