import 'package:flutter/material.dart';

import '../settings_store.dart';
import '../theme.dart';
import '../widgets/premium_picker.dart';
import '../widgets/settings_row.dart';

/// Player Settings — subtitle preview + Subtitles + Playback sections,
/// matching the approved mockup.
class PlayerSettingsScreen extends StatelessWidget {
  const PlayerSettingsScreen({super.key, required this.store});

  final SettingsStore store;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color secondaryText = isDark
        ? AppTheme.textSecondaryDark
        : AppTheme.textSecondaryLight;

    return Scaffold(
      appBar: AppBar(title: const Text('Player Settings')),
      body: ListenableBuilder(
        listenable: store,
        builder: (BuildContext context, Widget? _) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: <Widget>[
              // Live subtitle preview.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[Color(0xFF1B2A3A), Color(0xFF0A0A13)],
                    ),
                  ),
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: store.subPosition == 'Top' ? null : 14,
                        top: store.subPosition == 'Top' ? 40 : null,
                        child: Text(
                          'We’re nearly there. Stay close.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: kSubtitleColors[store.subColorIndex],
                            fontSize: store.subSize,
                            fontWeight: FontWeight.w700,
                            backgroundColor: store.subBackground
                                ? Colors.black.withValues(alpha: 0.55)
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SettingsSection(
                title: 'SUBTITLES',
                children: <Widget>[
                  SettingsTile(
                    title: 'Subtitle language',
                    trailing: Text(
                      _subtitleLanguageLabel(store.subtitleLanguage),
                      style: TextStyle(color: secondaryText, fontSize: 14),
                    ),
                    showChevron: true,
                    onTap: () => _pickSubtitleLanguage(context),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    title: 'Font',
                    trailing: Text(
                      store.subFont,
                      style: TextStyle(color: secondaryText, fontSize: 14),
                    ),
                    showChevron: true,
                    onTap: () => _pickFont(context),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    title: 'Size',
                    trailing: SizedBox(
                      width: 160,
                      child: Slider(
                        value: store.subSize,
                        min: 12,
                        max: 28,
                        divisions: 8,
                        onChanged: store.setSubSize,
                      ),
                    ),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    title: 'Color',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (int i = 0; i < kSubtitleColors.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: InkWell(
                              onTap: () => store.setSubColorIndex(i),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: kSubtitleColors[i],
                                  shape: BoxShape.circle,
                                  border: i == store.subColorIndex
                                      ? Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    title: 'Background',
                    trailing: Switch(
                      value: store.subBackground,
                      onChanged: store.setSubBackground,
                    ),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    title: 'Position',
                    trailing: Text(
                      store.subPosition,
                      style: TextStyle(color: secondaryText, fontSize: 14),
                    ),
                    showChevron: true,
                    onTap: () => _pickPosition(context),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    title: 'Delay',
                    trailing: Text(
                      '${store.subDelayMs}ms',
                      style: TextStyle(color: secondaryText, fontSize: 14),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Slider(
                      value: store.subDelayMs.toDouble(),
                      min: -1000,
                      max: 1000,
                      divisions: 20,
                      onChanged: (double v) => store.setSubDelayMs(v.toInt()),
                    ),
                  ),
                ],
              ),
              SettingsSection(
                title: 'PLAYBACK',
                children: <Widget>[
                  SettingsTile(
                    title: 'Double-tap seek',
                    trailing: Text(
                      '${store.doubleTapSeek} seconds',
                      style: TextStyle(color: secondaryText, fontSize: 14),
                    ),
                    showChevron: true,
                    onTap: () => _pickSeek(context),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    title: 'Playback speed',
                    trailing: Text(
                      '${store.playbackSpeed}x',
                      style: TextStyle(color: secondaryText, fontSize: 14),
                    ),
                    showChevron: true,
                    onTap: () => _pickSpeed(context),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    title: 'Autoplay countdown',
                    trailing: Text(
                      '${store.autoplayCountdownSeconds} seconds',
                      style: TextStyle(color: secondaryText, fontSize: 14),
                    ),
                    showChevron: true,
                    onTap: () => _pickAutoplayCountdown(context),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    title: 'Gestures',
                    trailing: Switch(
                      value: store.gestures,
                      onChanged: store.setGestures,
                    ),
                  ),
                  const SettingsDivider(),
                  SettingsTile(
                    title: 'Hardware decoding',
                    trailing: Switch(
                      value: store.hwDecoding,
                      onChanged: store.setHwDecoding,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  'Font: ${store.subFont} • '
                  'Color: ${kSubtitleColorNames[store.subColorIndex]}',
                  style: TextStyle(color: secondaryText, fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Preferred subtitle language (0.2.3): the player auto-selects
  /// this language's track when available. Auto = English by default.
  String _subtitleLanguageLabel(String value) {
    return switch (value) {
      'en' => 'English',
      'hi' => 'Hindi',
      'ar' => 'Arabic',
      'off' => 'Off',
      _ => 'Auto (English)',
    };
  }

  Future<void> _pickSubtitleLanguage(BuildContext context) async {
    const List<(String, String)> options = <(String, String)>[
      ('auto', 'Auto (English)'),
      ('en', 'English'),
      ('hi', 'Hindi'),
      ('ar', 'Arabic'),
      ('off', 'Off'),
    ];
    final String? picked = await showPremiumPicker<String>(
      context: context,
      title: 'Subtitle language',
      selected: store.subtitleLanguage,
      options: <PremiumPickerOption<String>>[
        for (final (String value, String label) in options)
          PremiumPickerOption<String>(value: value, label: label),
      ],
    );
    if (picked != null) await store.setSubtitleLanguage(picked);
  }

  Future<void> _pickFont(BuildContext context) async {
    const List<String> fonts = <String>[
      'Inter Semibold',
      'System',
      'Rounded',
      'Mono',
    ];
    final String? picked = await showPremiumPicker<String>(
      context: context,
      title: 'Subtitle font',
      selected: store.subFont,
      options: <PremiumPickerOption<String>>[
        for (final String f in fonts)
          PremiumPickerOption<String>(value: f, label: f),
      ],
    );
    if (picked != null) await store.setSubFont(picked);
  }

  Future<void> _pickPosition(BuildContext context) async {
    final String? picked = await showPremiumPicker<String>(
      context: context,
      title: 'Subtitle position',
      selected: store.subPosition,
      options: const <PremiumPickerOption<String>>[
        PremiumPickerOption(value: 'Bottom', label: 'Bottom'),
        PremiumPickerOption(value: 'Top', label: 'Top'),
      ],
    );
    if (picked != null) await store.setSubPosition(picked);
  }

  Future<void> _pickSeek(BuildContext context) async {
    final int? picked = await showPremiumPicker<int>(
      context: context,
      title: 'Double-tap seek',
      selected: store.doubleTapSeek,
      options: <PremiumPickerOption<int>>[
        for (final int s in <int>[5, 10, 15, 30])
          PremiumPickerOption<int>(value: s, label: '$s seconds'),
      ],
    );
    if (picked != null) await store.setDoubleTapSeek(picked);
  }

  Future<void> _pickSpeed(BuildContext context) async {
    final double? picked = await showPremiumPicker<double>(
      context: context,
      title: 'Playback speed',
      selected: store.playbackSpeed,
      options: <PremiumPickerOption<double>>[
        for (final double s in <double>[0.5, 1.0, 1.25, 1.5, 2.0])
          PremiumPickerOption<double>(value: s, label: '${s}x'),
      ],
    );
    if (picked != null) await store.setPlaybackSpeed(picked);
  }

  /// Up-next countdown (0.2.11): how long the player waits before
  /// auto-playing the next episode — 3 / 5 / 10 seconds.
  Future<void> _pickAutoplayCountdown(BuildContext context) async {
    final int? picked = await showPremiumPicker<int>(
      context: context,
      title: 'Autoplay countdown',
      selected: store.autoplayCountdownSeconds,
      options: <PremiumPickerOption<int>>[
        for (final int s in <int>[3, 5, 10])
          PremiumPickerOption<int>(value: s, label: '$s seconds'),
      ],
    );
    if (picked != null) await store.setAutoplayCountdownSeconds(picked);
  }
}
