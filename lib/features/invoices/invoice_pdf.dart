import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:time_tracker/constants/format.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/invoices/invoice_document.dart';
import 'package:time_tracker/features/invoices/invoice_layout.dart';

// Renders an [InvoiceDocument] into a branded PDF using an [InvoiceTemplate].
// All sizing constants live in [InvoiceLayout] — multiply each by [InvoiceLayout.pdfScale]
// to convert from the shared design-pixel space to PDF points (A4 595pt wide).
// invoice_preview.dart uses the same constants directly (no scale), keeping
// both outputs in parity from one source of truth.

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

// Shorthand: design value → PDF points.
double _p(double v) => v * InvoiceLayout.pdfScale;

Future<Uint8List> buildBrandedInvoicePdf({
  required InvoiceDocument doc,
  required InvoiceTemplate template,
}) async {
  final fontData = await rootBundle.load(
    'assets/fonts/Urbanist-VariableFont_wght.ttf',
  );
  final boldFontData = await rootBundle.load(
    'assets/fonts/Urbanist-SemiBold.ttf',
  );
  final font = pw.Font.ttf(fontData);
  final bold = pw.Font.ttf(boldFontData);

  final logoBytes =
      template.logo ??
      (await rootBundle.load('assets/logo/timedart_logo_horizontal.png'))
          .buffer
          .asUint8List();

  final bg = PdfColor.fromInt(template.colorBackground);
  final surface = PdfColor.fromInt(template.colorSurface);
  final primary = PdfColor.fromInt(template.colorPrimary);
  final text = PdfColor.fromInt(template.colorText); // text on surface (field box values)
  // Secondary text on background: primary at [mutedAlpha], composited over the
  // background since a PDF fill can't be translucent. Mirrors the preview's
  // _primary.withValues(alpha: mutedAlpha).
  final muted = PdfColor(
    primary.red,
    primary.green,
    primary.blue,
    InvoiceLayout.mutedAlpha,
  ).flatten(background: bg);

  // Only two font files exist (regular [font], SemiBold [bold]), so the
  // preview's w700 labels map to [bold] and its w400 values to [font].
  final labelStyle = pw.TextStyle(
    font: bold,
    color: primary,
    fontSize: _p(InvoiceLayout.fontLabel),
  );
  final valueStyle = pw.TextStyle(
    font: font,
    color: text,
    fontSize: _p(InvoiceLayout.fontValue),
  );

  final sym = currencySymbol(doc.currency);
  String moneyNum(double a) => a.toStringAsFixed(2);

  pw.Widget field(String label, String? value) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('$label:', style: labelStyle),
      pw.SizedBox(height: _p(InvoiceLayout.fieldValueGap)),
      pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.symmetric(
          horizontal: _p(InvoiceLayout.fieldPaddingH),
          vertical: _p(InvoiceLayout.fieldPaddingV),
        ),
        decoration: pw.BoxDecoration(
          color: surface,
          borderRadius: pw.BorderRadius.circular(_p(InvoiceLayout.fieldRadius)),
        ),
        child: pw.Text(
          value == null || value.isEmpty ? '—' : value,
          style: valueStyle,
        ),
      ),
    ],
  );

  final rowDecoration = pw.BoxDecoration(
    color: surface,
    borderRadius: pw.BorderRadius.circular(_p(InvoiceLayout.fieldRadius)),
  );

  // Single-line text — content for a cell box or a bare label.
  pw.Widget txt(String s, {bool right = false, pw.TextStyle? style}) => pw.Text(
    s,
    maxLines: 1,
    textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
    style: style ?? valueStyle,
  );

  // Currency symbol left-aligned, number right-aligned, within a cell box.
  pw.Widget splitRow(String left, String right, {pw.TextStyle? style}) => pw.Row(
    children: [
      pw.Text(left, style: style ?? valueStyle),
      pw.Spacer(),
      pw.Text(right, style: style ?? valueStyle),
    ],
  );

  // A surface box spanning [flex] columns — its fill + padding draws the
  // column divisions once boxes are separated by gutters.
  pw.Widget boxCell(int flex, pw.Widget child) => pw.Expanded(
    flex: flex,
    child: pw.Container(
      padding: pw.EdgeInsets.symmetric(
        horizontal: _p(InvoiceLayout.rowPaddingH),
        vertical: _p(InvoiceLayout.rowPaddingV),
      ),
      decoration: rowDecoration,
      child: child,
    ),
  );

  // Header label, aligned to the column's surface edge (no interior padding):
  // ITEM flush-left, the rest flush-right, matching the box outlines beneath.
  pw.Widget headCell(String s, int flex, {bool right = false}) => pw.Expanded(
    flex: flex,
    child: txt(s, right: right, style: labelStyle),
  );

  final gutter = pw.SizedBox(width: _p(InvoiceLayout.gridGutter));
  const labelSpan =
      InvoiceLayout.colItem + InvoiceLayout.colDate + InvoiceLayout.colRate;

  final doc0 = pw.Document();
  doc0.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(_p(InvoiceLayout.pageMargin)),
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: bg),
        ),
      ),
      build: (context) => [
        // ── Masthead: business details at the left edge, logo at the right ──
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    doc.businessName,
                    style: pw.TextStyle(
                      font: bold,
                      color: primary,
                      fontSize: _p(InvoiceLayout.fontPaymentsHeading),
                    ),
                  ),
                  pw.SizedBox(height: _p(2)),
                  // Contact line: bold "e." / "t." / "w." prefixes, regular values.
                  pw.RichText(
                    text: pw.TextSpan(
                      style: pw.TextStyle(
                        font: font,
                        color: muted,
                        fontSize: _p(InvoiceLayout.fontValue),
                      ),
                      children: [
                        for (final (i, entry) in <(String, String)>[
                          if (doc.senderEmail != null) ('e.', doc.senderEmail!),
                          if (doc.senderPhone != null) ('t.', doc.senderPhone!),
                          if (doc.senderWebsite != null) ('w.', doc.senderWebsite!),
                        ].indexed) ...[
                          if (i > 0) const pw.TextSpan(text: '    '),
                          pw.TextSpan(text: entry.$1, style: pw.TextStyle(font: bold)),
                          pw.TextSpan(text: ' ${entry.$2}'),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: _p(InvoiceLayout.sectionGap)),
            pw.Image(pw.MemoryImage(logoBytes), height: _p(InvoiceLayout.logoHeight)),
          ],
        ),
        pw.SizedBox(height: _p(InvoiceLayout.sectionGap)),

        // ── ATT / RE / date / invoice # ──
        pw.Text('ATT:', style: labelStyle),
        pw.Text(
          doc.attention ?? doc.organisation,
          style: pw.TextStyle(
            font: bold,
            color: primary,
            fontSize: _p(InvoiceLayout.fontHeadline),
          ),
        ),
        pw.SizedBox(height: _p(InvoiceLayout.headlineGap)),
        pw.Text('RE:', style: labelStyle),
        pw.Text(
          doc.reference,
          style: pw.TextStyle(
            font: bold,
            color: primary,
            fontSize: _p(InvoiceLayout.fontHeadline),
          ),
        ),
        pw.SizedBox(height: _p(InvoiceLayout.headlineGap)),
        pw.Text(
          _isoDate(doc.issueDate),
          style: pw.TextStyle(
            font: font,
            color: primary,
            fontSize: _p(InvoiceLayout.fontLabel),
          ),
        ),
        if (doc.invoiceNumber != null)
          pw.Text(
            doc.invoiceNumber!,
            style: pw.TextStyle(
              font: bold,
              color: primary,
              fontSize: _p(InvoiceLayout.fontInvoiceNumber),
            ),
          ),
        pw.SizedBox(height: _p(InvoiceLayout.partyBlockGap)),

        // ── Recipient grid ──
        pw.Row(
          children: [
            pw.Expanded(child: field('TO', doc.recipientContact)),
            pw.SizedBox(width: _p(InvoiceLayout.gridGutter)),
            pw.Expanded(child: field('EMAIL', doc.recipientEmail)),
          ],
        ),
        pw.SizedBox(height: _p(InvoiceLayout.totalsGap)),
        pw.Row(
          children: [
            pw.Expanded(child: field('ORGANISATION', doc.organisation)),
            pw.SizedBox(width: _p(InvoiceLayout.gridGutter)),
            pw.Expanded(child: field('PHONE', doc.recipientPhone)),
          ],
        ),
        pw.SizedBox(height: _p(InvoiceLayout.detailsBlockGap)),

        // ── Details heading ──
        pw.Text(
          'Details',
          style: pw.TextStyle(
            font: bold,
            color: primary,
            fontSize: _p(InvoiceLayout.fontDetailsHeading),
          ),
        ),
        pw.SizedBox(height: _p(InvoiceLayout.detailsHeadingGap)),
        pw.Row(
          children: [
            headCell('ITEM', InvoiceLayout.colItem),
            gutter,
            headCell('DATE', InvoiceLayout.colDate, right: true),
            gutter,
            headCell('RATE (${doc.currency})', InvoiceLayout.colRate, right: true),
            gutter,
            headCell('TIME (HRS)', InvoiceLayout.colTime, right: true),
            gutter,
            headCell('TOTAL', InvoiceLayout.colTotal, right: true),
          ],
        ),
        pw.SizedBox(height: _p(InvoiceLayout.tableHeaderGap)),

        // ── Line rows: one surface box per column, divided by gutters ──
        for (final l in doc.lines)
          pw.Container(
            margin: pw.EdgeInsets.only(
              bottom: _p(InvoiceLayout.rowMarginBottom),
            ),
            child: pw.Row(
              children: [
                boxCell(InvoiceLayout.colItem, txt(l.item)),
                gutter,
                boxCell(InvoiceLayout.colDate, txt(_isoDate(l.date), right: true)),
                gutter,
                boxCell(InvoiceLayout.colRate, splitRow(sym, moneyNum(l.rate))),
                gutter,
                boxCell(
                  InvoiceLayout.colTime,
                  txt(Duration(seconds: l.seconds).hms, right: true),
                ),
                gutter,
                boxCell(InvoiceLayout.colTotal, splitRow(sym, moneyNum(l.amount))),
              ],
            ),
          ),
        pw.SizedBox(height: _p(InvoiceLayout.totalsGap)),

        // ── Totals — bare right-aligned label + a box spanning the last
        //    two columns, mirroring invoice_preview.dart. ──
        pw.Container(
          margin: pw.EdgeInsets.only(bottom: _p(InvoiceLayout.rowMarginBottom)),
          child: pw.Row(
            children: [
              // Two leading gutters reproduce the ITEM|DATE and DATE|RATE gaps
              // folded into the label span, giving four gutters total so the
              // value boxes align exactly with the line-item columns above.
              gutter,
              gutter,
              pw.Expanded(
                flex: labelSpan,
                child: txt('TOTAL:', right: true, style: labelStyle),
              ),
              gutter,
              boxCell(InvoiceLayout.colTime, txt(doc.totalTime.hms, right: true)),
              gutter,
              boxCell(InvoiceLayout.colTotal, splitRow(sym, moneyNum(doc.subtotal))),
            ],
          ),
        ),
        if (doc.tax != null)
          pw.Container(
            margin: pw.EdgeInsets.only(bottom: _p(InvoiceLayout.rowMarginBottom)),
            child: pw.Row(
              children: [
                gutter,
                gutter,
                pw.Expanded(
                  flex: labelSpan,
                  child: txt(
                    '${doc.tax!.label} (${doc.tax!.rate}%):',
                    right: true,
                    style: labelStyle,
                  ),
                ),
                gutter,
                pw.Spacer(flex: InvoiceLayout.colTime),
                gutter,
                boxCell(InvoiceLayout.colTotal, splitRow(sym, moneyNum(doc.tax!.amount))),
              ],
            ),
          ),
        pw.SizedBox(height: _p(InvoiceLayout.amountDueGap)),

        // AMOUNT DUE: label fills the leftover width; the value box takes an
        // exact width so it spans the TIME + TOTAL columns (plus the gutter
        // between them), aligning with those columns exactly.
        pw.Row(
          children: [
            pw.Expanded(
              child: txt('AMOUNT DUE:', right: true, style: labelStyle),
            ),
            gutter,
            pw.Container(
              width: _p(InvoiceLayout.totalsValueWidth),
              padding: pw.EdgeInsets.symmetric(
                horizontal: _p(InvoiceLayout.rowPaddingH),
                vertical: _p(InvoiceLayout.rowPaddingV),
              ),
              decoration: rowDecoration,
              child: pw.Row(
                children: [
                  pw.Text(
                    '$sym ${moneyNum(doc.amountDue)}',
                    style: pw.TextStyle(
                      font: bold,
                      color: text,
                      fontSize: _p(InvoiceLayout.fontAmountDue),
                    ),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    doc.currency,
                    style: pw.TextStyle(
                      font: bold,
                      color: text,
                      fontSize: _p(InvoiceLayout.fontLabel),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: _p(InvoiceLayout.sectionGap)),

        // ── Payments ──
        pw.Text(
          'Please make payments to:',
          style: pw.TextStyle(
            font: bold,
            color: primary,
            fontSize: _p(InvoiceLayout.fontPaymentsHeading),
          ),
        ),
        pw.SizedBox(height: _p(InvoiceLayout.paymentsHeadingGap)),
        if (doc.paymentLink != null) ...[
          field('Link', doc.paymentLink),
          pw.SizedBox(height: _p(InvoiceLayout.paymentsFieldGap)),
        ],
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: field('NAME', doc.payeeName)),
            pw.SizedBox(width: _p(InvoiceLayout.gridGutter)),
            pw.Expanded(child: field('ACN/ABN', doc.senderAbn)),
            pw.SizedBox(width: _p(InvoiceLayout.gridGutter)),
            pw.Expanded(child: field('SWIFT/BIC', doc.swift)),
            pw.SizedBox(width: _p(InvoiceLayout.gridGutter)),
            pw.Expanded(child: field('BANK', doc.bankName)),
          ],
        ),
      ],
    ),
  );
  return doc0.save();
}
