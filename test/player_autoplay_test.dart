import 'package:anibee/models.dart';
import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/screens/full_player_screen.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.9 autoplay "Up next" card: the phone (2026-11-23, Death Note
/// EP 3) showed Cancel doing NOTHING — the card stayed and the
/// countdown kept running.
///
/// DIAGNOSIS (proven by the tests below, not guessed): a clean tap
/// on the button itself always worked. The failure was the HIT PATH:
/// the card's Container has a decoration so it IS hit-testable, but
/// it carried no recognizer, and the Stack stops hit-testing at the
/// overlay — so a tap on the title, the countdown text, the padding,
/// or the gap between the buttons was swallowed completely (not
/// even the controls toggle fired). The Cancel button was a bare
/// ~36pt TextButton, so a finger aiming at it easily lands a few px
/// off it. FIX: the whole card is tappable to cancel, and Cancel
/// has a proper 44pt target.
/// No timer-state bug: `_autoplayShown` is only reset by
/// `_selectEpisode`, and `_showAutoplayOverlay` has no other caller
/// (besides the test seam), so a cancelled timer cannot resurrect.
///
/// Harness copied from player_double_tap_test.dart: the player is
/// constructed for real (real libmpv on the VM) but NO media is
/// loaded; the overlay is driven through the showAutoplayForTest
/// seam (the real trigger is the position stream near the end).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    MediaKit.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.alexmercerind/media_kit_video'),
      (MethodCall call) async {
        if (call.method == 'VideoOutputManager.Create') {
          final Map<Object?, Object?> args =
              call.arguments as Map<Object?, Object?>;
          final int handle = int.parse(args['handle'] as String);
          await messenger.handlePlatformMessage(
            'com.alexmercerind/media_kit_video',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('VideoOutput.Resize', <String, Object>{
                'handle': handle,
                'rect': <String, Object>{
                  'left': 0.0,
                  'top': 0.0,
                  'width': 800.0,
                  'height': 600.0,
                },
                'id': 1,
              }),
            ),
            null,
          );
        }
        return null;
      },
    );
  });

  const Anime anime = Anime(
    id: 'autoplay-test',
    title: 'Autoplay Test Anime',
    rating: 4.0,
    year: 2024,
    episodeCount: 12,
    genres: <String>['Action'],
    synopsis: 'Test anime for the autoplay overlay widget test.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
  );

  late SettingsStore store;
  late TrailerPlayer trailer;

  Future<void> pumpPlayer(WidgetTester tester) async {
    store = await SettingsStore.load();
    await tester.runAsync(() async {
      trailer = TrailerPlayer();
    });
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    final List<Episode> episodes = mockEpisodes(anime);
    await tester.pumpWidget(
      MaterialApp(
        home: FullPlayerScreen(
          trailer: trailer,
          store: store,
          anime: anime,
          episodes: episodes,
          initialEpisode: episodes.first,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  dynamic playerState(WidgetTester tester) =>
      tester.state(find.byType(FullPlayerScreen)) as dynamic;

  Future<void> showOverlay(WidgetTester tester) async {
    playerState(tester).showAutoplayForTest();
    await tester.pump();
    expect(playerState(tester).autoplayVisibleForTest, isTrue);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Play now'), findsOneWidget);
    expect(find.text('Up next: Episode 2'), findsOneWidget);
  }

  testWidgets('Cancel dismisses the overlay and no episode switch follows', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    await showOverlay(tester);
    expect(playerState(tester).currentEpisodeForTest, 1);

    // The tap fires only after the double-tap window expires
    // (the full-screen gesture layer has onDoubleTap).
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Play now'), findsNothing);
    expect(playerState(tester).autoplayVisibleForTest, isFalse);
    // Past the whole countdown: still on episode 1, no switch.
    await tester.pump(const Duration(seconds: 6));
    expect(playerState(tester).currentEpisodeForTest, 1);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('Play now switches to the next episode', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    await showOverlay(tester);

    await tester.tap(find.text('Play now'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Cancel'), findsNothing);
    expect(playerState(tester).autoplayVisibleForTest, isFalse);
    expect(playerState(tester).currentEpisodeForTest, 2);
  });

  testWidgets('an untouched countdown switches episodes on its own', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    await showOverlay(tester);
    expect(playerState(tester).currentEpisodeForTest, 1);

    // Countdown is 5s: six 1s ticks take it to zero.
    await tester.pump(const Duration(seconds: 6));
    expect(playerState(tester).currentEpisodeForTest, 2);
    expect(playerState(tester).autoplayVisibleForTest, isFalse);
  });

  testWidgets('a slow press on Cancel still cancels', (
    WidgetTester tester,
  ) async {
    // PROBE (phone-realistic): a deliberate press holds the finger
    // down ~500ms before lifting. (The hold-to-2x timer never arms
    // here: the Stack stops hit-testing at the overlay, so the
    // pinch Listener below never sees the press — only the button's
    // tap recognizer is in the path.)
    await pumpPlayer(tester);
    await showOverlay(tester);
    final Offset center = tester.getCenter(find.text('Cancel'));
    final TestGesture gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Cancel'), findsNothing);
    expect(playerState(tester).autoplayVisibleForTest, isFalse);
    await tester.pump(const Duration(seconds: 6));
    expect(playerState(tester).currentEpisodeForTest, 1);
  });

  testWidgets('tapping Cancel right after a countdown tick still cancels', (
    WidgetTester tester,
  ) async {
    // PROBE (phone-realistic): the 1s countdown tick rebuilds the
    // overlay every second; a tap landing just after a tick must
    // still reach the button.
    await pumpPlayer(tester);
    await showOverlay(tester);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Playing in 4 s'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Cancel'), findsNothing);
    expect(playerState(tester).autoplayVisibleForTest, isFalse);
    await tester.pump(const Duration(seconds: 6));
    expect(playerState(tester).currentEpisodeForTest, 1);
  });

  testWidgets('tapping anywhere on the card dismisses the overlay', (
    WidgetTester tester,
  ) async {
    // 0.2.9: the whole card is tappable to cancel — before this,
    // a tap on the title / countdown text / padding was swallowed
    // completely (the overlay's Container is hit-testable but had
    // no recognizer, and the Stack blocks the gesture layer below).
    await pumpPlayer(tester);
    await showOverlay(tester);
    await tester.tap(find.text('Playing in 5 s'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Cancel'), findsNothing);
    expect(playerState(tester).autoplayVisibleForTest, isFalse);
    await tester.pump(const Duration(seconds: 6));
    expect(playerState(tester).currentEpisodeForTest, 1);
  });

  testWidgets('PROBE: Cancel tap with a 5px finger drift still cancels', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    await showOverlay(tester);
    final Offset center = tester.getCenter(find.text('Cancel'));
    final TestGesture gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(5, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Cancel'), findsNothing);
    expect(playerState(tester).autoplayVisibleForTest, isFalse);
  });

  testWidgets('a press drifting past the touch slop is not a tap', (
    WidgetTester tester,
  ) async {
    // Standard Flutter tap semantics: a press that moves > ~18px
    // is a swipe, not a tap, so the card stays and the countdown
    // runs its course (no accidental episode switch either way).
    await pumpPlayer(tester);
    await showOverlay(tester);
    final Offset center = tester.getCenter(find.text('Cancel'));
    final TestGesture gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(25, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);
    expect(playerState(tester).autoplayVisibleForTest, isTrue);
    await tester.pump(const Duration(seconds: 6));
    expect(playerState(tester).currentEpisodeForTest, 2);
  });
}
