import 'package:flutter/material.dart';

/// EcoEarn brand colors.
abstract final class EcoColors {
  static const emerald = Color(0xFF16A34A);
  static const forest = Color(0xFF064E3B);
  static const deepForest = Color(0xFF022C22);
  static const mint = Color(0xFF4ADE80);
  static const teal = Color(0xFF0D9488);
  static const sky = Color(0xFF0284C7);
  static const amber = Color(0xFFF59E0B);
  static const coral = Color(0xFFE11D48);
  static const background = Color(0xFFF3F7F4);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);

  /// Dark green sweep used on the sidebar, sign-in panel and kiosk.
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [deepForest, forest, Color(0xFF15803D)],
  );

  /// Bright green used to highlight the most important card on a screen.
  static const highlightGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF15803D), emerald, Color(0xFF22C55E)],
  );
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
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: EcoColors.background,
    textTheme: base.textTheme.apply(bodyColor: EcoColors.ink, displayColor: EcoColors.ink).copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: EcoColors.ink),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: EcoColors.ink),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: EcoColors.ink),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: EcoColors.ink),
          labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 72,
      titleSpacing: 24,
      // Needs an explicit size: ThemeData.textTheme only gets sizes when Theme.of() localizes it.
      titleTextStyle: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: EcoColors.ink),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.all(6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE2EBE5)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF1F5F3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: EcoColors.emerald, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: rounded,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: rounded, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: const Color(0xFFE8F5EC),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(color: EcoColors.forest, fontWeight: FontWeight.w600),
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: const WidgetStatePropertyAll(Color(0xFFF1F7F3)),
      headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, color: EcoColors.forest),
      dividerThickness: 0.6,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: Colors.white.withValues(alpha: 0.16),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      selectedIconTheme: const IconThemeData(color: Colors.white),
      unselectedIconTheme: IconThemeData(color: Colors.white.withValues(alpha: 0.65)),
      selectedLabelTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
      minWidth: 88,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: EcoColors.forest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE8EFEA), space: 1),
  );
}
