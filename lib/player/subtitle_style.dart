import 'package:flutter/material.dart';

/// mpv properties for the player subtitle editor (0.2.5).
///
/// ROOT CAUSE (user phone test 2026-11-23: "subtitle customization
/// kuch vi kaam nahi kar rha"): the editor wrote the plain `sub-*`
/// properties (sub-font-size, sub-color, sub-font, sub-bold,
/// sub-border-size, sub-back-color) but anime subtitles are ASS —
/// and mpv's default `sub-ass-override=scale` means those options
/// are IGNORED for ASS (only `sub-ass-*` overrides and `sub-scale`
/// apply). The manual is explicit: "Subtitles in ASS format are
/// normally not changed intentionally, but overriding them can be
/// controlled with --sub-ass-override", and only `force` "also
/// force[s] all --sub-* options". So every style option did nothing
/// on the phone even though the property writes themselves reached
/// mpv (verified: Player.platform IS NativePlayer on iOS and
/// setProperty calls the real mpv_set_property_string).
///
/// The fix: every style apply also sets `sub-ass-override=force`
/// (plus `sub-ass-force-margins=yes`, so `sub-pos` reliably moves
/// ASS subtitles) — then all of the editor's options visibly change
/// the on-screen subtitle, for ASS and for plain-text subtitles
/// alike. Trade-off, documented in the mpv manual: `force` "can
/// break rendering easily" — it strips the script's own typesetting
/// (signs/karaoke positioning) in favour of the user's style. That
/// is what a style editor promises, so it is the right default here.
///
/// Pure (no player, no store) so it is unit-tested:
/// test/subtitle_style_test.dart.
Map<String, String> buildSubtitleMpvProperties({
  required double subSize,
  required String subFont,
  required Color subColor,
  required int subOpacity,
  required bool subBold,
  required String subOutline,
  required String subBackgroundMode,
  required String subEncoding,
  required int subDelayMs,
  required double subPos,
}) {
  // mpv sub-color is #AARRGGBB — the alpha carries the text opacity.
  final int alpha = ((subOpacity.clamp(0, 100) / 100) * 255).round();
  final String hex =
      '#${alpha.toRadixString(16).padLeft(2, '0')}'
      '${subColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  return <String, String>{
    // First: without this, every option below is ignored for ASS.
    'sub-ass-override': 'force',
    'sub-ass-force-margins': 'yes',
    'sub-font-size': (subSize * 2).toString(),
    'sub-font': mpvFontName(subFont),
    'sub-color': hex,
    'sub-bold': subBold ? 'yes' : 'no',
    'sub-border-size': switch (subOutline) {
      'none' => '0',
      'thin' => '1',
      'thick' => '3',
      _ => '2',
    },
    // The outline colour was never set before; explicit black so the
    // outline is visible whichever background the user picks.
    'sub-border-color': '#FF000000',
    'sub-back-color': switch (subBackgroundMode) {
      'solid' => '#FF000000',
      'dark' => '#CC000000',
      _ => '#00000000',
    },
    'sub-codepage': subEncoding == 'auto' ? 'auto' : subEncoding,
    'sub-delay': (subDelayMs / 1000).toStringAsFixed(2),
    'sub-pos': subPos.toStringAsFixed(0),
  };
}

/// mpv fontconfig family for the Settings font names.
String mpvFontName(String font) {
  return switch (font) {
    'System' => 'sans-serif',
    'Rounded' => 'Arial Rounded MT Bold',
    'Mono' => 'monospace',
    _ => 'Inter Semi Bold',
  };
}
