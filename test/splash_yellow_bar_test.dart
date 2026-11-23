import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:anibee/widgets/splash_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.9 splash yellow-bar regression test.
///
/// Phone evidence (2026-11-23 19:43, screen recording): the Flutter
/// splash showed a PURE YELLOW bar (254,254,0) exactly under the
/// "AniBee" wordmark — same width as the text, fading with the
/// splash. The native launch screen (LaunchImage@3x.png, baked mark
/// + wordmark) has NO bar, and assets/splash_mark.png has ZERO
/// yellow pixels — so the bar came from the live Text wordmark.
///
/// Fix: the splash no longer has a live Text widget at all — it
/// shows the baked `assets/launch_image.png` (copied from the
/// native LaunchImage@3x.png, verified 0 yellow pixels), so the
/// splash renders exactly those pixels on navy.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Yellow pixels in a captured frame (r>200, g>200, b<80).
  /// The raster work runs inside runAsync: awaiting toImage() /
  /// toByteData() directly in the fake-async test body lets the
  /// capture complete but leaves the test unable to finish.
  Future<int> countYellowPixels(WidgetTester tester, GlobalKey boundaryKey) async {
    final RenderRepaintBoundary boundary =
        boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    final (ui.Image, ByteData?) captured =
        (await tester.runAsync(() async {
      final ui.Image img = await boundary.toImage(pixelRatio: 1.0);
      final ByteData? bytes =
          await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (img, bytes);
    }))!;
    final ui.Image image = captured.$1;
    final ByteData? data = captured.$2;
    expect(data, isNotNull);
    final Uint8List bytes = data!.buffer.asUint8List();
    int yellow = 0;
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      if (bytes[i] > 200 && bytes[i + 1] > 200 && bytes[i + 2] < 80) {
        yellow++;
      }
    }
    image.dispose();
    return yellow;
  }

  Future<int> captureYellow(WidgetTester tester, Widget child) async {
    final GlobalKey boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(key: boundaryKey, child: child),
      ),
    );
    await tester.pump();
    return countYellowPixels(tester, boundaryKey);
  }

  testWidgets('fixed splash (baked image) shows no yellow bar', (
    WidgetTester tester,
  ) async {
    final int yellow = await captureYellow(
      tester,
      const SplashView(opacity: 1.0),
    );
    expect(
      yellow,
      0,
      reason: 'Splash must not render a yellow bar under the wordmark',
    );
  });

  testWidgets('probe: old live-Text splash subtree yellow count', (
    WidgetTester tester,
  ) async {
    // Replica of the pre-0.2.9 _SplashView (live Text wordmark).
    // Prints whether THIS VM reproduces the phone's yellow bar —
    // informational only; the phone (iOS/SF Pro) is the authority.
    final int yellow = await captureYellow(
      tester,
      AnimatedOpacity(
        opacity: 1.0,
        duration: const Duration(milliseconds: 400),
        child: Container(
          color: const Color(0xFF0D142E),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Image.asset('assets/splash_mark.png', width: 180, height: 180),
              const SizedBox(height: 14),
              const Text(
                'AniBee',
                style: TextStyle(
                  color: Color(0xFFB17E5C),
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    debugPrint('probe: old live-Text splash yellow pixels = $yellow');
  });
}
