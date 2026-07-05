import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:time_tracker/constants/format.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/invoices/invoice_document.dart';

// Renders an [InvoiceDocument] into a branded PDF using an [InvoiceTemplate]
// (colours + optional logo). Presentational: it reads resolved values from the
// document and applies the template — no arithmetic here. Dark, brand-coloured,
// modelled on the reference invoice (PRD #79).

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

Future<Uint8List> buildBrandedInvoicePdf({
  required InvoiceDocument doc,
  required InvoiceTemplate template,
}) async {
  final fontData = await rootBundle.load(
    'assets/fonts/Urbanist-VariableFont_wght.ttf',
  );
  // Urbanist is a variable font; the pdf package embeds a single instance, so
  // `bold` reuses it (weight won't be heavier — a static bold ttf could be
  // bundled later if needed). Hierarchy leans on size/colour instead.
  final font = pw.Font.ttf(fontData);

  // User logo (template.logo) wins; fall back to the bundled timedart mark so
  // the default template shows branding before a logo is uploaded.
  final logoBytes =
      template.logo ??
      (await rootBundle.load('assets/logo/timedart_logo_horizontal.png'))
          .buffer
          .asUint8List();

  final bg = PdfColor.fromInt(template.colorBackground);
  final surface = PdfColor.fromInt(template.colorSurface);
  final primary = PdfColor.fromInt(template.colorPrimary);
  final text = PdfColor.fromInt(template.colorText);
  final muted = PdfColor.fromInt(template.colorText).flatten(background: bg);

  final labelStyle = pw.TextStyle(color: primary, fontSize: 8);
  final valueStyle = pw.TextStyle(
    color: primary,
    fontSize: 11,
    fontWeight: pw.FontWeight.bold,
  );

  String money(double a) => formatCurrency(a, doc.currency);

  // A "label above a filled value box" cell, mirroring the reference.
  pw.Widget field(String label, String? value) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('$label:', style: labelStyle),
      pw.SizedBox(height: 2),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: pw.BoxDecoration(
          color: surface,
          borderRadius: pw.BorderRadius.circular(AppTokens.radiusSm),
        ),
        child: pw.Text(
          value == null || value.isEmpty ? '—' : value,
          style: valueStyle,
        ),
      ),
    ],
  );

  // One column of the details grid. The same flex weights (3/2/2/2/2) are used
  // by the header, the line rows, and the totals so TIME and TOTAL line up top
  // to bottom.
  pw.Widget cell(String s, int flex, {bool right = false, pw.TextStyle? style}) =>
      pw.Expanded(
        flex: flex,
        child: pw.Text(
          s,
          maxLines: 1,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style:
              style ??
              pw.TextStyle(
                color: primary,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
        ),
      );

  final doc0 = pw.Document();
  doc0.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      build: (context) => pw.Container(
        color: bg,
        padding: const pw.EdgeInsets.all(36),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ── Masthead: logo/business right, contact under it ──
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Image(pw.MemoryImage(logoBytes), height: 28),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      [
                        if (doc.senderEmail != null) 'e. ${doc.senderEmail}',
                        if (doc.senderPhone != null) 't. ${doc.senderPhone}',
                      ].join('    '),
                      style: pw.TextStyle(color: muted, fontSize: 8),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // ── ATT / RE / date / invoice # ──
            pw.Text('ATT:', style: labelStyle),
            pw.Text(
              doc.attention ?? doc.organisation,
              style: pw.TextStyle(
                color: primary,
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text('RE:', style: labelStyle),
            pw.Text(
              doc.reference,
              style: pw.TextStyle(
                color: primary,
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(_isoDate(doc.issueDate), style: pw.TextStyle(color: muted, fontSize: 8)),
            if (doc.invoiceNumber != null)
              pw.Text(
                'Invoice #${doc.invoiceNumber}',
                style: pw.TextStyle(
                  color: text,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            pw.SizedBox(height: 16),

            // ── Recipient grid ──
            pw.Row(
              children: [
                pw.Expanded(child: field('TO', doc.recipientContact)),
                pw.SizedBox(width: 8),
                pw.Expanded(child: field('EMAIL', doc.recipientEmail)),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              children: [
                pw.Expanded(child: field('ORGANISATION', doc.organisation)),
                pw.SizedBox(width: 8),
                pw.Expanded(child: field('PHONE', doc.recipientPhone)),
              ],
            ),
            pw.SizedBox(height: 20),

            // ── Details ──
            pw.Text(
              'Details',
              style: pw.TextStyle(
                color: primary,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            // Header — same horizontal inset as the line rows so columns align.
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12),
              child: pw.Row(
                children: [
                  cell('ITEM', 3, style: labelStyle),
                  cell('DATE', 2, style: labelStyle),
                  cell('RATE (${doc.currency})', 2, right: true, style: labelStyle),
                  cell('TIME (HRS)', 2, right: true, style: labelStyle),
                  cell('TOTAL', 2, right: true, style: labelStyle),
                ],
              ),
            ),
            pw.SizedBox(height: 4),
            // Line rows — borderless rounded surfaces, padded for the corners.
            for (final l in doc.lines)
              pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 3),
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: pw.BoxDecoration(
                  color: surface,
                  borderRadius: pw.BorderRadius.circular(AppTokens.radiusSm),
                ),
                child: pw.Row(
                  children: [
                    cell(l.item, 3),
                    cell(_isoDate(l.date), 2),
                    cell(money(l.rate), 2, right: true),
                    cell(Duration(seconds: l.seconds).hms, 2, right: true),
                    cell(money(l.amount), 2, right: true),
                  ],
                ),
              ),
            pw.SizedBox(height: 6),

            // ── Totals — TIME under TIME, amount under TOTAL (same columns) ──
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: pw.Row(
                children: [
                  cell('TOTAL:', 7, right: true, style: labelStyle),
                  cell(doc.totalTime.hms, 2, right: true, style: valueStyle),
                  cell(money(doc.subtotal), 2, right: true, style: valueStyle),
                ],
              ),
            ),
            if (doc.tax != null)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: pw.Row(
                  children: [
                    cell(
                      '${doc.tax!.label} (${doc.tax!.rate}%):',
                      9,
                      right: true,
                      style: labelStyle,
                    ),
                    cell(money(doc.tax!.amount), 2, right: true, style: valueStyle),
                  ],
                ),
              ),
            pw.SizedBox(height: 4),
            // AMOUNT DUE — emphasised, right edge aligned with the TOTAL column.
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text('AMOUNT DUE:  ', style: labelStyle),
                  pw.Text(
                    '${money(doc.amountDue)} ${doc.currency}',
                    style: pw.TextStyle(
                      color: primary,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            pw.Spacer(),

            // ── Payments ──
            pw.Text(
              'Please make payments to:',
              style: pw.TextStyle(
                color: primary,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            if (doc.paymentLink != null)
              field('Link', doc.paymentLink)
            else
              pw.SizedBox(),
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: field('NAME', doc.payeeName)),
                pw.SizedBox(width: 8),
                pw.Expanded(child: field('ACN/ABN', doc.senderAbn)),
                pw.SizedBox(width: 8),
                pw.Expanded(child: field('SWIFT/BIC', doc.swift)),
                pw.SizedBox(width: 8),
                pw.Expanded(child: field('BANK', doc.bankName)),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return doc0.save();
}
