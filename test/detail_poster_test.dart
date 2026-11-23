import 'package:anibee/models.dart';
import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/screens/detail_screen.dart';
import 'package:anibee/services/app_services.dart';
import 'package:anibee/settings_store.dart';
import 'package:anibee/widgets/poster.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 0.2.5: the detail banner is poster-only. The YouTube trailer embed
/// is gone (it failed on the phone with Error 153), so the banner
/// must show the poster image and nothing else — no webview, no
/// TRAILER badge, no tap-to-play, no error state.
///
/// Same player/store test scaffolding as player_double_tap_test.dart:
/// the real Player constructor stalls in the fake-time zone, so the
/// TrailerPlayer is built in runAsync and injected into DetailScreen.
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

  // Long anime (47 eps) -> the number grid, so the only PosterArt on
  // screen is the banner itself. No posterUrl -> gradient art, no
  // network image fetch in the test.
  const Anime anime = Anime(
    id: 'poster-test',
    title: 'Poster Test Anime',
    rating: 4.0,
    year: 2024,
    episodeCount: 47,
    genres: <String>['Action'],
    synopsis: 'Test anime for the poster-only banner test.',
    gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
  );

  testWidgets('detail banner shows only the poster, no trailer', (
    WidgetTester tester,
  ) async {
    // 0.2.17: Detail is a fixed header + scrolling list — the
    // header alone is ~610pt, taller than the default 800x600
    // test surface, so pump on a phone-size surface.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final SettingsStore store = await SettingsStore.load();
    final AppServices services = AppServices.create();
    late TrailerPlayer trailer;
    await tester.runAsync(() async {
      trailer = TrailerPlayer();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          anime: anime,
          store: store,
          services: services,
          player: trailer,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    // 0.2.13: _loadDetails/_loadSeasons resolve the id by title
    // over the real network (AppServices.create()); a failed
    // lookup retries once after 300 ms — pump past that window so
    // no retry Timer is pending at teardown.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // The banner is the poster art — exactly one, the hero.
    expect(find.byType(PosterArt), findsOneWidget);
    // No YouTube embed anywhere on the screen.
    expect(find.byType(WebViewWidget), findsNothing);
    // No trailer badge, no tap-to-play, no error text.
    expect(find.text('TRAILER'), findsNothing);
    expect(find.text('Watch video on YouTube'), findsNothing);
    expect(find.text('Video player configuration error'), findsNothing);
    // Everything else is still there (title + PLAY above the fold;
    // the episode list itself is covered by episode_progress_test —
    // the screen is a lazily-built ListView and the grid sits below
    // the fold, so it is not built until scrolled into view).
    expect(find.text(anime.title), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);
  });
}
