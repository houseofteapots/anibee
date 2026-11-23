import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

import 'reicon_icon.dart';

/// The bottom navigation pill — the ONLY liquid-glass surface in the app.
/// Dark mode cards everywhere else are solid; this pill is translucent blur.
/// Positioned talks directly to the Stack (never wrap in Transform/Padding).
///
/// [navStyle] (Settings → Appearance): 'glass' = Liquid Glass — crystal
/// clear, Zeus-style; 'blurry' = the frosted look — heavy blur, milky
/// surface. (0.2.9: the old 'glass' rendered frosted on the phone, so the
/// frosted look moved here to 'blurry' and 'glass' became truly clear.)
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

  /// Liquid Glass design values — Zeus's Frost nav
  /// (packages/liquid_glass_bottom_nav, fork of 0.0.14): its glass
  /// colour is `Color.fromARGB(0, 255, 255, 255)` — alpha ZERO — with
  /// blur 5, thickness 20, refractive index 1.2. The glass look
  /// comes from refraction, not from a milky surface or heavy blur;
  /// Zeus's own Frost fix (b109, "nav blurry/milky on Frost — pure
  /// liquid glass, clear not frosted") is the same complaint this
  /// fixes here. AniBee has no refraction renderer, so the closest
  /// faithful equivalent is a near-transparent surface + minimal
  /// blur: the content behind stays SHARP and readable.
  static const double glassBlurSigma = 4.0;
  static const Color glassSurfaceDark = Color(0x0A181C20);

  /// Frosted design values — exactly what the old 'glass' rendered
  /// (Zeus MatteGlassPill's composed colour-matrix + blur-18 filter
  /// over the 0x38 dark surface): heavy diffusion, milky surface.
  static const double blurryBlurSigma = 18.0;
  static const Color blurrySurfaceDark = Color(0x38181C20);

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
    final bool glass = navStyle != 'blurry';
    // 'glass' — crystal clear: near-transparent surface + minimal
    // blur (sigma 4, cf. Zeus's liquid-glass blur 5). The content
    // behind stays sharp; only a thin bright border + a whisper of
    // top sheen mark the pill's edge.
    // 'blurry' — frosted: the composed colour-matrix + blur-18
    // filter over the 0x38 dark surface (the old 'glass' look).
    final ImageFilter filter = glass
        ? ImageFilter.blur(sigmaX: glassBlurSigma, sigmaY: glassBlurSigma)
        : ImageFilter.compose(
            outer: const ColorFilter.matrix(<double>[
              0.724,
              0.250,
              0.026,
              0,
              0,
              0.074,
              0.900,
              0.026,
              0,
              0,
              0.074,
              0.250,
              0.676,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            inner: ImageFilter.blur(
              sigmaX: blurryBlurSigma,
              sigmaY: blurryBlurSigma,
            ),
          );
    final Color bgColor = isDark
        ? (glass ? glassSurfaceDark : blurrySurfaceDark)
        : (glass
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.white.withValues(alpha: 0.30));
    final Color borderColor = Colors.white.withValues(
      alpha: isDark ? (glass ? 0.28 : 0.22) : (glass ? 0.50 : 0.45),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: filter,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: borderColor),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Colors.white.withValues(
                  alpha: isDark ? (glass ? 0.08 : 0.10) : (glass ? 0.12 : 0.20),
                ),
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
