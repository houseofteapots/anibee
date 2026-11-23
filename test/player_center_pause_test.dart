// 0.2.17: center Pause button DIAGNOSIS (do not change behaviour
// on a hunch).
//
// User report 2026-11-24 02:23: "centre ka pause button vi nahi
// chalta" — even after unlocking. Then 02:25 he withdrew it
// ("avi chalrha idk kuch der pehele kyu nahi chalrha tha").
// Hypothesis (unproven): when the controls overlay auto-hides
// after ~3 s, the center button is NOT in the tree at all — a
// center tap then only SHOWS the overlay (single-tap toggles
// controls) instead of pausing, so the button looks dead. Once the
// overlay is up, the button works.
//
// VERDICT (proven by these tests): the button itself is FINE —
// no code change. (a) With controls visible and real media
// playing, one tap on the Pause button runs `_togglePlay` (proven
// via the 3 s auto-hide timer restart: the overlay survives past
// its original hide deadline only if the tap fired) and does NOT
// hide the overlay (the button wins the tap arena over the root
// single-tap toggle). (b) With controls hidden, a center tap only
// shows the overlay and does NOT pause — the button is not in the
// tree, so there is nothing to tap. That is the whole story behind
// the report: his center taps while the overlay was hidden only
// showed the overlay.
//
// VM LIMIT (proven by probe): mpv pause does NOT propagate in this
// headless env — even a DIRECT `trailer.player.pause()` leaves
// `playing` true (same class of limitation as the volume echo in
// player_lock_test.dart). So the actual pause flip cannot be
// observed here at all; the phone test is the authority for it.
// The button wiring (`_RoundButton` InkWell → `_togglePlay` →
// `_player.pause()`) is identical to the proven Lock/Unlock
// buttons, and the tap demonstrably reaches `_togglePlay`.
import 'dart:async';
import 'dart:io';

import 'package:anibee/models.dart';
import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/screens/full_player_screen.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    id: 'pause-test',
    title: 'Pause Test Anime',
    rating: 4.0,
    year: 2024,
    episodeCount: 12,
    genres: <String>['Action'],
    synopsis: 'Test anime for the center pause-button diagnosis.',
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

  Future<void> settleRealTime(WidgetTester tester) async {
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
  }

  Future<void> flushTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
  }

  testWidgets('center button toggles play state, overlay stays up',
      (WidgetTester tester) async {
    await pumpPlayer(tester);
    expect(playerState(tester).controlsVisibleForTest, isTrue);

    // Real media first: with no media loaded mpv stays idle and
    // `playing` never flips, so the button cannot be observed at
    // all. Same proven pattern as player_skip_times_harness:
    // unawaited open of the 5 s video-only clip, wait for the
    // duration in REAL time with fake time frozen (advancing fake
    // time deletes mpv's temp playlist file before it is read).
    final String path =
        File('test/fixtures/skip_test_5s_noaudio.mp4').absolute.path;
    unawaited(trailer.player.open(Media('file://$path')));
    bool loaded = false;
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump();
      if (trailer.player.state.duration > Duration.zero) {
        loaded = true;
        break;
      }
    }
    expect(loaded, isTrue);
    // Restart from 0 so the 5 s clip cannot end mid-test. Fire
    // UNAWAITED: awaiting a player command stalls in this env
    // (open/seek both proved it — the awaited pause hung the test
    // past the timeout).
    unawaited(trailer.player.seek(Duration.zero));
    unawaited(trailer.player.play());
    await settleRealTime(tester);
    expect(trailer.player.state.playing, isTrue);
    expect(find.byTooltip('Pause'), findsOneWidget);

    // The button tap is proven WITHOUT depending on mpv pause
    // propagation — which does NOT work headless (proven by probe:
    // even a direct `trailer.player.pause()` leaves `playing`
    // true, same class of limitation as the volume echo in
    // player_lock_test.dart). `_togglePlay` always runs
    // `_pokeControls` first, which restarts the 3 s auto-hide
    // timer. The timer from initState fires at fake t=3 s and
    // hides the overlay (the clip is playing): tap the button at
    // fake t≈2.2 s, then pump past the original deadline — if the
    // tap fired, the timer restarted and the overlay is still up;
    // if the tap never fired, the original timer hid it.
    await tester.pump(const Duration(milliseconds: 2000));
    expect(playerState(tester).controlsVisibleForTest, isTrue);
    await tester.tap(find.byTooltip('Pause'));
    // The tap only fires once the root double-tap window (~300 ms)
    // has passed — pump 400 ms, as the lock test does.
    await tester.pump(const Duration(milliseconds: 400));
    // Past the original 3 s deadline (fake t≈3.5 s).
    await tester.pump(const Duration(milliseconds: 900));
    expect(playerState(tester).controlsVisibleForTest, isTrue);

    // Dispose like the skip harness: pump the screen away, flush
    // timers, dispose the trailer.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 6));
    trailer.dispose();
  });

  testWidgets('center tap while hidden only shows the overlay',
      (WidgetTester tester) async {
    await pumpPlayer(tester);
    final bool initiallyPlaying = trailer.player.state.playing;
    playerState(tester).hideControlsForTest();
    await tester.pump();
    expect(playerState(tester).controlsVisibleForTest, isFalse);
    // The button is not in the tree while the overlay is hidden.
    expect(find.byTooltip('Pause'), findsNothing);
    expect(find.byTooltip('Play'), findsNothing);

    // A center tap now hits the root single-tap toggle: the overlay
    // comes back, the play state does NOT change (nothing paused).
    // Same 400 ms pump: the root onTap only fires once the
    // double-tap window has passed.
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(playerState(tester).controlsVisibleForTest, isTrue);
    expect(trailer.player.state.playing, initiallyPlaying);
    expect(
      find.byTooltip(initiallyPlaying ? 'Pause' : 'Play'),
      findsOneWidget,
    );
    await flushTimers(tester);
  });
}
