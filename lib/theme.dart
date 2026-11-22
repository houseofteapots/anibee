import 'package:flutter/material.dart';

/// aniBee design tokens.
/// Dark mode: SOLID dark cards (no glassy/frosted panels).
/// Liquid glass lives ONLY on the bottom navigation pill.
class AppTheme {
  // Dark surfaces.
  static const Color bgDark = Color(0xFF0A0A13);
  static const Color cardDark = Color(0xFF17171F);
  static const Color cardDark2 = Color(0xFF1E1E2A);
  static const Color dividerDark = Color(0x1FFFFFFF);
  static const Color textPrimaryDark = Colors.white;
  static const Color textSecondaryDark = Color(0xFF8E8EA3);

  // Light surfaces.
  static const Color bgLight = Color(0xFFF4F4F8);
  static const Color cardLight = Colors.white;
  static const Color dividerLight = Color(0x1A000000);
  static const Color textPrimaryLight = Color(0xFF111118);
  static const Color textSecondaryLight = Color(0xFF6E6E80);

  static const Color success = Color(0xFF34C759);

  static ThemeData dark(Color accent) {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      colorScheme: ColorScheme.dark(
        primary: accent,
        secondary: accent,
        surface: cardDark,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      cardColor: cardDark,
      dividerColor: dividerDark,
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? success
              : const Color(0xFF3A3A48),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: const Color(0xFF3A3A48),
        thumbColor: Colors.white,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          color: textPrimaryDark,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(color: textPrimaryDark),
        bodySmall: TextStyle(color: textSecondaryDark),
      ),
    );
  }

  static ThemeData light(Color accent) {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: bgLight,
      colorScheme: ColorScheme.light(
        primary: accent,
        secondary: accent,
        surface: cardLight,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgLight,
        foregroundColor: textPrimaryLight,
        elevation: 0,
        centerTitle: true,
      ),
      cardColor: cardLight,
      dividerColor: dividerLight,
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? success
              : const Color(0xFFD5D5DE),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: const Color(0xFFD5D5DE),
        thumbColor: Colors.white,
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          color: textPrimaryLight,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(color: textPrimaryLight),
        bodySmall: TextStyle(color: textSecondaryLight),
      ),
    );
  }
}

/// Accent color choices (Zeus-style theme cards + color picker).
class AccentOption {
  const AccentOption(this.name, this.color);

  final String name;
  final Color color;
}

const List<AccentOption> kAccentOptions = <AccentOption>[
  AccentOption('Violet', Color(0xFF7C5CFF)),
  AccentOption('Blue', Color(0xFF2F7CF6)),
  AccentOption('Pink', Color(0xFFEC5A9E)),
  AccentOption('Green', Color(0xFF34C759)),
  AccentOption('Orange', Color(0xFFF59E0B)),
];

/// Subtitle color choices for the player settings preview.
const List<Color> kSubtitleColors = <Color>[
  Colors.white,
  Color(0xFFFFD60A),
  Color(0xFF2F7CF6),
  Color(0xFF34C759),
  Color(0xFFEC5A9E),
];

const List<String> kSubtitleColorNames = <String>[
  'White',
  'Yellow',
  'Blue',
  'Green',
  'Pink',
];
