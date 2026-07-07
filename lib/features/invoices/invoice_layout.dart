// Single source of truth for all invoice spacing and typography.
//
// invoice_preview.dart uses these values directly (Flutter design pixels,
// 820px-wide canvas). invoice_pdf.dart multiplies each value by [pdfScale]
// (A4 width in points ÷ design width) so the two outputs share one set of
// numbers to tune. Edit here; both renderers update on hot reload / next PDF
// export.

abstract class InvoiceLayout {
  // ── Coordinate spaces ──────────────────────────────────────────────
  static const double designWidth = 820.0;
  static const double pdfPageWidth = 595.0; // A4 width in points
  static const double pdfScale = pdfPageWidth / designWidth; // ≈ 0.726

  // ── Spacing ────────────────────────────────────────────────────────
  static const double pageMargin = 64.0;
  static const double sectionGap = 32.0;
  static const double headlineGap = 16.0;
  static const double partyBlockGap = 24.0;
  static const double detailsBlockGap = 24.0;
  static const double detailsHeadingGap = 12.0;
  static const double tableHeaderGap = 8.0;
  static const double totalsGap = 8.0;
  static const double amountDueGap = 8.0;
  static const double paymentsHeadingGap = 8.0;
  static const double paymentsFieldGap = 8.0;
  static const double gridGutter = 12.0;
  static const double fieldValueGap = 4.0;
  static const double fieldPaddingH = 12.0;
  static const double fieldPaddingV = 8.0;
  static const double rowPaddingH = 12.0;
  static const double rowPaddingV = 4.0;
  static const double rowMarginBottom = 12.0;
  static const double fieldRadius = 6.0;

  // ── Typography ─────────────────────────────────────────────────────
  static const double fontLabel = 10.0;
  static const double fontCell = 12.0;
  static const double fontValue = 12.0;
  static const double fontInvoiceNumber = 20.0;
  static const double fontDetailsHeading = 16.0;
  static const double fontPaymentsHeading = 17.0;
  static const double fontAmountDue = 16.0;
  static const double fontHeadline = 20.0;
}
