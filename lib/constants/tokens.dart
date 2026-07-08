import 'package:flutter/material.dart';

abstract class AppTokens {
  // ── 1. The Core Spacing Scale (T-Shirt Sizes) ──
  // Use these for padding, margins, gaps, and row insets symmetrically.
  static const double space4xs = 2.0;
  static const double space3xs = 4.0;
  static const double space2xs = 6.0;
  static const double spaceXs = 8.0;
  static const double spaceSm = 12.0;
  static const double spaceMd = 16.0;
  static const double spaceLg = 20.0;
  static const double spaceXl = 24.0;
  static const double space2xl = 32.0;

  // ── 2. Screen Architecture (Layout Bounds) ──
  static const double breakpointMd = 760.0;
  static const double maxContentWidth = 800.0;

  // ── 3. Borders & Shapes ──
  static const double radiusSm = 8.0;
  static const double radiusLg = 12.0;

  static const double strokeThin = 1.0;
  static const double strokeThick = 1.5;

  // ── 4. Typography ──
  static const String fontFamily = 'Mona';
  static const double fontHeightDefault = 1.4;
  static const double fontSizeXs = 13.0;
  static const double fontSizeSm = 14.0;
  static const double fontSizeMd = 18.0;

  // ── 5. Color Palette ──
  // Seed drives the M3 surface tones; keep it as the brand primary so the
  // palette stays coherent.
  static const Color colorSeed = Color(0xFF69E228);
  static const Color colorBrandPrimary = Color(0xFF69E228);
  static const Color colorBrandOnPrimary = Colors.black;
  static const Color colorBrandSecondary = Color(0xFF2E6C0F);
  static const Color colorBrandOnSecondary = Colors.white;
  // Structural borders app-wide: dividers, app-bar hairline, input rest state,
  // side-panel section/vertical dividers. The one knob — brighten/darken here.
  static const Color colorBorder = Color(0xFF4A5142);

  // ── 6. Icon Sizes ──
  static const double iconXs = 14.0; // For tight sub-lists or inline indicators
  static const double iconSm =
      16.0; // Standard compressed actions/secondary layout
  static const double iconMd = 20.0; // Default navigation/list tile metrics
  static const double iconLg = 24.0; // Main structural actions
}
