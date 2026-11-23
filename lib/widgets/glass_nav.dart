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

  /// Frosted design values — exactly what 'glass' rendered in
  /// 0.2.9–0.2.11 (blur sigma 4 over the dark 0x0A181C20 surface):
  /// the frosted look the user sees today, kept as the 'blurry'
  /// option (the default). The old blurry (colour-matrix + blur 18
  /// over 0x38) is retired.
  static const double blurryBlurSigma = 4.0;
  static const Color blurrySurfaceDark = Color(0x0A181C20);

  /// Pill geometry, shared by both styles so switching nav styles
  /// never moves the pill: 63 pt tall (the package's fixed height),
  /// radius 32 (AniBee's stadium pill), 16 pt side margins from the
  /// app shell's Positioned.
  static const double pillRadius = 32.0;

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

  /// Liquid Glass (0.2.13): the real package bar — the same
  /// `LiquidGlassNavBar` Zeus renders. Its dark-mode pill is the
  /// clear one (4% fill); its light-mode pill is milky (76% white
  /// fill), so on light themes the bar is handed a dark brightness
  /// (Zeus's `clearNavGlassFor`) to get the same clear glass, and
  /// the icons use the dark set. A thin white 0.18 rim is overlaid
  /// on the pill's exact outline (Zeus's `_NavPillRim`). The shell
  /// already insets the pill 16 pt on each side, so the package's
  /// own `insets` is 0.
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
    return Stack(
      children: <Widget>[
        glass,
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
    );
  }

  /// Frosted (the default): plain blur sigma 4 over the old glass
  /// surface (0x0A181C20 dark / white 0.30 light), exactly the
  /// 0.2.9–0.2.11 'glass' look.
  Widget _buildBlurry() {
    final ImageFilter filter = ImageFilter.blur(
      sigmaX: blurryBlurSigma,
      sigmaY: blurryBlurSigma,
    );
    final Color bgColor = isDark
        ? blurrySurfaceDark
        : Colors.white.withValues(alpha: 0.30);
    final Color borderColor = Colors.white.withValues(
      alpha: isDark ? 0.28 : 0.45,
    );
    final double sheenAlpha = isDark ? 0.08 : 0.20;
    return ClipRRect(
      borderRadius: BorderRadius.circular(pillRadius),
      child: BackdropFilter(
        filter: filter,
        child: Container(
          height: 64,
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
          child: Row(
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
          ),
        ),
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
