import 'dart:ui';

import 'package:flutter/material.dart';

import '../models.dart';

/// Settings background (0.2.8, approved mockup): a very dark, heavily
/// blurred collage of the anime posters the app already fetches
/// (Home/trending posters from the catalogue — the same URLs, so they
/// come from Flutter's in-memory ImageCache after Home renders them)
/// at low opacity under a dark overlay, with the solid cards floating
/// above it and all text perfectly readable.
///
/// Dark mode only — light mode keeps the plain light background.
/// Falls back to the plain dark background when no posters are
/// available (empty catalogue, or every load fails: the dark overlay
/// alone over the scaffold background is the fallback, so the screen
/// is never broken or blank).
class SettingsBackground extends StatelessWidget {
  const SettingsBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    if (!isDark) return const SizedBox.shrink();
    final List<String> urls = mockCatalogue()
        .map((Anime a) => a.posterUrl)
        .whereType<String>()
        .take(21)
        .toList();
    if (urls.isEmpty) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Poster collage: 3 columns, fills the screen. A failed load
        // leaves its cell empty (transparent) — the dark overlay
        // below covers it, so offline the background is just dark.
        GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.68,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
          itemCount: urls.length,
          itemBuilder: (BuildContext context, int i) {
            return Image.network(
              urls[i],
              fit: BoxFit.cover,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stackTrace) {
                    return const SizedBox.shrink();
                  },
            );
          },
        ),
        // Heavy blur + dark overlay: the art stays recognizable
        // between the cards, but nothing behind the text competes
        // with it. The cards themselves are solid dark (AppTheme
        // cardDark), so card text is unaffected by the art.
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(color: Colors.black.withValues(alpha: 0.60)),
        ),
      ],
    );
  }
}
