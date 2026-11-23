import 'package:flutter/material.dart';

import '../theme.dart';

/// One option in a premium selection picker.
class PremiumPickerOption<T> {
  const PremiumPickerOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;

  /// Destructive action (e.g. "Remove from list"): red label, no
  /// checkmark. Not a selection — it is an action that closes the
  /// sheet with this value.
  final bool destructive;
}

/// Premium selection picker (0.2.8): the app-wide replacement for the
/// dull flat SimpleDialog pickers — a bottom sheet in the server-sheet
/// style, with an unmistakable selected state (accent checkmark +
/// accent-tinted row, bold label) and the Settings accent used
/// dynamically, never hardcoded. Returns the picked value, or null
/// when the sheet is dismissed.
Future<T?> showPremiumPicker<T>({
  required BuildContext context,
  required String title,
  required List<PremiumPickerOption<T>> options,
  required T? selected,
  String? subtitle,
}) {
  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  final Color accent = Theme.of(context).colorScheme.primary;
  final Color primaryText = isDark
      ? AppTheme.textPrimaryDark
      : AppTheme.textPrimaryLight;
  final Color secondaryText = isDark
      ? AppTheme.textSecondaryDark
      : AppTheme.textSecondaryLight;
  final Color sheetBg = isDark ? AppTheme.cardDark : AppTheme.cardLight;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: sheetBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A48),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                title,
                style: TextStyle(
                  color: primaryText,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  subtitle,
                  style: TextStyle(color: secondaryText, fontSize: 13),
                ),
              ),
            const SizedBox(height: 4),
            for (final PremiumPickerOption<T> option in options)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: _PremiumPickerRow<T>(
                  option: option,
                  isSelected: !option.destructive && option.value == selected,
                  accent: accent,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

class _PremiumPickerRow<T> extends StatelessWidget {
  const _PremiumPickerRow({
    required this.option,
    required this.isSelected,
    required this.accent,
    required this.primaryText,
    required this.secondaryText,
  });

  final PremiumPickerOption<T> option;
  final bool isSelected;
  final Color accent;
  final Color primaryText;
  final Color secondaryText;

  @override
  Widget build(BuildContext context) {
    final Color labelColor = option.destructive
        ? Colors.redAccent
        : primaryText;
    return InkWell(
      onTap: () => Navigator.of(context).pop(option.value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: accent.withValues(alpha: 0.45))
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          children: <Widget>[
            if (option.icon != null) ...<Widget>[
              Icon(
                option.icon,
                size: 20,
                color: isSelected ? accent : secondaryText,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    option.label,
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 15,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  if (option.subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      option.subtitle!,
                      style: TextStyle(color: secondaryText, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected) Icon(Icons.check_rounded, color: accent, size: 22),
          ],
        ),
      ),
    );
  }
}
