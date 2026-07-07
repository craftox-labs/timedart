import 'package:flutter/material.dart';
import 'package:time_tracker/constants/tokens.dart';

/// App-chrome text styles that don't map cleanly onto Material's built-in
/// [TextTheme] roles — either because the role they'd naturally reuse already
/// has a different established meaning elsewhere (e.g. `titleSmall` is the
/// shortcuts modal's group heading, `labelLarge` is a date-picker field
/// label), or because one Material role can't carry two different baked
/// colours for two genuinely different semantic uses at the same size/weight.
///
/// A [ThemeExtension] rather than a plain constants class so every value —
/// family, size, weight, *and* colour — stays colorScheme-aware and lives in
/// [Theme], not scattered across widget files. Read via
/// `Theme.of(context).extension<AppTextStyles>()!`.
@immutable
class AppTextStyles extends ThemeExtension<AppTextStyles> {
  const AppTextStyles({
    required this.panelHeading,
    required this.rowTitle,
    required this.sectionHeader,
    required this.rowTitleSmall,
    required this.rowMeta,
  });

  /// Panel/settings title bar heading (e.g. "Settings").
  final TextStyle panelHeading;

  /// A row's own title at normal density (task row, client header).
  final TextStyle rowTitle;

  /// A collapsible section's header label (e.g. "Templates"/"Profiles").
  final TextStyle sectionHeader;

  /// A row's own title at high density (project row, template/profile entity row)
  /// — same weight as [rowMeta] but the row's primary colour, not muted.
  final TextStyle rowTitleSmall;

  /// Secondary/meta text at high density (subtitles, entry rows) — muted.
  final TextStyle rowMeta;

  factory AppTextStyles.of(ColorScheme scheme) => AppTextStyles(
    panelHeading: TextStyle(
      fontFamily: AppTokens.fontFamily,
      fontSize: AppTokens.fontSizeSm,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    ),
    rowTitle: TextStyle(
      fontFamily: AppTokens.fontFamily,
      fontSize: AppTokens.fontSizeSm,
      fontWeight: FontWeight.w400,
      letterSpacing: 1,
      color: scheme.onSurface,
    ),
    sectionHeader: TextStyle(
      fontFamily: AppTokens.fontFamily,
      fontSize: AppTokens.fontSizeMd,
      fontWeight: FontWeight.w400,
      color: scheme.onSurface,
    ),
    rowTitleSmall: TextStyle(
      fontFamily: AppTokens.fontFamily,
      fontSize: AppTokens.fontSizeXs,
      fontWeight: FontWeight.w300,
      letterSpacing: 1,
      color: scheme.onSurface,
    ),
    rowMeta: TextStyle(
      fontFamily: AppTokens.fontFamily,
      fontSize: AppTokens.fontSizeXs,
      fontWeight: FontWeight.w300,
      color: scheme.onSurfaceVariant,
    ),
  );

  @override
  AppTextStyles copyWith({
    TextStyle? panelHeading,
    TextStyle? rowTitle,
    TextStyle? sectionHeader,
    TextStyle? rowTitleSmall,
    TextStyle? rowMeta,
  }) => AppTextStyles(
    panelHeading: panelHeading ?? this.panelHeading,
    rowTitle: rowTitle ?? this.rowTitle,
    sectionHeader: sectionHeader ?? this.sectionHeader,
    rowTitleSmall: rowTitleSmall ?? this.rowTitleSmall,
    rowMeta: rowMeta ?? this.rowMeta,
  );

  // The app has one static theme (no animated light/dark transition), so
  // this doesn't need real interpolation — it's a required override.
  @override
  AppTextStyles lerp(ThemeExtension<AppTextStyles>? other, double t) {
    if (other is! AppTextStyles) return this;
    return t < 0.5 ? this : other;
  }
}
