import 'package:flutter/material.dart';

/// Subtitle styling for the AniBee player (0.2.7).
///
/// ROOT CAUSE (user phone tests 0.2.5 + 0.2.6, video proof
/// 2026-11-23: "subtitle feature not working" — manual position
/// 38% -> 22% -> 27%, opacity 95% -> 85% -> 90%, outline -> Thick,
/// and the on-screen subtitle NEVER changed): the app never rendered
/// subtitles with mpv at all.
///
/// - `Player()` is created with the default `PlayerConfiguration`,
///   whose `libass` defaults to `false` (media_kit 1.2.6
///   `platform_player.dart`). mpv is therefore started with
///   `sub-ass=no` and `sub-visibility=no` — mpv never draws a
///   subtitle.
/// - What the user sees is media_kit_video's `SubtitleView`: the
///   `Video` widget renders that Flutter overlay whenever
///   `libass` is false (`video_texture.dart`: the overlay is shown
///   iff `subtitleViewConfiguration.visible && !libass`). It renders
///   mpv's `sub-text` property as plain Flutter text with the
///   FIXED default style (fontSize 32 scaled by screen size, white,
///   normal weight, semi-transparent black box, bottom-centre,
///   24px bottom padding).
///
/// So every `sub-*` property the editor wrote — 0.2.5's
/// `sub-ass-override=force` fix and 0.2.6's self-healing retry —
/// changed mpv state that is never rendered, while the visible
/// overlay ignored all of it. The VM "proofs" in 0.2.6 set the
/// properties inside mpv and rendered frames with mpv directly;
/// they never went through the app's `Video` widget with
/// `libass: false`, which is why they passed and the phone failed.
///
/// The fix (the architecture Zeus uses on this same phone, where
/// its subtitle editor works): keep `libass: false` and drive the
/// subtitle rendering ourselves — the app renders its own Flutter
/// overlay from `player.stream.subtitle` (the same `sub-text` the
/// built-in overlay used), styled from the settings store. The
/// built-in overlay is hidden
/// (`SubtitleViewConfiguration(visible: false)`). Two mpv
/// properties still matter and are still written to mpv:
/// `sub-delay` (proven on the VM with real mpv: it shifts the
/// `sub-text` emission, so the delay slider works through the
/// overlay) and `sub-codepage` (read when the subtitle file is
/// (re)loaded). Everything else in the old 12-property map is
/// gone — it could never affect the picture.
///
/// Pure (no player, no store) so it is unit-tested:
/// test/subtitle_style_test.dart.
Map<String, String> buildSubtitlePipelineProperties({
  required int subDelayMs,
  required String subEncoding,
}) {
  return <String, String>{
    'sub-delay': (subDelayMs / 1000).toStringAsFixed(2),
    'sub-codepage': subEncoding == 'auto' ? 'auto' : subEncoding,
  };
}

/// Flutter font family for the Settings font names. Only Mono maps
/// to a real bundled family ('Courier' ships on iOS); the others
/// fall back to the system font — 'Inter Semi Bold' is not an iOS
/// system font, so asking Flutter for it would silently fall back
/// anyway.
String? flutterFontFamily(String font) {
  return switch (font) {
    'Mono' => 'Courier',
    _ => null,
  };
}

/// Fake outline for the overlay text: Flutter's TextStyle has no
/// stroke, so the outline is simulated with black shadows around
/// the glyphs (the standard Flutter trick).
List<Shadow> subtitleOutlineShadows(String outline) {
  const Shadow thin = Shadow(
    color: Colors.black,
    offset: Offset(1, 0),
    blurRadius: 1,
  );
  const Shadow thin2 = Shadow(
    color: Colors.black,
    offset: Offset(-1, 0),
    blurRadius: 1,
  );
  const Shadow thin3 = Shadow(
    color: Colors.black,
    offset: Offset(0, 1),
    blurRadius: 1,
  );
  const Shadow thin4 = Shadow(
    color: Colors.black,
    offset: Offset(0, -1),
    blurRadius: 1,
  );
  const Shadow diag = Shadow(
    color: Colors.black,
    offset: Offset(1, 1),
    blurRadius: 1,
  );
  const Shadow diag2 = Shadow(
    color: Colors.black,
    offset: Offset(-1, 1),
    blurRadius: 1,
  );
  const Shadow diag3 = Shadow(
    color: Colors.black,
    offset: Offset(1, -1),
    blurRadius: 1,
  );
  const Shadow diag4 = Shadow(
    color: Colors.black,
    offset: Offset(-1, -1),
    blurRadius: 1,
  );
  const Shadow thick = Shadow(
    color: Colors.black,
    offset: Offset(2, 0),
    blurRadius: 2,
  );
  const Shadow thick2 = Shadow(
    color: Colors.black,
    offset: Offset(-2, 0),
    blurRadius: 2,
  );
  const Shadow thick3 = Shadow(
    color: Colors.black,
    offset: Offset(0, 2),
    blurRadius: 2,
  );
  const Shadow thick4 = Shadow(
    color: Colors.black,
    offset: Offset(0, -2),
    blurRadius: 2,
  );
  const Shadow thickDiag = Shadow(
    color: Colors.black,
    offset: Offset(2, 2),
    blurRadius: 2,
  );
  const Shadow thickDiag2 = Shadow(
    color: Colors.black,
    offset: Offset(-2, 2),
    blurRadius: 2,
  );
  const Shadow thickDiag3 = Shadow(
    color: Colors.black,
    offset: Offset(2, -2),
    blurRadius: 2,
  );
  const Shadow thickDiag4 = Shadow(
    color: Colors.black,
    offset: Offset(-2, -2),
    blurRadius: 2,
  );
  return switch (outline) {
    'none' => const <Shadow>[],
    'thin' => const <Shadow>[thin, thin2, thin3, thin4],
    'thick' => const <Shadow>[
      thick,
      thick2,
      thick3,
      thick4,
      thickDiag,
      thickDiag2,
      thickDiag3,
      thickDiag4,
    ],
    _ => const <Shadow>[
      thin,
      thin2,
      thin3,
      thin4,
      diag,
      diag2,
      diag3,
      diag4,
    ],
  };
}

/// The on-screen subtitle style for the Flutter overlay: size,
/// colour + opacity, bold, background box, font, outline.
/// Matches the panel preview (`_buildSubtitlePreview`) so what the
/// user sees in the panel is what the video shows.
TextStyle buildSubtitleOverlayStyle({
  required double subSize,
  required String subFont,
  required Color subColor,
  required int subOpacity,
  required bool subBold,
  required String subOutline,
  required String subBackgroundMode,
}) {
  return TextStyle(
    fontSize: subSize,
    fontFamily: flutterFontFamily(subFont),
    fontWeight: subBold ? FontWeight.w700 : FontWeight.w500,
    color: subColor.withValues(
      alpha: subOpacity.clamp(0, 100) / 100,
    ),
    backgroundColor: switch (subBackgroundMode) {
      'solid' => Colors.black,
      'dark' => Colors.black54,
      _ => Colors.transparent,
    },
    shadows: subtitleOutlineShadows(subOutline),
  );
}

/// Vertical position of the overlay inside the video area, as a
/// Flutter [Alignment] (y: -1 = top, +1 = bottom). Mirrors the old
/// mpv `sub-pos` mapping so the numbers the user already knows
/// still mean the same thing: Top = 5, Middle = 50, Bottom follows
/// the controls (lifted above the button row while they are visible,
/// near the bottom — but never clipped — when hidden), and manual
/// position (auto-adjust off) is `sub-pos = 100 - manualPercent`.
Alignment subtitleOverlayAlignment({
  required String subPosition,
  required bool subAutoAdjust,
  required double subManualPercent,
  required bool controlsVisible,
}) {
  if (subPosition == 'Top') return const Alignment(0, -0.92);
  if (subPosition == 'Middle') return Alignment.center;
  if (!subAutoAdjust) {
    final double frac = (100 - subManualPercent.clamp(0, 100)) / 100;
    return Alignment(0, -1 + 2 * frac);
  }
  return Alignment(0, controlsVisible ? 0.6 : 0.92);
}
