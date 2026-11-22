import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:reicon_flutter/reicon_flutter.dart';

import 'reicon_icon.dart';

/// The bottom navigation pill — the ONLY liquid-glass surface in the app.
/// Dark mode cards everywhere else are solid; this pill is translucent blur.
/// Positioned talks directly to the Stack (never wrap in Transform/Padding).
///
/// [navStyle] (Settings → Appearance): 'glass' = Liquid Glass — highly
/// translucent with a sheen; 'blurry' = frosted blur — stronger blur,
/// more opaque, matte finish.
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

  // Navigation icons are Reicon Outline (reicon.dev, MIT) — no generic
  // Material icons on the nav pill.
  static final List<_NavItem> _items = <_NavItem>[
    _NavItem(Reicon.outline.home, 'Home'),
    _NavItem(Reicon.outline.search, 'Search'),
    _NavItem(Reicon.outline.bookmark, 'Collection'),
    _NavItem(Reicon.outline.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final bool glass = navStyle != 'blurry';
    // Liquid Glass: clearly translucent, light blur, bright sheen edge.
    // Blurry: frosted — heavy blur + much more opaque, matte.
    final double blurSigma = glass ? 18 : 32;
    final Color bgColor = isDark
        ? (glass
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.24))
        : (glass
            ? Colors.white.withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.82));
    final Color borderColor = Colors.white.withValues(
      alpha: isDark ? (glass ? 0.20 : 0.10) : (glass ? 0.45 : 0.25),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: borderColor),
            gradient: glass
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Colors.white.withValues(alpha: isDark ? 0.10 : 0.20),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                  )
                : null,
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
    final Color color = selected
        ? accent
        : (isDark ? const Color(0xFF8E8EA3) : const Color(0xFF6E6E80));
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
