import 'package:flutter/material.dart';

/// The app's own subtitle overlay (0.2.7).
///
/// ROOT CAUSE (0.2.5 + 0.2.6 phone tests): with the default
/// `PlayerConfiguration` (`libass: false`) mpv never renders
/// subtitles (`sub-visibility=no`); the visible caption was
/// media_kit_video's built-in `SubtitleView` overlay with a FIXED
/// default style, so no `sub-*` property could ever change it.
/// The app now hides that overlay
/// (`SubtitleViewConfiguration(visible: false)`) and renders this
/// one instead, styled from the settings store — size, colour,
/// font, bold, background, outline, position and opacity all drive
/// this widget directly, so the panel and the picture can never
/// drift apart again.
///
/// Pure presentation: [lines] are the current subtitle cues
/// (`player.stream.subtitle`), [style] and [alignment] come from
/// `buildSubtitleOverlayStyle` / `subtitleOverlayAlignment`
/// (`lib/player/subtitle_style.dart`). Empty lines render nothing.
/// Never handles input (`IgnorePointer` is applied by the caller).
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({
    super.key,
    required this.lines,
    required this.style,
    required this.alignment,
  });

  final List<String> lines;
  final TextStyle style;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final List<String> visible = <String>[
      for (final String line in lines)
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (visible.isEmpty) return const SizedBox.shrink();
    // No Positioned here: the caller places this widget in the
    // player Stack (StackFit.expand gives it the full video area),
    // and a bare Align sizes to whatever constraints it gets.
    return Align(
      alignment: alignment,
      child: Padding(
        // Fixed safe margins so a two-line cue can never clip at
        // the screen edge (the 0.2.6 video showed the second line
        // cut off at the bottom).
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
        child: Text(
          visible.join('\n'),
          textAlign: TextAlign.center,
          style: style,
        ),
      ),
    );
  }
}
