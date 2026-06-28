import 'package:flutter/material.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.lightGreenAccent,
    brightness: brightness,
    primary: Colors.lightGreenAccent,
    onPrimary: Colors.black,
  );

  return ThemeData(
    colorScheme: scheme,
    // ── Type scale: tweak roles once, applies everywhere ──
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontWeight: FontWeight.w300),
      titleMedium: TextStyle(fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(height: 1.4),
    ),
    // ── App bar ── flat, same colour as the body, with a primary hairline under it
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.primary,
      elevation: 0,
      scrolledUnderElevation:
          0, // M3 would otherwise lift/tint it when content scrolls under
      surfaceTintColor: Colors.transparent, // kill the M3 scroll tint overlay
      shape: Border(bottom: BorderSide(color: scheme.primary, width: 1)),
    ),
    // --- Divider ---
    dividerTheme: DividerThemeData(
      color: scheme.primary,
      space: 1,
      thickness: 1,
    ),
    // ── List rows (explicit, contrast-correct colours) ──
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(vertical: 2),
      titleTextStyle: TextStyle(fontSize: 16, color: scheme.onSurface),
      leadingAndTrailingTextStyle: TextStyle(
        fontSize: 15,
        color: scheme.onSurfaceVariant, // subtler than the title
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    // ── Floating action button ──
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    // ── Cards ──
    cardTheme: CardThemeData(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    // ── Text fields (ready for the TextField step) ──
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
    ),
    visualDensity: VisualDensity.comfortable, // desktop: a touch roomier
  );
}
