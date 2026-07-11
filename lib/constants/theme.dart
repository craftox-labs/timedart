import 'package:flutter/material.dart';
import 'package:timedart/constants/text_styles.dart';
import 'package:timedart/constants/tokens.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppTokens.colorSeed,
    brightness: brightness,
    primary: AppTokens.colorBrandPrimary,
    onPrimary: AppTokens.colorBrandOnPrimary,
  );

  // One source of truth for structural borders (dividers, app-bar hairline,
  // input rest state). Change it in AppTokens.colorBorder. Interactive
  // outlines (outlined buttons, focused inputs) stay primary — see below.
  const borderColor = AppTokens.colorBorder;

  // Buttons match the marketing site's .btn: 7px radius, 16×8 padding, Mona
  // 600 @ 15.5. Inputs/dialogs keep radiusSm (8px) via their own shapes below.
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTokens.radiusButton),
  );
  const buttonPadding = EdgeInsets.symmetric(
    horizontal: AppTokens.spaceMd, // 16
    vertical: AppTokens.spaceXs, // 8
  );
  const buttonTextStyle = TextStyle(
    fontFamily: AppTokens.fontFamily,
    fontSize: AppTokens.fontSizeButton,
    fontWeight: FontWeight.w600,
  );
  // Dialogs/inputs stay on the 8px corner — decoupled from the button radius.
  final panelShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily:
        AppTokens.fontFamily, // one source of truth — cascades to all text
    colorScheme: scheme,

    // ── Type scale: tweak roles once, applies everywhere ──
    // fontFamily is set explicitly on every role rather than relying on the
    // ThemeData(fontFamily:) cascade — that shortcut only reaches `textTheme`,
    // not component themes like `listTileTheme` below, so a role that leaves
    // it out here is a trap for any style built the same way elsewhere.
    textTheme: TextTheme(
      headlineLarge: const TextStyle(
        fontFamily: AppTokens.fontFamily,
        fontWeight: FontWeight.w300,
        letterSpacing: 5,
      ),
      // Display heading — Raleway Medium Italic, matched to the marketing site.
      // Only the onboarding flow uses headlineSmall today; size inherits the M3
      // default. Extend to other headings as we decide where else it fits.
      headlineSmall: const TextStyle(
        fontFamily: AppTokens.fontFamilyHeading,
        fontWeight: FontWeight.w500,
        fontStyle: FontStyle.italic,
      ),
      // Screen/dialog titles — Raleway Medium Italic, matching the onboarding
      // headings and the marketing site. Keeps the primary colour + tracking.
      titleLarge: const TextStyle(
        fontFamily: AppTokens.fontFamilyHeading,
        fontStyle: FontStyle.italic,
        color: AppTokens.colorBrandPrimary,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.25,
      ),
      titleMedium: const TextStyle(
        fontFamily: AppTokens.fontFamily,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
      bodyMedium: const TextStyle(
        fontFamily: AppTokens.fontFamily,
        height: AppTokens.fontHeightDefault,
        color: AppTokens.colorBrandPrimary,
        letterSpacing: 0.75,
      ),
      // Explainer / helper / empty-state text — muted throughout.
      bodySmall: TextStyle(
        fontFamily: AppTokens.fontFamily,
        color: scheme.onSurfaceVariant,
        letterSpacing: 1,
      ),
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
    // ListTile wraps its title/leading/trailing in a fresh default text style
    // built from these — that *replaces* rather than merges with the ambient
    // style, so any role left without fontFamily here silently falls back to
    // the platform default font instead of the app's, for every ListTile in
    // the app (the side panel and Settings panel are built entirely from
    // them). This is why explicit fontFamily matters more here than on a
    // plain Text widget, which merges with the true root style correctly.
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(vertical: AppTokens.space4xs),
      titleTextStyle: TextStyle(
        fontFamily: AppTokens.fontFamily,
        fontSize: AppTokens.fontSizeMd,
        color: scheme.onSurface,
      ),
      leadingAndTrailingTextStyle: TextStyle(
        fontFamily: AppTokens.fontFamily,
        fontSize: AppTokens.fontSizeSm,
        color: scheme.onSurfaceVariant, // subtler than the title
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      selectedTileColor: scheme.surfaceContainerHighest,
    ),

    // --- Buttons (matched to the marketing site's .btn variants) ---
    // Primary = site .btn-primary: a *tinted* fill (dim green bg + bright green
    // text + faint accent border), not M3's solid fill. Hover inverts to a
    // bright fill with near-black text.
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            shape: buttonShape,
            padding: buttonPadding,
            textStyle: buttonTextStyle,
            side: BorderSide(
              color: AppTokens.colorBrandPrimary.withValues(alpha: 0.30),
              width: AppTokens.strokeThin,
            ),
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.hovered)
                  ? AppTokens.colorAccentText
                  : AppTokens.colorAccentDim,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.hovered)
                  ? AppTokens.colorOnAccent
                  : AppTokens.colorAccentText,
            ),
          ),
    ),
    // Ghost = site .btn-ghost: transparent, neutral border at rest, accent
    // border + text on hover.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            shape: buttonShape,
            padding: buttonPadding,
            textStyle: buttonTextStyle,
          ).copyWith(
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return const BorderSide(
                  color: borderColor,
                  width: AppTokens.strokeThin,
                );
              }
              final hovered =
                  states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused);
              return BorderSide(
                color: hovered ? scheme.primary : borderColor,
                width: AppTokens.strokeThin,
              );
            }),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.hovered)
                  ? AppTokens.colorAccentText
                  : scheme.onSurface,
            ),
          ),
    ),
    // Text buttons share the button typography; accent-coloured like a link.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: buttonShape,
        padding: buttonPadding,
        textStyle: buttonTextStyle,
        foregroundColor: AppTokens.colorAccentText,
      ),
    ),

    // ── Switches ── ON state mirrors the primary button's tint: dim-green
    // track + bright-green thumb + faint accent outline (vs M3's solid bright
    // fill). OFF stays neutral.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return borderColor;
        if (states.contains(WidgetState.selected)) {
          return AppTokens.colorAccentText;
        }
        return scheme.onSurfaceVariant;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.surfaceContainerHighest;
        }
        if (states.contains(WidgetState.selected)) {
          return AppTokens.colorAccentDim;
        }
        return scheme.surface;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppTokens.colorBrandPrimary.withValues(alpha: 0.30);
        }
        return borderColor;
      }),
    ),

    // ── Dialogs ── 8px corner (radiusSm), not M3's large default. Covers the
    // entry editor and confirm dialogs alike.
    dialogTheme: DialogThemeData(
      shape: panelShape,
      // Modal titles: Raleway Medium Italic (like other headings) in the primary
      // colour. M3 would otherwise fall back to headlineSmall at onSurface.
      titleTextStyle: TextStyle(
        fontFamily: AppTokens.fontFamilyHeading,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w500,
        fontSize: 24, // M3 headlineSmall size
        color: scheme.primary,
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

    // ── Tooltips ── app surface + border, app font, faster reveal
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        border: Border.all(color: borderColor),
      ),
      textStyle: TextStyle(
        fontFamily: AppTokens.fontFamily,
        fontSize: AppTokens.fontSizeXs,
        color: scheme.onSurface,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: AppTokens.space4xs,
      ),
      preferBelow: false,
    ),

    // ── Snack bars ── floating, panel-coloured, primary hairline (matches
    // the app-bar/divider aesthetic) instead of the default dark pill.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.surface,
      contentTextStyle: TextStyle(
        fontFamily: AppTokens.fontFamily,
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
    // App-specific chrome text styles that don't fit Material's fixed
    // TextTheme roles without colliding with an existing role's meaning
    // elsewhere — see AppTextStyles' doc comment.
    extensions: [AppTextStyles.of(scheme)],
  );
}
