// Single source of truth for all invoice layout, typography, and structure.
//
// invoice_preview.dart uses these values directly (Flutter design pixels,
// 820px-wide canvas). invoice_pdf.dart multiplies spacing/font values by
// [pdfScale] (A4 width in points ÷ design width) so both outputs share one
// set of numbers. Edit here; both renderers update on hot reload / next PDF.

import 'package:flutter/material.dart';

import 'package:timedart/features/invoices/invoice_document.dart';
import 'package:timedart/features/invoices/invoice_layout_plan.dart';

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
  static const double mastheadContactGap = 2.0; // business name → contact line
  static const double recipientGap = 8.0;
  static const double detailsBlockGap = 24.0;
  static const double detailsHeadingGap = 12.0;
  static const double tableHeaderGap = 8.0;
  static const double totalsGap = 0;
  static const double amountDueGap = 0;
  static const double paymentsHeadingGap = 8.0;
  static const double paymentsFieldGap = 8.0;
  static const double gridGutter = 6.0;
  static const double fieldValueGap = 4.0;
  static const double fieldPaddingH = 8.0;
  static const double fieldPaddingV = 6.0;
  static const double rowPaddingH = 8.0;
  static const double rowPaddingV = 6.0;
  static const double rowMarginBottom = 6.0;
  static const double fieldRadius = 4.0;

  // ── Typography ─────────────────────────────────────────────────────
  static const double fontLabel = 10.0;
  static const double fontCell = 12.0;
  static const double fontValue = 11.5;
  static const double fontInvoiceNumber = 20.0;
  static const double fontDetailsHeading = 16.0;
  static const double fontPaymentsHeading = 17.0;
  static const double fontAmountDue = 12.0;
  static const double fontHeadline = 20.0;

  // Font weights. The Flutter preview reads these directly from the single
  // Mona variable font (Flutter interpolates the wght axis). The PDF renderer
  // can't shift a variable axis, so it maps each to a pre-instanced static
  // Mona ttf: fontWeightValue→Regular, fontWeightLabel→Medium, fontWeightBold→
  // SemiBold. Keep the three weights distinct so the export mirrors the preview.
  static const FontWeight fontWeightLabel = FontWeight.w500;
  static const FontWeight fontWeightValue = FontWeight.w400;
  static const FontWeight fontWeightBold = FontWeight.w600;

  // Alpha for secondary ("muted") text painted over the background — the
  // masthead contact line and issue date. Both renderers apply it the same
  // way: the preview via a translucent colour, the PDF by compositing that
  // translucent primary over the background (PDFs can't paint transparency).
  static const double mutedAlpha = 0.55;

  // ── Logo ───────────────────────────────────────────────────────────
  static const double logoHeight = 38.0;
  // The "[Logo]" placeholder shown when a profile has no logo (and isn't the
  // default, which falls back to the timedart mark). A fixed box so preview and
  // PDF match; the PDF scales both by pdfScale.
  static const double logoPlaceholderWidth = 68.0;
  static const double logoPlaceholderRadius = 4.0;

  // ── Table columns ─────────────────────────────────────────────────
  // Flex weights for the 5-column line-items grid (ITEM / DATE / RATE / TIME / TOTAL).
  // Totals and AMOUNT DUE rows use the same weights so columns align top-to-bottom.
  static const int colItem = 3;
  static const int colDate = 1;
  static const int colRate = 1;
  static const int colTime = 1;
  static const int colTotal = 1;

  // ── Derived geometry ───────────────────────────────────────────────
  // The design canvas is a fixed width, so column widths are constants rather
  // than purely layout-driven. The AMOUNT DUE box is a single box spanning the
  // TIME + TOTAL columns; flex can't span two columns *plus* the gutter between
  // them (a flex-2 slot is only two column-units wide), so it takes this exact
  // pixel width instead and lands on the same edges as the flex columns above.
  static const double contentWidth = designWidth - 2 * pageMargin;
  static const int _colFlexTotal =
      colItem + colDate + colRate + colTime + colTotal;
  static const int _colGutters = 4; // five columns → four gutters
  static const double _colUnit =
      (contentWidth - _colGutters * gridGutter) / _colFlexTotal;
  // Width of the merged TIME + TOTAL value region (two columns + one gutter).
  static const double totalsValueWidth =
      _colUnit * (colTime + colTotal) + gridGutter;

  // Recipient grid: ORGANISATION (half) | EMAIL (quarter) | PHONE (quarter).
  // This is PHONE's quarter-width; the tax-no cell copies it so it lands on the
  // PHONE column's edges, and ADDRESS (an Expanded) fills the org+email span.
  static const double recipientCol = (contentWidth - 2 * gridGutter) / 4;

  // Payment/bank fields wrap into rows of this many columns.
  static const int payColumns = 3;

  // The TOTAL/tax rows span these leading columns with the row label before the
  // value cells begin (ITEM + DATE + RATE); TIME + TOTAL carry the values.
  static const int labelSpan = colItem + colDate + colRate;

  // ── Layout resolution ───────────────────────────────────────────────
  // Resolve an [InvoiceDocument] into an [InvoiceLayoutPlan]: every presence
  // decision and the risky recipient geometry, computed once so the preview and
  // PDF painters can't drift. Both painters consume the plan; neither decides
  // layout itself. See invoice_layout_plan.dart.
  static InvoiceLayoutPlan resolve(InvoiceDocument doc) {
    // Masthead logo: real bytes, else the fallback the document chose.
    final LogoPlan logo = doc.logo != null
        ? LogoPlan(LogoSlot.image, doc.logo)
        : switch (doc.logoFallback) {
            LogoFallback.brand => const LogoPlan(LogoSlot.brandMark),
            LogoFallback.placeholder => const LogoPlan(LogoSlot.placeholder),
            LogoFallback.none => const LogoPlan(LogoSlot.none),
          };

    // Contact line: only present fields, in e./t./w. order (gate on non-null to
    // match the existing renderers exactly).
    final contact = <ContactSpan>[
      if (doc.senderEmail != null) ContactSpan('e.', doc.senderEmail!),
      if (doc.senderPhone != null) ContactSpan('t.', doc.senderPhone!),
      if (doc.senderWebsite != null) ContactSpan('w.', doc.senderWebsite!),
    ];

    final masthead = MastheadPlan(
      logo: logo,
      showAddress: _present(doc.senderAddress),
      contact: contact,
    );

    final party = PartyPlan(
      showInvoiceNumber: doc.invoiceNumber != null,
      attValue: doc.attention ?? doc.organisation,
    );

    // Recipient grid row 2.
    final hasTaxCell = doc.recipientAbn != null;
    final hasAddress = doc.recipientAddress != null;
    final recipient = RecipientPlan(
      showSecondRow: hasAddress || hasTaxCell,
      showAddress: hasAddress,
      showTaxCell: hasTaxCell,
    );

    // Totals: tax row and reverse-charge statement are mutually exclusive.
    // Upstream already nulls [tax] under reverse charge; encode the XOR here so
    // a broken invariant can't print both.
    final showTaxRow = doc.tax != null;
    final totals = TotalsPlan(
      labelSpan: labelSpan,
      amountDueWidth: totalsValueWidth,
      showTaxRow: showTaxRow,
      showReverseCharge: doc.reverseCharge && !showTaxRow,
    );

    // Payments: bank fields (gated by showBank), chunked into rows.
    final fields = doc.showBank
        ? [for (final (l, v) in doc.paymentFields) PayField(l, v)]
        : const <PayField>[];
    final rows = <List<PayField>>[
      for (var i = 0; i < fields.length; i += payColumns)
        fields.sublist(i, (i + payColumns).clamp(0, fields.length)),
    ];
    final showLink = doc.showPaymentLink && _present(doc.paymentLink);
    final payments = PaymentsPlan(
      visible: rows.isNotEmpty || showLink,
      rows: rows,
      showLink: showLink,
      showPaymentNote: rows.isNotEmpty && doc.region.paymentNote != null,
    );

    return InvoiceLayoutPlan(
      masthead: masthead,
      party: party,
      recipient: recipient,
      totals: totals,
      payments: payments,
      geometry: const GeometryPlan(
        recipientQuarter: recipientCol,
        attColWidth: 2 * recipientCol,
      ),
    );
  }

  static bool _present(String? s) => s != null && s.trim().isNotEmpty;
}
