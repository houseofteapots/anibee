import 'package:anibee/models.dart';
import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/screens/full_player_screen.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.8 hold-to-2x: tap and hold the RIGHT side plays at 2x while
/// held, and releasing restores the previously selected speed (with a
/// small "2x" indicator while held). The hold must not fire on a
/// double-tap (+10s seek) or on a swipe, and the release must not
/// toggle the controls overlay.
///
/// Harness copied from player_double_tap_test.dart: the player is
/// constructed for real (real libmpv on the VM) but NO media is
/// loaded; the screen's initState player calls settle in real time.
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
    id: 'hold-speed-test',
    title: 'Hold Speed Test Anime',
    rating: 4.0,
    year: 2024,
    episodeCount: 12,
    genres: <String>['Action'],
    synopsis: 'Test anime for the hold-to-2x widget test.',
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

  testWidgets('holding the right side plays at 2x with an indicator', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    expect(playerState(tester).rateForTest, 1.0);
    expect(playerState(tester).hold2xForTest, isFalse);

    final TestGesture gesture = await tester.startGesture(
      const Offset(700, 300),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(playerState(tester).hold2xForTest, isTrue);
    expect(playerState(tester).rateForTest, 2.0);
    expect(
      find.byKey(const ValueKey('hold2x-indicator')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));
    expect(playerState(tester).hold2xForTest, isFalse);
    expect(playerState(tester).rateForTest, 1.0);
    expect(find.text('2x'), findsNothing);
  });

  testWidgets('releasing a hold does not toggle the controls overlay', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    final bool before = playerState(tester).controlsVisibleForTest as bool;
    final TestGesture gesture = await tester.startGesture(
      const Offset(700, 300),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(playerState(tester).hold2xForTest, isTrue);
    await gesture.up();
    // The tap recognizer fires after the double-tap window; the
    // hold-release guard must swallow it.
    await tester.pump(const Duration(milliseconds: 600));
    expect(playerState(tester).controlsVisibleForTest, before);
  });

  testWidgets('holding the left side does not engage 2x', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    final TestGesture gesture = await tester.startGesture(
      const Offset(100, 300),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(playerState(tester).hold2xForTest, isFalse);
    expect(playerState(tester).rateForTest, 1.0);
    expect(find.text('2x'), findsNothing);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('a quick double-tap still seeks and never engages 2x', (
    WidgetTester tester,
  ) async {
    await pumpPlayer(tester);
    playerState(tester).hideControlsForTest();
    await tester.pump();
    await tester.tapAt(const Offset(700, 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(700, 300));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(playerState(tester).hold2xForTest, isFalse);
    expect(playerState(tester).rateForTest, 1.0);
    expect(playerState(tester).seekFlashVisibleForTest, isTrue);
    expect(find.text('+10 s'), findsOneWidget);
  });
}
