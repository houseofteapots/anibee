import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

import 'reicon_icon.dart';

/// The bottom navigation pill — the ONLY liquid-glass surface in the app.
/// Dark mode cards everywhere else are solid; this pill is translucent blur.
/// Positioned talks directly to the Stack (never wrap in Transform/Padding).
///
/// [navStyle] (Settings → Appearance): 'glass' = Liquid Glass — crystal
/// clear, Zeus-style; 'blurry' = the frosted look. (0.2.12: the old
/// 'glass' — blur sigma 4 over the dark 0x0A181C20 surface — still
/// rendered frosted on the phone, so it moved here to 'blurry' and
/// 'glass' was rebuilt on Zeus's measured Frost values.)
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

  /// Liquid Glass design values — MEASURED from Zeus's Frost nav
  /// (2026-11-23, 0.2.12), not guessed: the
  /// `liquid_glass_bottom_nav` 0.0.14 package paints its dark-mode
  /// pill with white at 0.04 alpha, blur 1, thickness 32, and a
  /// white 0.08 border; Zeus overlays its own 1px rim in white at
  /// 0.18 (`custom_bottom_nav.dart`, `_NavPillRim`) plus black
  /// shadows (0.08 blur 0, 0.14 blur 20). The glass look comes from
  /// refraction, not from a milky surface or heavy blur — AniBee
  /// has no refraction renderer, so the faithful equivalent is a
  /// near-transparent white surface + minimal blur: the content
  /// behind stays SHARP and readable, with only the bright thin rim
  /// marking the pill's edge. The 0.2.9 comment claiming Zeus uses
  /// "blur 5" was WRONG — the package uses blur 1.
  static const double glassBlurSigma = 1.0;
  static const Color glassSurfaceDark = Color(0x0AFFFFFF);
  static const double glassBorderAlpha = 0.18;

  /// Frosted design values — exactly what 'glass' rendered in
  /// 0.2.9–0.2.11 (blur sigma 4 over the dark 0x0A181C20 surface):
  /// the frosted look the user sees today, kept as the 'blurry'
  /// option (the default). The old blurry (colour-matrix + blur 18
  /// over 0x38) is retired.
  static const double blurryBlurSigma = 4.0;
  static const Color blurrySurfaceDark = Color(0x0A181C20);

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
    // 'glass' — crystal clear (Zeus Frost, measured): white 0.04
    // surface + blur sigma 1 + white 0.18 rim. The pill is dark
    // glass in BOTH themes (Zeus hands light themes a dark
    // brightness for the same reason), so the icons use the dark
    // set whenever glass is on. 'blurry' — frosted: plain blur
    // sigma 4 over the old glass surface (0x0A181C20 dark /
    // white 0.30 light), exactly the 0.2.9–0.2.11 'glass' look.
    final ImageFilter filter = glass
        ? ImageFilter.blur(sigmaX: glassBlurSigma, sigmaY: glassBlurSigma)
        : ImageFilter.blur(sigmaX: blurryBlurSigma, sigmaY: blurryBlurSigma);
    final Color bgColor = glass
        ? glassSurfaceDark
        : (isDark
              ? blurrySurfaceDark
              : Colors.white.withValues(alpha: 0.30));
    final Color borderColor = Colors.white.withValues(
      alpha: glass ? glassBorderAlpha : (isDark ? 0.28 : 0.45),
    );
    final double sheenAlpha = glass ? 0.05 : (isDark ? 0.08 : 0.20);
    // Dark-glass pill in both themes when glass is on — the light
    // icon set would be unreadable on it otherwise.
    final bool pillDark = isDark || glass;
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
                    isDark: pillDark,
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
