import 'package:flutter/material.dart';

class FxPalette {
  static const Color background = Color(0xFF171717);
  static const Color surface = Color(0xFF1F1F1F);
  static const Color surfaceRaised = Color(0xFF272727);
  static const Color panel = Color(0xFF1B1B1B);
  static const Color divider = Color(0xFF0D0D0D);
  static const Color dividerSoft = Color(0xFF141414);
  static const Color textPrimary = Color(0xFFF3F3F3);
  static const Color textMuted = Color(0xFF9A9A9A);
  static const Color textFaint = Color(0xFF666666);
  static const Color accent = Color(0xFF39C8C0);
  static const Color accentSoft = Color(0x8037CBC3);
  static const Color danger = Color(0xFFDD675A);
  static const Color previewTop = Color(0xFF292929);
  static const Color previewBottom = Color(0xFF121212);
  static const Color clipFill = Color(0xFF4A4A4A);
  static const Color clipFillAlt = Color(0xFF555555);
  static const Color clipStroke = Color(0xFF303030);
}

ThemeData buildFxTheme() {
  const base = ColorScheme.dark(
    primary: FxPalette.accent,
    secondary: FxPalette.accent,
    background: FxPalette.background,
    surface: FxPalette.surface,
    error: FxPalette.danger,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: base,
    scaffoldBackgroundColor: FxPalette.background,
    canvasColor: FxPalette.background,
    dividerColor: FxPalette.divider,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(
        color: FxPalette.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      bodySmall: TextStyle(
        color: FxPalette.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      titleMedium: TextStyle(
        color: FxPalette.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      labelLarge: TextStyle(
        color: FxPalette.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
