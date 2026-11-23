import 'package:anibee/models.dart';
import 'package:anibee/player/subtitle_style.dart';
import 'package:anibee/player/trailer_player.dart';
import 'package:anibee/screens/full_player_screen.dart';
import 'package:anibee/settings_store.dart';
import 'package:anibee/widgets/subtitle_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 0.2.7 subtitle overlay tests.
///
/// ROOT CAUSE (0.2.5 + 0.2.6 phone tests, video proof): with the
/// default `PlayerConfiguration` (`libass: false`) mpv never
/// renders subtitles; the visible caption was media_kit_video's
/// built-in `SubtitleView` overlay with a FIXED default style, so
/// no `sub-*` property could ever change it. The app now hides
/// that overlay and renders its own (`SubtitleOverlay`) from
/// `player.stream.subtitle`, styled from the settings store.
/// These tests prove the new mechanism end to end:
/// - the built-in overlay is gone from the player tree;
/// - the panel's size / colour / position options change the
///   overlay's style + alignment through the store;
/// - the manual slider is draggable out of the box and dragging
///   it turns auto-adjust off.
void main() {
  group('SubtitleOverlay widget', () {
    TextStyle style({double size = 18, Color color = Colors.white}) {
      return buildSubtitleOverlayStyle(
        subSize: size,
        subFont: 'Inter Semibold',
        subColor: color,
        subOpacity: 100,
        subBold: false,
        subOutline: 'medium',
        subBackgroundMode: 'dark',
      );
    }

    Future<void> pumpOverlay(
      WidgetTester tester, {
      required List<String> lines,
      required TextStyle style,
      required Alignment alignment,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubtitleOverlay(
              lines: lines,
              style: style,
              alignment: alignment,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('renders lines with the given style + alignment',
        (WidgetTester tester) async {
      await pumpOverlay(
        tester,
        lines: <String>['Hello subtitle world', 'Second line here'],
        style: style(size: 24, color: const Color(0xFFFF0000)),
        alignment: const Alignment(0, 0.24),
      );
      final Finder text = find.text(
        'Hello subtitle world\nSecond line here',
      );
      expect(text, findsOneWidget);
      final Text widget = tester.widget<Text>(text);
      expect(widget.style?.fontSize, 24);
      expect(widget.style?.color, const Color(0xFFFF0000));
      expect(widget.textAlign, TextAlign.center);
      expect(
        tester.widget<Align>(find.byType(Align)).alignment,
        const Alignment(0, 0.24),
      );
    });

    testWidgets('empty / blank lines render nothing',
        (WidgetTester tester) async {
      await pumpOverlay(
        tester,
        lines: const <String>['', '   '],
        style: style(),
        alignment: Alignment.bottomCenter,
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('size / colour / bold / background follow the style',
        (WidgetTester tester) async {
      await pumpOverlay(
        tester,
        lines: const <String>['Hello'],
        style: buildSubtitleOverlayStyle(
          subSize: 20,
          subFont: 'Mono',
          subColor: const Color(0xFFFFD60A),
          subOpacity: 50,
          subBold: true,
          subOutline: 'thick',
          subBackgroundMode: 'solid',
        ),
        alignment: Alignment.center,
      );
      final Text widget = tester.widget<Text>(find.text('Hello'));
      expect(widget.style?.fontSize, 20);
      expect(widget.style?.fontFamily, 'Courier');
      expect(widget.style?.fontWeight, FontWeight.w700);
      expect(
        widget.style?.color,
        const Color(0xFFFFD60A).withValues(alpha: 0.5),
      );
      expect(widget.style?.backgroundColor, Colors.black);
      expect(widget.style?.shadows, hasLength(8));
    });
  });

  group('player wiring (panel -> store -> overlay)', () {
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
      id: 'subtitle-overlay-test',
      title: 'Subtitle Overlay Test Anime',
      rating: 4.0,
      year: 2024,
      episodeCount: 12,
      genres: <String>['Action'],
      synopsis: 'Test anime for the subtitle overlay wiring test.',
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

    Future<void> openSubtitlesPanel(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Subtitles'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('SUBTITLE STYLE'), findsOneWidget);
    }

    testWidgets('built-in media_kit subtitle overlay is hidden',
        (WidgetTester tester) async {
      await pumpPlayer(tester);
      // With libass: false the Video widget would render its own
      // SubtitleView overlay with a fixed style — the 0.2.5/0.2.6
      // bug. 0.2.7 passes visible: false, so no SubtitleView may
      // exist anywhere in the player tree.
      expect(find.byType(SubtitleView), findsNothing);
      // The app's own overlay is present (empty until a cue
      // arrives, so it renders a shrink, not text).
      expect(find.byType(SubtitleOverlay), findsOneWidget);
    });

    testWidgets('Text size + changes the store and the panel preview',
        (WidgetTester tester) async {
      await pumpPlayer(tester);
      await openSubtitlesPanel(tester);
      expect(find.text('18'), findsOneWidget);
      expect(store.subSize, 18);

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pump();
      expect(store.subSize, 19);
      expect(find.text('19'), findsOneWidget);
      // The preview and the overlay read the same store value, so
      // the preview's font size IS the on-screen size.
      final Text preview = tester.widget<Text>(
        find.text('This is a subtitle preview'),
      );
      expect(preview.style?.fontSize, 19);

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pump();
      expect(store.subSize, 20);
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets('manual slider is enabled by default (auto-adjust on)',
        (WidgetTester tester) async {
      await pumpPlayer(tester);
      expect(store.subAutoAdjust, isTrue);
      await openSubtitlesPanel(tester);
      // The manual slider (0–100) must be draggable even though
      // Auto-Adjust starts on — before the 0.2.5 fix its onChanged
      // was null, so it could not be moved at all out of the box.
      final Slider slider = tester.widget<Slider>(manualSlider());
      expect(slider.onChanged, isNotNull);
    });

    testWidgets('dragging the manual slider turns auto-adjust off',
        (WidgetTester tester) async {
      await pumpPlayer(tester);
      await openSubtitlesPanel(tester);
      expect(store.subAutoAdjust, isTrue);
      expect(store.subManualPercent, 0);
      // The slider is below the fold of the panel's scroll view —
      // bring it into view first, or the drag hits nothing.
      await tester.ensureVisible(manualSlider());
      await tester.pump();
      await tester.drag(manualSlider(), const Offset(80, 0));
      await tester.pump();
      // Dragging IS manual mode: auto-adjust switches off and the
      // manual position follows the drag — and the overlay's
      // alignment follows the same store value.
      expect(store.subAutoAdjust, isFalse);
      expect(store.subManualPercent, greaterThan(0));
      final double expectedY =
          -1 + 2 * ((100 - store.subManualPercent) / 100);
      expect(
        subtitleOverlayAlignment(
          subPosition: store.subPosition,
          subAutoAdjust: store.subAutoAdjust,
          subManualPercent: store.subManualPercent,
          controlsVisible: true,
        ).y,
        closeTo(expectedY, 0.001),
      );
    });
  });
}
