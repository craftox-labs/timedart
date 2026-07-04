import 'package:flutter/material.dart';
import 'package:time_tracker/constants/tokens.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppTokens.colorSeed,
    brightness: brightness,
    primary: AppTokens.colorBrandPrimary,
    onPrimary: AppTokens.colorBrandOnPrimary,
    secondary: AppTokens.colorBrandSecondary,
    onSecondary: AppTokens.colorBrandOnSecondary,
  );

  // One source of truth for structural borders (dividers, app-bar hairline,
  // input rest state). Change it in AppTokens.colorBorder. Interactive
  // outlines (outlined buttons, focused inputs) stay primary — see below.
  const borderColor = AppTokens.colorBorder;

  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily:
        AppTokens.fontFamily, // one source of truth — cascades to all text
    colorScheme: scheme,

    // ── Type scale: tweak roles once, applies everywhere ──
    textTheme: TextTheme(
      headlineLarge: const TextStyle(fontWeight: FontWeight.w300),
      titleLarge: const TextStyle(
        color: AppTokens.colorBrandPrimary,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
      titleMedium: const TextStyle(fontWeight: FontWeight.w600),
      bodyMedium: const TextStyle(height: AppTokens.fontHeightDefault),
      // Explainer / helper / empty-state text — muted throughout.
      bodySmall: TextStyle(color: scheme.onSurfaceVariant),
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
        bottom: BorderSide(color: borderColor, width: AppTokens.strokeThin),
      ),
    ),

    // --- Divider ---
    // Top-level so ExpansionTile's expand borders inherit it too.
    dividerColor: borderColor,
    dividerTheme: DividerThemeData(
      color: borderColor,
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
      selectedTileColor: scheme.surfaceContainerHighest,
    ),

    // --- Buttons ---
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: buttonShape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.disabled)
              ? borderColor // disabled → the shared muted border
              : scheme.primary; // primary otherwise
          return BorderSide(color: color, width: AppTokens.strokeThick);
        }),
        shape: WidgetStatePropertyAll(buttonShape),
      ),
    ),

    // ── Dialogs ── same corner radius as buttons/inputs (radiusSm), not M3's
    // large default. Covers the entry editor and confirm dialogs alike.
    dialogTheme: DialogThemeData(shape: buttonShape),

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
      // Rest state uses the shared border colour; focusing brings in primary.
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        borderSide: BorderSide(color: borderColor),
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

    // ── Snack bars ── floating, panel-coloured, primary hairline (matches
    // the app-bar/divider aesthetic) instead of the default dark pill.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.surface,
      contentTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: AppTokens.fontSizeSm,
      ),
      actionTextColor: scheme.primary,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        side: BorderSide(color: borderColor, width: AppTokens.strokeThin),
      ),
    ),

    visualDensity: VisualDensity.comfortable, // desktop: a touch roomier
  );
}
