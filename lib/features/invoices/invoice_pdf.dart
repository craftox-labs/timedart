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
  final muted = PdfColor.fromInt(template.colorPrimary).flatten(background: bg); // secondary text on background

  final labelStyle = pw.TextStyle(
    font: font,
    color: primary,
    fontSize: _p(InvoiceLayout.fontLabel),
  );
  final valueStyle = pw.TextStyle(
    font: bold,
    color: text,
    fontSize: _p(InvoiceLayout.fontValue),
  );

  String money(double a) => formatCurrency(a, doc.currency);

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

  // One column in the line-items grid. Flex weights 3/2/2/2/2 — same across
  // header, rows, and totals so columns line up top to bottom.
  pw.Widget cell(
    String s,
    int flex, {
    bool right = false,
    pw.TextStyle? style,
  }) => pw.Expanded(
    flex: flex,
    child: pw.Text(
      s,
      maxLines: 1,
      textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
      style: style ?? valueStyle,
    ),
  );

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
        // ── Masthead: logo right-aligned, contact line below ──
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Image(pw.MemoryImage(logoBytes), height: _p(InvoiceLayout.logoHeight)),
                pw.SizedBox(height: _p(InvoiceLayout.fieldValueGap) * 2),
                pw.Text(
                  [
                    if (doc.senderEmail != null) 'e. ${doc.senderEmail}',
                    if (doc.senderPhone != null) 't. ${doc.senderPhone}',
                  ].join('    '),
                  style: pw.TextStyle(
                    font: font,
                    color: muted,
                    fontSize: _p(InvoiceLayout.fontLabel),
                  ),
                ),
              ],
            ),
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
        pw.Padding(
          padding: pw.EdgeInsets.symmetric(
            horizontal: _p(InvoiceLayout.rowPaddingH),
          ),
          child: pw.Row(
            children: [
              cell('ITEM', InvoiceLayout.colItem, style: labelStyle),
              cell('DATE', InvoiceLayout.colDate, style: labelStyle),
              cell('RATE (${doc.currency})', InvoiceLayout.colRate, right: true, style: labelStyle),
              cell('TIME (HRS)', InvoiceLayout.colTime, right: true, style: labelStyle),
              cell('TOTAL', InvoiceLayout.colTotal, right: true, style: labelStyle),
            ],
          ),
        ),
        pw.SizedBox(height: _p(InvoiceLayout.tableHeaderGap)),

        // ── Line rows ──
        for (final l in doc.lines)
          pw.Container(
            margin: pw.EdgeInsets.only(
              bottom: _p(InvoiceLayout.rowMarginBottom),
            ),
            padding: pw.EdgeInsets.symmetric(
              horizontal: _p(InvoiceLayout.rowPaddingH),
              vertical: _p(InvoiceLayout.rowPaddingV),
            ),
            decoration: pw.BoxDecoration(
              color: surface,
              borderRadius: pw.BorderRadius.circular(
                _p(InvoiceLayout.fieldRadius),
              ),
            ),
            child: pw.Row(
              children: [
                cell(l.item, InvoiceLayout.colItem),
                cell(_isoDate(l.date), InvoiceLayout.colDate),
                cell(money(l.rate), InvoiceLayout.colRate, right: true),
                cell(Duration(seconds: l.seconds).hms, InvoiceLayout.colTime, right: true),
                cell(money(l.amount), InvoiceLayout.colTotal, right: true),
              ],
            ),
          ),
        pw.SizedBox(height: _p(InvoiceLayout.totalsGap)),

        // ── Totals — TIME under TIME col, amount under TOTAL col ──
        pw.Padding(
          padding: pw.EdgeInsets.symmetric(
            horizontal: _p(InvoiceLayout.rowPaddingH),
            vertical: _p(InvoiceLayout.fieldValueGap),
          ),
          child: pw.Row(
            children: [
              cell('TOTAL:', InvoiceLayout.colItem + InvoiceLayout.colDate + InvoiceLayout.colRate, right: true, style: labelStyle),
              cell(doc.totalTime.hms, InvoiceLayout.colTime, right: true, style: valueStyle),
              cell(money(doc.subtotal), InvoiceLayout.colTotal, right: true, style: valueStyle),
            ],
          ),
        ),
        if (doc.tax != null)
          pw.Padding(
            padding: pw.EdgeInsets.symmetric(
              horizontal: _p(InvoiceLayout.rowPaddingH),
              vertical: _p(InvoiceLayout.fieldValueGap),
            ),
            child: pw.Row(
              children: [
                cell(
                  '${doc.tax!.label} (${doc.tax!.rate}%):',
                  InvoiceLayout.colItem + InvoiceLayout.colDate + InvoiceLayout.colRate + InvoiceLayout.colTime,
                  right: true,
                  style: labelStyle,
                ),
                cell(money(doc.tax!.amount), InvoiceLayout.colTotal, right: true, style: valueStyle),
              ],
            ),
          ),
        pw.SizedBox(height: _p(InvoiceLayout.amountDueGap)),

        // AMOUNT DUE — aligned to the TOTAL column (flex 9 spacer + flex 2 value).
        pw.Padding(
          padding: pw.EdgeInsets.symmetric(
            horizontal: _p(InvoiceLayout.rowPaddingH),
            vertical: _p(InvoiceLayout.fieldValueGap),
          ),
          child: pw.Row(
            children: [
              cell('AMOUNT DUE:', InvoiceLayout.colItem + InvoiceLayout.colDate + InvoiceLayout.colRate + InvoiceLayout.colTime, right: true, style: labelStyle),
              cell(
                '${money(doc.amountDue)} ${doc.currency}',
                InvoiceLayout.colTotal,
                right: true,
                style: pw.TextStyle(
                  font: bold,
                  color: primary,
                  fontSize: _p(InvoiceLayout.fontAmountDue),
                ),
              ),
            ],
          ),
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
