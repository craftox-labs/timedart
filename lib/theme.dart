import 'package:flutter/material.dart';
import 'package:time_tracker/tokens.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppTokens.colorSeed,
    brightness: brightness,
    primary: AppTokens.colorBrandPrimary,
    onPrimary: AppTokens.colorBrandOnPrimary,
  );

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: AppTokens.fontFamily, // one source of truth — cascades to all text
    colorScheme: scheme,

    // ── Type scale: tweak roles once, applies everywhere ──
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontWeight: FontWeight.w300),
      titleMedium: TextStyle(fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(height: AppTokens.fontHeightDefault),
    ),

    // ── App bar ── flat, same colour as the body, with a primary hairline under it
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.primary,
      elevation: 0,
      scrolledUnderElevation:
          0, // M3 would otherwise lift/tint it when content scrolls under
      surfaceTintColor: Colors.transparent, // kill the M3 scroll tint overlay
      shape: Border(
        bottom: BorderSide(color: scheme.primary, width: AppTokens.strokeThin),
      ),
    ),

    // --- Divider ---
    dividerTheme: DividerThemeData(
      color: scheme.primary,
      space: AppTokens.strokeThin,
      thickness: AppTokens.strokeThin,
    ),

    // ── List rows (explicit, contrast-correct colours) ──
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(vertical: AppTokens.space4xs),
      titleTextStyle: TextStyle(
        fontSize: AppTokens.fontSizeMd,
        color: scheme.onSurface,
      ),
      leadingAndTrailingTextStyle: TextStyle(
        fontSize: AppTokens.fontSizeSm,
        color: scheme.onSurfaceVariant, // subtler than the title
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),

    // --- Buttons ---
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: buttonShape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: 0.12) // faded when disabled
              : scheme.primary; // primary otherwise
          return BorderSide(color: color, width: AppTokens.strokeThick);
        }),
        shape: WidgetStatePropertyAll(buttonShape),
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
      margin: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLg,
        vertical: AppTokens.space2xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      ),
    ),

    // ── Text fields (ready for the TextField step) ──
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        borderSide: BorderSide(color: scheme.primary),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        borderSide: BorderSide(
          color: scheme.primary,
          width: AppTokens.strokeThick,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: AppTokens.space4xs,
        horizontal: AppTokens.spaceSm,
      ),
    ),

    visualDensity: VisualDensity.comfortable, // desktop: a touch roomier
  );
}
