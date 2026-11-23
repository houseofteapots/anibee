import 'package:anibee_mpv_pip/anibee_mpv_pip.dart';
import 'package:anibee/models.dart';
import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/screens/full_player_screen.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.9 PiP: (a) do not call enterPiP until the native layer is
/// primed — the phone failed with primed=false / ingest=0 because
/// the pip player's first frame (HLS open + seek + decode) takes
/// longer than the Swift side's ~3 s enter poll; (b) the raw native
/// diagnostic must never reach the user — one short Hinglish line
/// instead.
void main() {
  group('AnibeeMpvPip.diagIsPrimed', () {
    // The EXACT diag string from the phone failure (2026-11-23):
    // frames=0, primed=false, primes=0 — no frame ever arrived.
    const String phoneDiag =
        'layer=0 inWindow=true possible=true pipActive=false '
        'audio=AVAudioSessionCategoryPlayback frames=0 ingest=0 '
        'liveEnq=0 liveDrop=0 liveAgeMs=-1 primed=false primeAgeMs=-1 '
        'primes=0 poolFail=0 poolStatus=0 layerFail=0 layerErr=none '
        'ptsDeltaMs=0 upd=0 rend=0 rendMs=0.0';

    test('the phone failure diag is NOT primed', () {
      expect(AnibeeMpvPip.diagIsPrimed(phoneDiag), isFalse);
    });

    test('primed=true with frames ingested IS primed', () {
      expect(
        AnibeeMpvPip.diagIsPrimed(
          phoneDiag
              .replaceAll('frames=0', 'frames=12')
              .replaceAll('ingest=0', 'ingest=12')
              .replaceAll('primed=false', 'primed=true')
              .replaceAll('primeAgeMs=-1', 'primeAgeMs=120')
              .replaceAll('primes=0', 'primes=3'),
        ),
        isTrue,
      );
    });

    test('empty / unrelated strings are not primed', () {
      expect(AnibeeMpvPip.diagIsPrimed(''), isFalse);
      expect(AnibeeMpvPip.diagIsPrimed('not iOS'), isFalse);
      expect(AnibeeMpvPip.diagIsPrimed('primed=false'), isFalse);
      // No substring trickery: 'primed=truex' is not a match.
      expect(AnibeeMpvPip.diagIsPrimed('primed=truex'), isFalse);
    });
  });

  group('AnibeeMpvPip.waitForPrime', () {
    test('times out (false) when the layer never primes', () async {
      // Off iOS, diag is 'not iOS' — never primed — so the wait
      // must give up at the timeout instead of hanging.
      final AnibeeMpvPip bridge = AnibeeMpvPip();
      final Stopwatch sw = Stopwatch()..start();
      final bool primed = await bridge.waitForPrime(
        timeout: const Duration(milliseconds: 600),
        interval: const Duration(milliseconds: 100),
      );
      expect(primed, isFalse);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });
  });

  group('PiP failure message (player screen)', () {
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

    testWidgets('the user-facing PiP failure line is one short line',
        (WidgetTester tester) async {
      final SettingsStore store = await SettingsStore.load();
      late TrailerPlayer trailer;
      await tester.runAsync(() async {
        trailer = TrailerPlayer();
      });
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      const Anime anime = Anime(
        id: 'pip-msg-test',
        title: 'PiP Message Test Anime',
        rating: 4.0,
        year: 2024,
        episodeCount: 1,
        genres: <String>['Action'],
        synopsis: 'Test anime.',
        gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
      );
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
      final dynamic state =
          tester.state(find.byType(FullPlayerScreen)) as dynamic;
      // The raw PGPegasusErrorDomain dump must never be the message.
      expect(
        state.pipFailedMessageForTest as String,
        'PiP nahi khula — dobara try karo.',
      );
      expect(
        state.pipFailedMessageForTest as String,
        isNot(contains('PGPegasus')),
      );
      expect(
        state.pipFailedMessageForTest as String,
        isNot(contains('primed=')),
      );
    });
  });
}
