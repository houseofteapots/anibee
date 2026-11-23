import 'package:anibee/widgets/premium_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 0.2.8: the premium picker replaces the dull flat SimpleDialog
/// pickers — the selected row must be unmistakable (accent checkmark
/// + accent tint) and tapping an option must return its value.
void main() {
  Future<void> pumpPicker(
    WidgetTester tester, {
    required String? selected,
    required List<PremiumPickerOption<String>> options,
    required ValueChanged<String?> onPicked,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) {
            return ElevatedButton(
              onPressed: () async {
                final String? picked = await showPremiumPicker<String>(
                  context: context,
                  title: 'Preferred server',
                  selected: selected,
                  options: options,
                );
                onPicked(picked);
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

  testWidgets('selected row has the accent checkmark, others do not', (
    WidgetTester tester,
  ) async {
    String? picked;
    await pumpPicker(
      tester,
      selected: 'Miruro',
      options: const <PremiumPickerOption<String>>[
        PremiumPickerOption(value: 'Miruro', label: 'Miruro'),
        PremiumPickerOption(value: 'AniKoto', label: 'AniKoto'),
        PremiumPickerOption(value: 'AllAnime', label: 'AllAnime'),
      ],
      onPicked: (String? v) => picked = v,
    );
    expect(find.text('Preferred server'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    // Tapping another option returns it and closes the sheet.
    await tester.tap(find.text('AniKoto'));
    await tester.pumpAndSettle();
    expect(picked, 'AniKoto');
    expect(find.text('Preferred server'), findsNothing);
  });

  testWidgets('destructive option renders red without a checkmark', (
    WidgetTester tester,
  ) async {
    String? picked;
    await pumpPicker(
      tester,
      selected: 'watching',
      options: const <PremiumPickerOption<String>>[
        PremiumPickerOption(value: 'watching', label: 'Watching'),
        PremiumPickerOption(
          value: '',
          label: 'Remove from list',
          destructive: true,
        ),
      ],
      onPicked: (String? v) => picked = v,
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    final Text removeText = tester.widget<Text>(find.text('Remove from list'));
    expect(removeText.style?.color, Colors.redAccent);
    await tester.tap(find.text('Remove from list'));
    await tester.pumpAndSettle();
    expect(picked, '');
  });
}
