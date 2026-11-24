import 'package:anibee/models.dart';
import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/screens/full_player_screen.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.17: the player lock must actually lock — and must always be
/// unlockable.
///
/// Bug 1 (user report 2026-11-24 02:20): locking the player, then
/// waiting for the 3 s auto-hide, removed the unlock button from
/// the tree entirely (`_buildControls` was only rendered while
/// `_controlsVisible`), so no tap could ever unlock. The unlock
/// button now lives on its own layer outside the auto-hide gate.
///
/// Bug 2 (same report): while locked, volume/brightness swipes
/// still worked. Locked, ONLY double-tap left/right ±10 s seek
/// works — no single-tap toggle, no volume/brightness swipes, no
/// drag seek, no center double-tap play/pause, no hold-to-2x, no
/// pinch zoom.
///
/// The player is constructed for real (real libmpv on the VM) but
/// NO media is loaded — same harness as player_double_tap_test.dart
/// (see its header for why). The seek flash is shown before the
/// seek round-trip, so the double-tap assertions do not depend on
/// the seek completing. The volume drag is proven through the HUD
/// label, not `player.state.volume`: the mpv volume echo does not
/// propagate in this headless env (no audio device), so the state
/// never moves even when the handler runs and calls setVolume.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    MediaKit.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // flutter_secure_storage has no Linux implementation: unmocked,
    // its channel never replies inside testWidgets (fake-time zone)
    // and SettingsStore.load() hangs on the secret reads. Answer
    // null — there are no secrets in tests.
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
    // media_kit_video's native controller registers its texture
    // through a MethodChannel with no test implementation: unmocked,
    // the VideoController init never completes and Player.open()
    // hangs on it. Simulate the native side instead: answer Create
    // and immediately deliver the texture id the way the real
    // plugin does (inbound 'VideoOutput.Resize'), so create()
    // completes normally, the controller is healthy, and the Video
    // widget renders (black in the test engine). Without this the
    // controller lands in its error state and the test framework
    // reports the unhandled MissingPluginException as a failure.
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
    id: 'lock-test',
    title: 'Lock Test Anime',
    rating: 4.0,
    year: 2024,
    episodeCount: 12,
    genres: <String>['Action'],
    synopsis: 'Test anime for the player-lock widget test.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
  );

  late SettingsStore store;
  late TrailerPlayer trailer;

  Future<void> pumpPlayer(WidgetTester tester) async {
    store = await SettingsStore.load();
    // The Player constructor spawns media_kit's initializer isolate;
    // that handshake stalls when started inside the test's fake-time
    // zone, so construct the player in the real zone too.
    await tester.runAsync(() async {
      trailer = TrailerPlayer();
    });
    // No tearDown dispose: the screen's dispose() calls back into
    // the shared trailer (backToInline), so the trailer must outlive
    // the screen — as in the app, where the Detail screen owns it.
    // Disposing it in tearDown makes the next test's screen-dispose
    // notify a dead ChangeNotifier ("used after being disposed").
    // Pump a bare frame first: the VideoController init waits on a
    // post-frame callback (mocked channel answers it — see setUpAll).
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
    // Let the screen's initState player calls (expandToFull,
    // subtitle style) settle in real time, then render.
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  dynamic playerState(WidgetTester tester) =>
      tester.state(find.byType(FullPlayerScreen)) as dynamic;

  /// The double-tap handlers fire unawaited mpv commands (seek /
  /// play-pause) whose round-trip runs in REAL time; fake pumps
  /// alone never let them finish. Give real time a chance, then
  /// render.
  Future<void> settleRealTime(WidgetTester tester) async {
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
  }

  /// Flush every pending fake timer (3 s auto-hide, 500 ms seek
  /// flash, 700 ms HUD hide) before the test ends — a pending
  /// Timer fails teardown ("A Timer is still pending").
  Future<void> flushTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets('unlock button survives the auto-hide and unlocks',
      (WidgetTester tester) async {
    await pumpPlayer(tester);
    expect(playerState(tester).controlsVisibleForTest, isTrue);
    expect(find.byTooltip('Lock controls'), findsOneWidget);

    // Lock through the real button, as the user does.
    await tester.tap(find.byTooltip('Lock controls'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(playerState(tester).controlsLockedForTest, isTrue);
    expect(find.byTooltip('Unlock controls'), findsOneWidget);

    // The 3 s auto-hide fires while playing — simulate it: hide
    // the overlay. The old code removed the unlock button from
    // the tree here; the fix keeps it on its own layer.
    playerState(tester).hideControlsForTest();
    await tester.pump();
    expect(playerState(tester).controlsVisibleForTest, isFalse);
    expect(find.byTooltip('Unlock controls'), findsOneWidget);

    // One tap on the unlock button unlocks and brings the full
    // controls back.
    await tester.tap(find.byTooltip('Unlock controls'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(playerState(tester).controlsLockedForTest, isFalse);
    expect(playerState(tester).controlsVisibleForTest, isTrue);
    expect(find.text(anime.title), findsOneWidget);
    expect(find.byTooltip('Lock controls'), findsOneWidget);
    await flushTimers(tester);
  });

  testWidgets('locked vertical drags change neither volume nor brightness',
      (WidgetTester tester) async {
    await pumpPlayer(tester);
    expect(playerState(tester).volumeForTest, 100);
    expect(playerState(tester).brightnessLevelForTest, 100);

    // Lock FIRST, before any drag: no HUD has ever shown, so any
    // volume/brightness label appearing later must come from a
    // locked handler running — the HUD text is the proof, because
    // the mpv volume echo does not propagate in this headless env
    // (no audio device), so `state.volume` cannot prove the
    // negative either way. Drag both halves UP from 100: a handler
    // run would clamp to 100 and show '… 100%' labels.
    playerState(tester).lockControlsForTest();
    await tester.pump();
    expect(playerState(tester).controlsLockedForTest, isTrue);
    await tester.dragFrom(const Offset(200, 300), const Offset(0, -150));
    await tester.pump();
    await tester.dragFrom(const Offset(600, 300), const Offset(0, -150));
    await tester.pump();
    await settleRealTime(tester);
    expect(playerState(tester).brightnessLevelForTest, 100);
    expect(playerState(tester).volumeForTest, 100);
    expect(find.text('Brightness 100%'), findsNothing);
    expect(find.text('Volume 100%'), findsNothing);
    expect(playerState(tester).controlsLockedForTest, isTrue);

    // Positive control (unlocked): unlock, then drag both halves
    // DOWN. Brightness drops (local ValueNotifier — exact, ~48
    // after the touch slop) and the volume HUD appears, proving
    // the handler ran and called setVolume with the computed
    // value. These prove the drags actually reach the handlers
    // when unlocked — the lock above is what blocked them.
    await tester.tap(find.byTooltip('Unlock controls'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(playerState(tester).controlsLockedForTest, isFalse);
    await tester.dragFrom(const Offset(200, 300), const Offset(0, 150));
    await tester.pump();
    expect(
      playerState(tester).brightnessLevelForTest,
      inExclusiveRange(20, 60),
    );
    await tester.dragFrom(const Offset(600, 300), const Offset(0, 150));
    await tester.pump();
    expect(find.textContaining('Volume'), findsOneWidget);
    await flushTimers(tester);
  });

  testWidgets('locked double-tap left/right still seeks ±10 s',
      (WidgetTester tester) async {
    await pumpPlayer(tester);
    playerState(tester).hideControlsForTest();
    playerState(tester).lockControlsForTest();
    await tester.pump();
    expect(playerState(tester).controlsVisibleForTest, isFalse);
    expect(playerState(tester).controlsLockedForTest, isTrue);

    // Double-tap on the left third (100ms gap — two tapAts with
    // zero fake time between them are ignored as a double-tap).
    await tester.tapAt(const Offset(100, 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(100, 300));
    await settleRealTime(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(playerState(tester).seekFlashVisibleForTest, isTrue);
    expect(find.text('-10 s'), findsOneWidget);
    expect(playerState(tester).controlsLockedForTest, isTrue);
    expect(playerState(tester).controlsVisibleForTest, isFalse);

    // And the right third seeks forward.
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(700, 300));
    await settleRealTime(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('+10 s'), findsOneWidget);
    expect(playerState(tester).controlsLockedForTest, isTrue);
    expect(playerState(tester).controlsVisibleForTest, isFalse);
    await flushTimers(tester);
  });

  testWidgets('locked center double-tap does not play/pause',
      (WidgetTester tester) async {
    await pumpPlayer(tester);
    playerState(tester).hideControlsForTest();
    playerState(tester).lockControlsForTest();
    await tester.pump();

    // Double-tap in the center — at (400, 200), NOT (400, 300):
    // the 56 px unlock button sits at the exact screen center, so
    // a tap there unlocks (that is its job); above it is still the
    // center third for the double-tap handler. No play/pause flash,
    // no seek flash, still locked, overlay still hidden.
    await tester.tapAt(const Offset(400, 200));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(400, 200));
    await settleRealTime(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(playerState(tester).seekFlashVisibleForTest, isFalse);
    expect(find.text('-10 s'), findsNothing);
    expect(find.text('+10 s'), findsNothing);
    expect(playerState(tester).controlsLockedForTest, isTrue);
    expect(playerState(tester).controlsVisibleForTest, isFalse);
    await flushTimers(tester);
  });

  testWidgets('locked single tap does not toggle the overlay',
      (WidgetTester tester) async {
    await pumpPlayer(tester);
    playerState(tester).hideControlsForTest();
    playerState(tester).lockControlsForTest();
    await tester.pump();
    expect(playerState(tester).controlsVisibleForTest, isFalse);

    // A lone tap on empty video: unlocked it would show the
    // overlay; locked it must do nothing — the unlock button is
    // the only way back.
    await tester.tapAt(const Offset(150, 150));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(playerState(tester).controlsVisibleForTest, isFalse);
    expect(playerState(tester).controlsLockedForTest, isTrue);
    expect(find.byTooltip('Unlock controls'), findsOneWidget);
    await flushTimers(tester);
  });

  testWidgets('after unlock, normal gestures work again',
      (WidgetTester tester) async {
    await pumpPlayer(tester);
    playerState(tester).lockControlsForTest();
    playerState(tester).hideControlsForTest();
    await tester.pump();
    expect(find.byTooltip('Unlock controls'), findsOneWidget);

    await tester.tap(find.byTooltip('Unlock controls'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(playerState(tester).controlsLockedForTest, isFalse);
    expect(playerState(tester).controlsVisibleForTest, isTrue);

    // Single tap toggles the overlay off again…
    await tester.tapAt(const Offset(150, 150));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(playerState(tester).controlsVisibleForTest, isFalse);
    // …and on again.
    await tester.tapAt(const Offset(150, 150));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(playerState(tester).controlsVisibleForTest, isTrue);

    // …and a left-half drag lowers the brightness again (a 150 px
    // drag lands ~130 px after the touch slop, so ~48 — assert a
    // range, not the exact number).
    await tester.dragFrom(const Offset(200, 300), const Offset(0, 150));
    await tester.pump();
    expect(
      playerState(tester).brightnessLevelForTest,
      inExclusiveRange(20, 60),
    );
    await flushTimers(tester);
  });

  testWidgets('unlock works after a HUD has shown and faded',
      (WidgetTester tester) async {
    // 0.2.18 regression (user report on 0.2.17): the unlock button
    // was visible but tapping it did nothing. Root cause was NOT
    // the gesture arena — the button's opaque InkWell already
    // shields it from the double-tap detector below. The real
    // blocker was _GestureHud: it keeps the last shown HUD in an
    // invisible (opacity 0) decorated Container centred on the
    // screen, and BoxDecoration hit-tests true inside its rounded
    // bounds — so once ANY HUD had shown (volume / brightness /
    // drag-seek), that invisible box swallowed every later centre
    // tap, including on the unlock button. The HUD is now
    // IgnorePointer; this test proves the unlock survives a shown
    // and faded HUD.
    await pumpPlayer(tester);
    // Show the volume HUD with a right-side drag down (unlocked).
    await tester.dragFrom(const Offset(600, 300), const Offset(0, 150));
    await tester.pump();
    expect(find.textContaining('Volume'), findsOneWidget);
    // Let the HUD fade out (700 ms hide) — invisible now, but the
    // last state stays in the tree (opacity 0, Text still found
    // by the finder — that persistence IS the bug's mechanism).
    await tester.pump(const Duration(seconds: 2));
    final AnimatedOpacity hudOpacity = tester.widget<AnimatedOpacity>(
      find.ancestor(
        of: find.textContaining('Volume'),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(hudOpacity.opacity, 0.0);

    playerState(tester).lockControlsForTest();
    await tester.pump();
    expect(playerState(tester).controlsLockedForTest, isTrue);
    expect(find.byTooltip('Unlock controls'), findsOneWidget);

    await tester.tap(find.byTooltip('Unlock controls'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(playerState(tester).controlsLockedForTest, isFalse);
    await flushTimers(tester);
  });

  testWidgets('two rapid taps on the unlock button unlock',
      (WidgetTester tester) async {
    // 0.2.18: a frustrated user taps the unlock button repeatedly
    // and fast. The unlock fires on pointer-DOWN, so the first
    // touch unlocks even if the pair would have formed a
    // double-tap. tapAt (not tap on the finder): after the first
    // tap unlocks, the button is gone.
    await pumpPlayer(tester);
    playerState(tester).lockControlsForTest();
    await tester.pump();
    expect(playerState(tester).controlsLockedForTest, isTrue);
    expect(find.byTooltip('Unlock controls'), findsOneWidget);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(playerState(tester).controlsLockedForTest, isFalse);
    await flushTimers(tester);
  });
}
