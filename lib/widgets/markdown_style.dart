import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:timedart/constants/tokens.dart';

/// The shared markdown style for rendered prose (the in-app docs reader and the
/// update-notes dialog). Body text stays in `onSurface` so only headings and
/// links carry the accent — keeping long-form content readable rather than a
/// wall of green.
MarkdownStyleSheet appMarkdownStyleSheet(ThemeData theme) {
  final scheme = theme.colorScheme;
  final base = TextStyle(
    fontFamily: AppTokens.fontFamily,
    fontSize: AppTokens.fontSizeDocsBody,
    fontWeight: AppTokens.fontWeightDocsBody,
    height: AppTokens.fontHeightDocsBody,
    color: scheme.onSurface,
  );
  final heading = TextStyle(
    fontFamily: AppTokens.fontFamilyHeading,
    fontStyle: FontStyle.italic,
    color: scheme.primary,
  );
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: base,
    listBullet: base,
    h1: heading.copyWith(
      fontSize: AppTokens.fontSizeDocsH1,
      fontWeight: AppTokens.fontWeightHeading,
    ),
    h2: heading.copyWith(
      fontSize: AppTokens.fontSizeDocsH2,
      fontWeight: AppTokens.fontWeightHeading,
    ),
    h3: heading.copyWith(
      fontSize: AppTokens.fontSizeDocsH3,
      fontWeight: AppTokens.fontWeightHeading,
    ),
    // Space before section headings so they breathe from the preceding block.
    // h1 is the page title (right under the eyebrow), so it stays tight.
    h2Padding: const EdgeInsets.only(top: AppTokens.spaceLg),
    h3Padding: const EdgeInsets.only(top: AppTokens.spaceMd),
    a: base.copyWith(
      color: AppTokens.colorAccentText,
      decoration: TextDecoration.underline,
    ),
    code: TextStyle(
      fontFamily: 'monospace',
      fontSize: AppTokens.fontSizeXs,
      color: scheme.onSurface,
      backgroundColor: scheme.surfaceContainerHighest,
    ),
    codeblockDecoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      border: Border.all(color: AppTokens.colorBorder),
    ),
    tableBorder: TableBorder.all(color: AppTokens.colorBorder),
    tableHead: base.copyWith(fontWeight: FontWeight.w600),
    // Flat: the docs reader draws its own callout/quote via a custom builder,
    // so clear the fromTheme default (a shadowed grey box) here.
    blockquotePadding: EdgeInsets.zero,
    blockquoteDecoration: const BoxDecoration(),
  );
}
