import 'package:anibee/models.dart';
import 'package:anibee/player/subtitle_style.dart';
import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/screens/full_player_screen.dart';
import 'package:anibee/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.5 subtitle editor: the style options must reach mpv AND apply
/// to ASS subtitles (mpv's default sub-ass-override=scale ignores
/// them), and the manual position slider must be draggable out of
/// the box (it was disabled while Auto-Adjust was on — the default).
void main() {
  group('buildSubtitleMpvProperties', () {
    Map<String, String> props({
      double subSize = 18,
      String subFont = 'Inter Semibold',
      Color subColor = Colors.white,
      int subOpacity = 100,
      bool subBold = false,
      String subOutline = 'medium',
      String subBackgroundMode = 'dark',
      String subEncoding = 'auto',
      int subDelayMs = 200,
      double subPos = 100,
    }) {
      return buildSubtitleMpvProperties(
        subSize: subSize,
        subFont: subFont,
        subColor: subColor,
        subOpacity: subOpacity,
        subBold: subBold,
        subOutline: subOutline,
        subBackgroundMode: subBackgroundMode,
        subEncoding: subEncoding,
        subDelayMs: subDelayMs,
        subPos: subPos,
      );
    }

    test('forces the ASS override so style options apply to ASS subs',
        () {
      final Map<String, String> p = props();
      // Without this, mpv ignores every style option below for ASS
      // subtitles (the "nothing works" bug).
      expect(p['sub-ass-override'], 'force');
      expect(p['sub-ass-force-margins'], 'yes');
    });

    test('size / font / bold map to mpv options', () {
      final Map<String, String> p = props(
        subSize: 18,
        subFont: 'System',
        subBold: true,
      );
      expect(p['sub-font-size'], '36.0');
      expect(p['sub-font'], 'sans-serif');
      expect(p['sub-bold'], 'yes');
      expect(props(subBold: false)['sub-bold'], 'no');
      expect(props(subFont: 'Rounded')['sub-font'], 'Arial Rounded MT Bold');
      expect(props(subFont: 'Mono')['sub-font'], 'monospace');
    });

    test('colour carries the opacity in its alpha channel', () {
      // toRadixString gives lowercase hex; mpv accepts either case.
      expect(props()['sub-color'], '#ffffffff');
      expect(props(subOpacity: 50)['sub-color'], '#80ffffff');
      expect(props(subOpacity: 0)['sub-color'], '#00ffffff');
      expect(
        props(subColor: const Color(0xFFFF0000))['sub-color'],
        '#ffff0000',
      );
    });

    test('outline / background map to border and back colours', () {
      expect(props(subOutline: 'none')['sub-border-size'], '0');
      expect(props(subOutline: 'thin')['sub-border-size'], '1');
      expect(props(subOutline: 'medium')['sub-border-size'], '2');
      expect(props(subOutline: 'thick')['sub-border-size'], '3');
      expect(props(subOutline: 'medium')['sub-border-color'], '#FF000000');
      expect(props(subBackgroundMode: 'off')['sub-back-color'], '#00000000');
      expect(props(subBackgroundMode: 'dark')['sub-back-color'], '#CC000000');
      expect(
        props(subBackgroundMode: 'solid')['sub-back-color'],
        '#FF000000',
      );
    });

    test('encoding / delay / position pass through', () {
      expect(props()['sub-codepage'], 'auto');
      expect(props(subEncoding: 'utf-8')['sub-codepage'], 'utf-8');
      expect(props()['sub-delay'], '0.20');
      expect(props(subDelayMs: -500)['sub-delay'], '-0.50');
      expect(props(subPos: 80)['sub-pos'], '80');
      expect(props(subPos: 50)['sub-pos'], '50');
    });
  });

  group('manual position slider (widget)', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    setUpAll(() {
      MediaKit.ensureInitialized();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final TestDefaultBinaryMessenger messenger =
          TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger;
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
      id: 'subtitle-style-test',
      title: 'Subtitle Style Test Anime',
      rating: 4.0,
      year: 2024,
      episodeCount: 12,
      genres: <String>['Action'],
      synopsis: 'Test anime for the subtitle editor widget test.',
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

    Finder manualSlider() => find.byWidgetPredicate(
      (Widget w) => w is Slider && w.min == 0 && w.max == 100,
    );

    testWidgets('manual slider is enabled by default (auto-adjust on)',
        (WidgetTester tester) async {
      await pumpPlayer(tester);
      expect(store.subAutoAdjust, isTrue);
      await tester.tap(find.byTooltip('Subtitles'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The manual slider (0–100) must be draggable even though
      // Auto-Adjust starts on — before the fix its onChanged was
      // null, so it could not be moved at all out of the box.
      final Slider slider = tester.widget<Slider>(manualSlider());
      expect(slider.onChanged, isNotNull);
    });

    testWidgets('dragging the manual slider turns auto-adjust off',
        (WidgetTester tester) async {
      await pumpPlayer(tester);
      await tester.tap(find.byTooltip('Subtitles'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.subAutoAdjust, isTrue);
      expect(store.subManualPercent, 0);
      // The slider is below the fold of the panel's scroll view —
      // bring it into view first, or the drag hits nothing.
      await tester.ensureVisible(manualSlider());
      await tester.pump();
      await tester.drag(manualSlider(), const Offset(80, 0));
      await tester.pump();
      // Dragging IS manual mode: auto-adjust switches off and the
      // manual position follows the drag.
      expect(store.subAutoAdjust, isFalse);
      expect(store.subManualPercent, greaterThan(0));
    });
  });
}
