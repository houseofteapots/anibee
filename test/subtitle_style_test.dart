import 'package:anibee/player/subtitle_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.7 subtitle styling: the app renders subtitles itself (a
/// Flutter overlay from `player.stream.subtitle`) because with the
/// default `PlayerConfiguration` (`libass: false`) mpv never draws
/// a subtitle — the visible caption was media_kit_video's built-in
/// `SubtitleView` with a FIXED default style, which is why no
/// `sub-*` property ever changed the picture (0.2.5 + 0.2.6 phone
/// tests). These tests prove the new mechanism: the panel options
/// map to the overlay's TextStyle + alignment, and only
/// `sub-delay` / `sub-codepage` still go to mpv.
void main() {
  group('buildSubtitlePipelineProperties', () {
    test('only delay and codepage go to mpv', () {
      final Map<String, String> p = buildSubtitlePipelineProperties(
        subDelayMs: 200,
        subEncoding: 'auto',
      );
      expect(p, <String, String>{
        'sub-delay': '0.20',
        'sub-codepage': 'auto',
      });
      expect(
        buildSubtitlePipelineProperties(
          subDelayMs: -500,
          subEncoding: 'utf-8',
        ),
        <String, String>{'sub-delay': '-0.50', 'sub-codepage': 'utf-8'},
      );
    });
  });

  group('buildSubtitleOverlayStyle', () {
    TextStyle style({
      double subSize = 18,
      String subFont = 'Inter Semibold',
      Color subColor = Colors.white,
      int subOpacity = 100,
      bool subBold = false,
      String subOutline = 'medium',
      String subBackgroundMode = 'dark',
    }) {
      return buildSubtitleOverlayStyle(
        subSize: subSize,
        subFont: subFont,
        subColor: subColor,
        subOpacity: subOpacity,
        subBold: subBold,
        subOutline: subOutline,
        subBackgroundMode: subBackgroundMode,
      );
    }

    test('size / colour + opacity / bold map to the text style', () {
      final TextStyle s = style();
      expect(s.fontSize, 18);
      expect(s.color, const Color(0xFFFFFFFF));
      expect(s.fontWeight, FontWeight.w500);
      expect(style(subSize: 24).fontSize, 24);
      expect(style(subBold: true).fontWeight, FontWeight.w700);
      expect(
        style(subOpacity: 50).color,
        const Color(0xFFFFFFFF).withValues(alpha: 0.5),
      );
      expect(
        style(subColor: const Color(0xFFFF0000)).color,
        const Color(0xFFFF0000),
      );
    });

    test('background modes map to the text background', () {
      expect(style(subBackgroundMode: 'off').backgroundColor,
          Colors.transparent);
      expect(style(subBackgroundMode: 'dark').backgroundColor, Colors.black54);
      expect(style(subBackgroundMode: 'solid').backgroundColor, Colors.black);
    });

    test('font family: only Mono maps to a real family', () {
      expect(style().fontFamily, isNull);
      expect(style(subFont: 'System').fontFamily, isNull);
      expect(style(subFont: 'Rounded').fontFamily, isNull);
      // 'Inter Semi Bold' is not an iOS system font — asking
      // Flutter for it would silently fall back anyway.
      expect(style(subFont: 'Inter Semibold').fontFamily, isNull);
      expect(style(subFont: 'Mono').fontFamily, 'Courier');
    });

    test('outline maps to shadow counts', () {
      expect(style(subOutline: 'none').shadows, isEmpty);
      expect(style(subOutline: 'thin').shadows, hasLength(4));
      expect(style(subOutline: 'medium').shadows, hasLength(8));
      expect(style(subOutline: 'thick').shadows, hasLength(8));
      // Thick uses a wider offset than medium.
      final List<Shadow> medium = style(subOutline: 'medium').shadows!;
      final List<Shadow> thick = style(subOutline: 'thick').shadows!;
      expect(
        thick.map((Shadow s) => s.offset.dx.abs()).reduce(
              (double a, double b) => a > b ? a : b,
            ),
        greaterThan(
          medium.map((Shadow s) => s.offset.dx.abs()).reduce(
                (double a, double b) => a > b ? a : b,
              ),
        ),
      );
    });
  });

  group('subtitleOverlayAlignment', () {
    Alignment align({
      String subPosition = 'Bottom',
      bool subAutoAdjust = true,
      double subManualPercent = 0,
      bool controlsVisible = true,
    }) {
      return subtitleOverlayAlignment(
        subPosition: subPosition,
        subAutoAdjust: subAutoAdjust,
        subManualPercent: subManualPercent,
        controlsVisible: controlsVisible,
      );
    }

    test('Top / Middle are fixed', () {
      expect(align(subPosition: 'Top').y, closeTo(-0.92, 0.001));
      expect(align(subPosition: 'Middle').y, closeTo(0, 0.001));
    });

    test('Bottom follows the controls', () {
      // Visible: lifted above the button row (old sub-pos 80).
      expect(align(controlsVisible: true).y, closeTo(0.6, 0.001));
      // Hidden: near the bottom, but never clipped.
      expect(align(controlsVisible: false).y, closeTo(0.92, 0.001));
    });

    test('manual position overrides everything', () {
      // Manual percent follows the old mpv mapping: sub-pos was
      // 100 - manual, and sub-pos 0 = top, 100 = bottom — so the
      // slider's 0 sits at the bottom and 100 at the top.
      expect(
        align(subAutoAdjust: false, subManualPercent: 0).y,
        closeTo(1, 0.001),
      );
      expect(
        align(subAutoAdjust: false, subManualPercent: 100).y,
        closeTo(-1, 0.001),
      );
      // The 0.2.6 video: manual 38% sat the subtitle just below
      // the middle; 22% near the bottom — and neither moved it.
      expect(
        align(subAutoAdjust: false, subManualPercent: 38).y,
        closeTo(0.24, 0.001),
      );
      expect(
        align(subAutoAdjust: false, subManualPercent: 22).y,
        closeTo(0.56, 0.001),
      );
    });
  });
}
