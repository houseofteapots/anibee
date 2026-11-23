import 'package:anibee/models.dart';
import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/screens/full_player_screen.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PROOF TEST (0.2.6): the subtitle editor's FULL wiring, end to end —
/// panel tap → store → _applySubtitleStyle → the real mpv instance.
///
/// The user reports caption customization "still not working" on
/// 0.2.5. The mpv mechanism itself is proven (real-mpv frames in
/// ~/workspace/.tmp/subtest + the media_kit round-trip in
/// subtitle_mpv_delivery_test.dart), so this test proves the remaining
/// link inside the app: opening the Subtitles panel and tapping the
/// Text size "+" actually changes `sub-font-size` inside the shared
/// player, and the initState apply leaves the defaults in place.
/// If this passes, the whole in-app chain is proven and a phone-only
/// failure must be outside what this VM can reproduce.
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
    id: 'subtitle-panel-test',
    title: 'Subtitle Panel Test Anime',
    rating: 4.0,
    year: 2024,
    episodeCount: 12,
    genres: <String>['Action'],
    synopsis: 'Test anime for the subtitle panel wiring test.',
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

  Future<String> mpvProp(String key) async {
    final NativePlayer native = trailer.player.platform as NativePlayer;
    // waitForInitialization: false — the default waits re-await the
    // controller-init future inside the test's fake-async zone and
    // stall the test after the first call (see session log).
    return native.getProperty(key, waitForInitialization: false);
  }

  Future<double> mpvNum(String key) async =>
      double.parse(await mpvProp(key));

  testWidgets(
    'subtitle panel Text size + changes sub-font-size inside mpv',
    (WidgetTester tester) async {
      await pumpPlayer(tester);

      // initState applied the defaults: size 18 -> sub-font-size 36,
      // controls visible + Bottom + auto-adjust -> sub-pos 80, and
      // the 0.2.5 force override for ASS.
      expect(await mpvProp('sub-ass-override'), 'force');
      expect(await mpvNum('sub-font-size'), closeTo(36, 0.001));
      expect(await mpvNum('sub-pos'), closeTo(80, 0.001));

      // Open the Subtitles panel and tap Text size "+" (the first
      // add button in the panel — Text size is the first stepper).
      await tester.tap(find.byTooltip('Subtitles'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('SUBTITLE STYLE'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump();

      // 19 -> sub-font-size 38 inside the real mpv instance, and the
      // stepper value on screen moved with it.
      expect(await mpvNum('sub-font-size'), closeTo(38, 0.001));
      expect(find.text('19'), findsOneWidget);

      // One more tap: 20 -> 40.
      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump();
      expect(await mpvNum('sub-font-size'), closeTo(40, 0.001));
      expect(find.text('20'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
