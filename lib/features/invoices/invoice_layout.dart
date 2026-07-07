// Single source of truth for all invoice layout, typography, and structure.
//
// invoice_preview.dart uses these values directly (Flutter design pixels,
// 820px-wide canvas). invoice_pdf.dart multiplies spacing/font values by
// [pdfScale] (A4 width in points ÷ design width) so both outputs share one
// set of numbers. Edit here; both renderers update on hot reload / next PDF.

import 'package:flutter/material.dart';

abstract class InvoiceLayout {
  // ── Coordinate spaces ──────────────────────────────────────────────
  static const double designWidth = 820.0;
  static const double pdfPageWidth = 595.0; // A4 width in points
  static const double pdfScale = pdfPageWidth / designWidth; // ≈ 0.726

  // ── Spacing ────────────────────────────────────────────────────────
  static const double pageMargin = 48.0;
  static const double sectionGap = 32.0;
  static const double headlineGap = 16.0;
  static const double partyBlockGap = 24.0;
  static const double detailsBlockGap = 24.0;
  static const double detailsHeadingGap = 12.0;
  static const double tableHeaderGap = 8.0;
  static const double totalsGap = 8.0;
  static const double amountDueGap = 12.0;
  static const double paymentsHeadingGap = 8.0;
  static const double paymentsFieldGap = 8.0;
  static const double gridGutter = 6.0;
  static const double fieldValueGap = 4.0;
  static const double fieldPaddingH = 12.0;
  static const double fieldPaddingV = 5.0;
  static const double rowPaddingH = 12.0;
  static const double rowPaddingV = 5.0;
  static const double rowMarginBottom = 6.0;
  static const double fieldRadius = 6.0;

  // ── Typography ─────────────────────────────────────────────────────
  static const double fontLabel = 10.0;
  static const double fontCell = 12.0;
  static const double fontValue = 11.0;
  static const double fontInvoiceNumber = 20.0;
  static const double fontDetailsHeading = 16.0;
  static const double fontPaymentsHeading = 17.0;
  static const double fontAmountDue = 16.0;
  static const double fontHeadline = 20.0;

  // Font weights (Flutter preview uses these directly; the PDF renderer uses
  // separate font files for regular vs bold — [fontWeightBold] maps to
  // Urbanist-SemiBold.ttf, [fontWeightValue] to the variable font).
  static const FontWeight fontWeightLabel = FontWeight.w700;
  static const FontWeight fontWeightValue = FontWeight.w400;
  static const FontWeight fontWeightBold = FontWeight.w800;

  // ── Logo ───────────────────────────────────────────────────────────
  static const double logoHeight = 38.0;

  // ── Table columns ─────────────────────────────────────────────────
  // Flex weights for the 5-column line-items grid (ITEM / DATE / RATE / TIME / TOTAL).
  // Totals and AMOUNT DUE rows use the same weights so columns align top-to-bottom.
  static const int colItem = 4;
  static const int colDate = 1;
  static const int colRate = 1;
  static const int colTime = 1;
  static const int colTotal = 1;
}
