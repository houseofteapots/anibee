import 'package:flutter/material.dart';

/// The splash: the AniBee mark + wordmark centered on the dark navy
/// background — the same composition as the native launch screen, so
/// the handoff between the two is seamless.
///
/// 0.2.9: the mark + wordmark are ONE baked image
/// (`assets/launch_image.png`, copied from the native
/// `LaunchImage@3x.png`). The previous version rendered the wordmark
/// with a live [Text] widget, and on the phone a pure-yellow bar
/// appeared exactly under the wordmark — same width as the text,
/// fading with the splash, although no code draws yellow and the
/// mark asset has zero yellow pixels (verified on the 2026-11-23
/// screen recording). With no live Text widget there is nothing
/// left that can underline or otherwise re-render the wordmark:
/// the splash now shows exactly the pixels of an image verified
/// to contain no yellow.
class SplashView extends StatelessWidget {
  const SplashView({super.key, required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 400),
      child: Container(
        color: const Color(0xFF0D142E),
        alignment: Alignment.center,
        // 720x810 baked image at width 240: the mark tile renders
        // 180pt wide (same as before) with the wordmark baked below
        // it at the native launch screen's proportions.
        child: Image.asset('assets/launch_image.png', width: 240),
      ),
    );
  }
}
