import 'package:flutter/material.dart';

/// EcoEarn colors: warm neutrals with one green accent. Flat, no gradients.
abstract final class EcoColors {
  static const emerald = Color(0xFF16A34A); // the accent
  static const forest = Color(0xFF14532D);
  static const night = Color(0xFF0B2B20); // deep green for hero panels
  static const lime = Color(0xFFA3E635); // bright highlight on dark green
  static const mint = Color(0xFFE7F6EC); // light green tint
  static const teal = Color(0xFF0D9488);
  static const sky = Color(0xFF2563EB);
  static const amber = Color(0xFFF59E0B);
  static const coral = Color(0xFFE11D48);
  static const background = Color(0xFFF5F4F0);
  static const field = Color(0xFFF0EFEA);
  static const line = Color(0xFFEAE8E2);
  static const ink = Color(0xFF16181D);
  static const muted = Color(0xFF8B8F98);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: EcoColors.emerald,
    primary: EcoColors.emerald,
    secondary: EcoColors.teal,
    tertiary: EcoColors.amber,
    error: EcoColors.coral,
    surface: Colors.white,
  );
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'PlusJakartaSans',
    // Symbols the bundled font lacks (→, ●, ○) come from Windows' own fonts.
    fontFamilyFallback: const ['Segoe UI', 'Segoe UI Symbol'],
  );

  return base.copyWith(
    scaffoldBackgroundColor: EcoColors.background,
    textTheme: base.textTheme.apply(bodyColor: EcoColors.ink, displayColor: EcoColors.ink),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: EcoColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: EcoColors.field,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: EcoColors.emerald, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: rounded,
        // Small vertical padding: header buttons are 40 px high, and 2 × 16 px left the label 8 px.
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: rounded,
        side: const BorderSide(color: EcoColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: EcoColors.field,
      side: BorderSide.none,
      shape: const StadiumBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: EcoColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(color: EcoColors.line, space: 1),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: EcoColors.ink, borderRadius: BorderRadius.circular(8)),
    ),
  );
}
