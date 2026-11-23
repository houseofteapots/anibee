// PREMIUM PICKER SCROLL (0.2.10, item 6): the shared picker used to
// render all options as a plain Column with NO scroll view — with
// 12 ranges (One Piece, 1180 eps) everything below 701-800 was cut
// off and unreachable. Now the options scroll inside a 70% cap with
// the title + drag handle fixed at the top; few-option pickers
// render exactly as before (shrink-wrapped, no empty space).
import 'package:anibee/models.dart';
import 'package:anibee/settings_store.dart';
import 'package:anibee/widgets/episode_list.dart';
import 'package:anibee/widgets/premium_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final TestDefaultBinaryMessenger messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall call) async => null,
    );
  });

  List<PremiumPickerOption<int>> rangeOptions() {
    return <PremiumPickerOption<int>>[
      for (int s = 1; s <= 1180; s += 100)
        PremiumPickerOption<int>(
          value: s,
          label:
              '${s.toString().padLeft(3, '0')}'
              '-${(s + 99).clamp(1, 1180).toString().padLeft(3, '0')}',
        ),
    ];
  }

  Future<void> pumpRangePicker(
    WidgetTester tester, {
    required List<PremiumPickerOption<int>> options,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return ElevatedButton(
              onPressed: () async {
                await showPremiumPicker<int>(
                  context: context,
                  title: 'Episode range',
                  selected: 1,
                  options: options,
                );
              },
              child: const Text('Open picker'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
  }

  group('showPremiumPicker with 12 ranges', () {
    testWidgets('last range is reachable by scrolling and selectable', (
      WidgetTester tester,
    ) async {
      await pumpRangePicker(tester, options: rangeOptions());
      expect(find.text('Episode range'), findsOneWidget);
      expect(find.text('001-100'), findsOneWidget);

      // The last range is NOT built yet: the list is lazy and the
      // option sits below the fold — before the 0.2.10 fix there was
      // no scroll view at all, so it could never be reached.
      expect(find.text('1101-1180'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('1101-1180'),
        200,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump();
      expect(find.text('1101-1180'), findsOneWidget);
      expect(tester.getCenter(find.text('1101-1180')).dy, lessThan(600));

      await tester.tap(find.text('1101-1180'));
      await tester.pumpAndSettle();
      expect(find.text('Episode range'), findsNothing);
    });

    testWidgets('tapping the last range returns its value', (
      WidgetTester tester,
    ) async {
      int? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () async {
                  picked = await showPremiumPicker<int>(
                    context: context,
                    title: 'Episode range',
                    selected: 1,
                    options: rangeOptions(),
                  );
                },
                child: const Text('Open picker'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('1101-1180'), 200);
      await tester.tap(find.text('1101-1180'));
      await tester.pumpAndSettle();
      expect(picked, 1101);
    });
  });

  group('showPremiumPicker with few options', () {
    testWidgets('all options visible, no empty space, tap works', (
      WidgetTester tester,
    ) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () async {
                  picked = await showPremiumPicker<String>(
                    context: context,
                    title: 'Preferred server',
                    selected: 'Miruro',
                    options: const <PremiumPickerOption<String>>[
                      PremiumPickerOption(value: 'Miruro', label: 'Miruro'),
                      PremiumPickerOption(value: 'AniKoto', label: 'AniKoto'),
                      PremiumPickerOption(value: 'AllAnime', label: 'AllAnime'),
                    ],
                  );
                },
                child: const Text('Open picker'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      // All three visible without scrolling.
      expect(find.text('Miruro'), findsOneWidget);
      expect(find.text('AniKoto'), findsOneWidget);
      expect(find.text('AllAnime'), findsOneWidget);
      // Shrink-wrapped: the sheet is far shorter than the 70% cap
      // (420pt) — no empty space below the options.
      expect(tester.getSize(find.byType(BottomSheet)).height, lessThan(300));
      await tester.tap(find.text('AniKoto'));
      await tester.pumpAndSettle();
      expect(picked, 'AniKoto');
    });
  });

  group('One Piece range flow (EpisodeSection)', () {
    const Anime onePiece = Anime(
      id: 'one-piece',
      anilistId: 21,
      title: 'One Piece',
      rating: 4.0,
      year: 1999,
      episodeCount: 1180,
      genres: <String>['Action'],
      synopsis: 'Test anime for the One Piece range picker flow.',
      gradient: <Color>[Color(0xFF3B2A6B), Color(0xFF120E24)],
    );

    testWidgets('range picker scrolls to 1101-1180 and the grid follows', (
      WidgetTester tester,
    ) async {
      final SettingsStore store = await SettingsStore.load();
      final List<Episode> episodes = mockEpisodes(onePiece);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 800,
              child: EpisodeSection(
                anime: onePiece,
                episodes: episodes,
                store: store,
                onPlay: (_) {},
                onToggleDownload: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Grid starts on 001-100.
      expect(find.text('001-100'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('1101'), findsNothing);

      await tester.tap(find.text('001-100'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('Episode range'), findsOneWidget);

      // The target has TWO scrollable ancestors (the sheet's list
      // and the outer SingleChildScrollView), so name the sheet's
      // list explicitly — otherwise scrollUntilVisible is ambiguous.
      await tester.scrollUntilVisible(
        find.text('1101-1180'),
        200,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('1101-1180'));
      await tester.pumpAndSettle();

      // The grid switched to the last range.
      expect(find.text('1101-1180'), findsOneWidget);
      expect(find.text('1101'), findsOneWidget);
      expect(find.text('1180'), findsOneWidget);
      expect(find.text('100'), findsNothing);
    });
  });
}
