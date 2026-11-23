import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anibee/models.dart';
import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/screens/full_player_screen.dart';
import 'package:anibee/services/anilist_service.dart';
import 'package:anibee/services/aniskip_service.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared harness for the 0.2.9 Skip Intro player tests.
///
/// ONE real-media test per file: a libmpv Player created in an
/// earlier test in the same process permanently breaks later
/// loads in this env (duration stays 0 even after 30 s, while the
/// same test alone loads in ~10 s). Each media test therefore gets
/// its own file = its own fresh flutter_tester process. The
/// no-media deferral test can share a file with nothing else.
void configureSkipTestBindings() {
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
}

const Anime mha = Anime(
  id: 'skip-mha',
  title: 'My Hero Academia',
  rating: 4.0,
  year: 2016,
  episodeCount: 1,
  genres: <String>['Action'],
  synopsis: 'Test anime for the Skip Intro widget test.',
  gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
  malId: 31964,
);

const Anime mhaNoIds = Anime(
  id: 'skip-mha-no-ids',
  title: 'My Hero Academia',
  rating: 4.0,
  year: 2016,
  episodeCount: 1,
  genres: <String>['Action'],
  synopsis: 'Test anime for the Skip Intro title-resolve test.',
  gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
);

/// Canned AniSkip found:true for MHA S1 EP1 (live shape).
http.Response mhaSkipResponse() => http.Response(
  jsonEncode(<String, Object>{
    'found': true,
    'results': <Object>[
      <String, Object>{
        'skipType': 'op',
        'interval': <String, Object>{
          'startTime': 91.915,
          'endTime': 189.394,
        },
      },
      <String, Object>{
        'skipType': 'ed',
        'interval': <String, Object>{
          'startTime': 1313,
          'endTime': 1433,
        },
      },
    ],
  }),
  200,
);

class SkipPlayerHarness {
  late SettingsStore store;
  late TrailerPlayer trailer;
  late List<http.Request> skipRequests;

  AniSkipService recordingSkipService() {
    return AniSkipService(
      client: MockClient((http.Request req) async {
        skipRequests.add(req);
        return mhaSkipResponse();
      }),
    );
  }

  Future<void> pumpPlayer(
    WidgetTester tester, {
    required Anime anime,
    AniSkipService? aniSkip,
    AniListService? anilist,
  }) async {
    store = await SettingsStore.load();
    skipRequests = <http.Request>[];
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
          aniSkip: aniSkip,
          anilist: anilist,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  dynamic playerState(WidgetTester tester) =>
      tester.state(find.byType(FullPlayerScreen)) as dynamic;

  /// Open the 5 s local clip on the shared player (real libmpv) so
  /// the duration genuinely becomes known.
  ///
  /// The clip is VIDEO-ONLY (no audio track): with audio, mpv's
  /// headless audio init (ALSA/JACK) stalls the load and the
  /// position clock never advances in this env; video-only loads
  /// and the duration listener (0.2.9) fires the retry. The
  /// duration listener — not position ticks — is what the test
  /// proves, which is also the point on the phone: the retry fires
  /// the moment the duration is known.
  ///
  /// Proven by probe (2026-11-23): in flutter_test, AWAITING
  /// `player.open()` never returns — the open Future stalls even
  /// though the media loads (plain-Dart `dart run` of the same open
  /// completes in <1 s). So the open is fired UNAWAITED and this
  /// waits for the duration to become known instead: ~10 s real
  /// time in this env (mpv init is slow headless), duration 5.0 s.
  ///
  /// The wait loop uses plain `pump()` (fake time FROZEN) on
  /// purpose: media_kit schedules deletion of the temp playlist
  /// file 5 s after open() — in fake time. Advancing fake time
  /// with `pump(Duration)` deletes that file before mpv's slow
  /// command loop ever reads it, so the clip never loads. The
  /// timer is flushed in disposePlayer instead, after the media
  /// has loaded.
  Future<void> openTestClip(WidgetTester tester) async {
    final String path =
        File('test/fixtures/skip_test_5s_noaudio.mp4').absolute.path;
    unawaited(trailer.player.open(Media('file://$path')));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump();
      if (trailer.player.state.duration > Duration.zero) return;
    }
    fail('test clip did not load: duration stayed 0 after 30 s');
  }

  /// Dispose the player + screen at the end of a test that opened
  /// media, so no fake Timer (screen hide timer, mpv temp-file
  /// timer) is left pending at teardown.
  Future<void> disposePlayer(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 6));
    trailer.dispose();
  }

  /// Real-time wait for the Skip data to land (duration listener +
  /// the mock HTTP round-trip both run in real time). Plain pump()
  /// — same temp-playlist reason as openTestClip.
  Future<bool> waitForSkip(WidgetTester tester, {int maxMs = 10000}) async {
    final Stopwatch sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < maxMs) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump();
      if (playerState(tester).skipTimesForTest != null) return true;
    }
    return false;
  }
}
