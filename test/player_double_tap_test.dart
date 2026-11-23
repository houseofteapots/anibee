import 'package:anibee/models.dart';
import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/screens/full_player_screen.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.4: double-tap must NOT show the player details/controls
/// overlay — it only seeks (with the flash) or play/pauses, and the
/// overlay stays exactly as it was. Plus the layout proofs: center
/// cluster at the exact vertical center, bottom row clustered flush
/// at the far right (0.2.5: 32px buttons, 4px gaps, 8pt right
/// padding), flat buttons with no circular background (0.2.5),
/// right-side panels.
///
/// The player is constructed for real (real libmpv on the VM, so the
/// VideoController init runs) but NO media is loaded: the screen's
/// initState fires unawaited player calls (expandToFull) that
/// deadlock media_kit's command path when raced with a real
/// open()/seek() in this test environment (sequential calls all
/// complete in ~1s; concurrent ones stall — see probe notes in the
/// session log). The flash is shown before the seek round-trip
/// (see _seekBy), so the double-tap feedback the test asserts does
/// not depend on the seek completing.
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
    id: 'double-tap-test',
    title: 'Double Tap Test Anime',
    rating: 4.0,
    year: 2024,
    episodeCount: 12,
    genres: <String>['Action'],
    synopsis: 'Test anime for the double-tap widget test.',
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
  /// alone never let them finish, so the flash would not be up yet
  /// when the expects run. Give real time a chance, then render.
  Future<void> settleRealTime(WidgetTester tester) async {
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
  }

  testWidgets('double-tap left seeks without showing the controls overlay', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    // Controls start visible; hide them through the test seam.
    playerState(tester).hideControlsForTest();
    await tester.pump();
    expect(playerState(tester).controlsVisibleForTest, isFalse);
    expect(find.text(anime.title), findsNothing);

    // Double-tap on the left third. The 100ms pump between the taps
    // is required: two tapAts with zero fake time between them are
    // ignored as a double-tap (kDoubleTapMinTime is 40ms).
    await tester.tapAt(const Offset(100, 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(100, 300));
    await settleRealTime(tester);
    await tester.pump(const Duration(milliseconds: 200));

    // The -10s flash proves the seek ran…
    expect(playerState(tester).seekFlashVisibleForTest, isTrue);
    expect(find.text('-10 s'), findsOneWidget);
    // …and the overlay stayed hidden.
    expect(playerState(tester).controlsVisibleForTest, isFalse);
    expect(find.text(anime.title), findsNothing);
  });

  testWidgets('double-tap center play/pauses without showing the overlay', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    playerState(tester).hideControlsForTest();
    await tester.pump();
    expect(find.text(anime.title), findsNothing);

    // Double-tap in the center (100ms gap — see the left-tap test).
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(400, 300));
    await settleRealTime(tester);
    await tester.pump(const Duration(milliseconds: 200));

    expect(playerState(tester).controlsVisibleForTest, isFalse);
    expect(find.text(anime.title), findsNothing);
  });

  testWidgets('single tap toggles the controls overlay off and on', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    // Tap an EMPTY part of the video (150,150): the center cluster
    // sits at (400,300) and the top/bottom bars own the edges, so a
    // tap there would hit a button, not the video.
    const Offset emptySpot = Offset(150, 150);
    // Controls start visible: one tap hides them all.
    expect(playerState(tester).controlsVisibleForTest, isTrue);
    await tester.tapAt(emptySpot);
    // A lone tap fires onTap only after the double-tap window.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(playerState(tester).controlsVisibleForTest, isFalse);
    expect(find.text(anime.title), findsNothing);

    // The next single tap shows them all again…
    await tester.tapAt(emptySpot);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(playerState(tester).controlsVisibleForTest, isTrue);
    expect(find.text(anime.title), findsOneWidget);

    // …and one more tap hides them again.
    await tester.tapAt(emptySpot);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(playerState(tester).controlsVisibleForTest, isFalse);
  });

  testWidgets('tapping a control button does not toggle the overlay', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    expect(playerState(tester).controlsVisibleForTest, isTrue);
    // The Subtitles button opens its panel; the overlay stays up —
    // the tap is absorbed by the button, never reaching the root
    // GestureDetector's toggle.
    await tester.tap(find.byTooltip('Subtitles'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(playerState(tester).controlsVisibleForTest, isTrue);
    expect(find.text('SUBTITLE STYLE'), findsOneWidget);
  });

  testWidgets('center cluster sits at the exact vertical center', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    final Offset center = tester.getCenter(find.byTooltip('Back 10 seconds'));
    expect(center.dy, closeTo(300, 2));
    expect(center.dx, lessThan(400));
  });

  testWidgets('bottom button row is clustered at the far right', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    // 0.2.5: Last button (Next) ends 8pt from the right edge:
    // center at 800 - 8 - 16 = 776 on the 800pt test surface
    // (32px buttons, 4px gaps).
    final Offset next = tester.getCenter(find.byTooltip('Next episode'));
    expect(next.dx, closeTo(776, 2));
    // First button (CC) starts in the right half, never mid-screen.
    final Offset cc = tester.getCenter(find.byTooltip('Subtitles'));
    expect(cc.dx, greaterThan(400));
  });

  testWidgets('round buttons have no circular background', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    // 0.2.5: the icons float directly over the video — no glossy
    // circle, no gradient, no border under any player button.
    final Iterable<Container> circles = tester.widgetList<Container>(
      find.byWidgetPredicate(
        (Widget w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle,
      ),
    );
    expect(circles, isEmpty);
    // No glossy CIRCULAR button either: a Container pairing a
    // LinearGradient with a circle shape. (A blanket "no gradient
    // anywhere" check false-positives on the video area's own
    // gradient backdrop, which is a rounded rect, not a circle.)
    final Iterable<Container> glossyCircles =
        tester.widgetList<Container>(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).shape ==
                    BoxShape.circle &&
                (w.decoration! as BoxDecoration).gradient
                    is LinearGradient,
          ),
        );
    expect(glossyCircles, isEmpty);
    // The buttons themselves are still there (0.2.5 bottom row:
    // 32px hit areas, Next center at 776 — see the far-right test).
    expect(find.byTooltip('Back 10 seconds'), findsOneWidget);
    expect(find.byTooltip('Next episode'), findsOneWidget);
    final Offset next = tester.getCenter(find.byTooltip('Next episode'));
    expect(next.dx, closeTo(776, 2));
  });

  testWidgets('subtitles button opens the right-side panel', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    await tester.tap(find.byTooltip('Subtitles'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The Zeus editor is in the panel: track list + load file +
    // the full style section with a live preview.
    expect(find.text('Load subtitle file'), findsOneWidget);
    expect(find.text('SUBTITLE STYLE'), findsOneWidget);
    expect(find.text('This is a subtitle preview'), findsOneWidget);
    expect(find.text('Text size'), findsOneWidget);
    expect(find.text('Text colour'), findsOneWidget);
    expect(find.text('Font'), findsOneWidget);
    expect(find.text('Bold'), findsOneWidget);
    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Outline'), findsOneWidget);
    expect(find.text('Position'), findsOneWidget);
    expect(find.text('Text opacity'), findsOneWidget);
    expect(find.text('Encoding'), findsOneWidget);
    expect(find.text('Auto-Adjust'), findsOneWidget);
    expect(find.text('Manual position'), findsOneWidget);
    // The panel sits on the right side of the screen.
    final Offset header = tester.getTopLeft(find.text('SUBTITLE STYLE'));
    expect(header.dx, greaterThan(400));
  });
}
