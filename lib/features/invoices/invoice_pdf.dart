import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:time_tracker/constants/format.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/invoices/invoice_document.dart';

// Renders an [InvoiceDocument] into a branded PDF using an [InvoiceTheme]
// (colours + optional logo). Presentational: it reads resolved values from the
// document and applies the theme — no arithmetic here. Dark, brand-coloured,
// modelled on the reference invoice (PRD #79).

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

Future<Uint8List> buildBrandedInvoicePdf({
  required InvoiceDocument doc,
  required InvoiceTheme theme,
}) async {
  final fontData = await rootBundle.load(
    'assets/fonts/Urbanist-VariableFont_wght.ttf',
  );
  // Urbanist is a variable font; the pdf package embeds a single instance, so
  // `bold` reuses it (weight won't be heavier — a static bold ttf could be
  // bundled later if needed). Hierarchy leans on size/colour instead.
  final font = pw.Font.ttf(fontData);

  final bg = PdfColor.fromInt(theme.colorBackground);
  final surface = PdfColor.fromInt(theme.colorSurface);
  final primary = PdfColor.fromInt(theme.colorPrimary);
  final text = PdfColor.fromInt(theme.colorText);
  final muted = PdfColor.fromInt(theme.colorText).flatten(background: bg);

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
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: pw.BoxDecoration(
          color: surface,
          border: pw.Border.all(color: primary, width: 0.5),
        ),
        child: pw.Text(
          value == null || value.isEmpty ? '—' : value,
          style: valueStyle,
        ),
      ),
    ],
  );

  pw.Widget tableCell(String s, {bool header = false, bool right = false}) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(
          s,
          style: header
              ? labelStyle
              : pw.TextStyle(
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
                    if (theme.logo != null)
                      pw.Image(pw.MemoryImage(theme.logo!), height: 28)
                    else
                      pw.Text(
                        doc.businessName,
                        style: pw.TextStyle(
                          color: primary,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
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
            pw.SizedBox(height: 8),
            pw.Table(
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(2),
                4: pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  children: [
                    tableCell('ITEM', header: true),
                    tableCell('DATE', header: true),
                    tableCell('RATE (${doc.currency})', header: true, right: true),
                    tableCell('TIME (HRS)', header: true, right: true),
                    tableCell('TOTAL', header: true, right: true),
                  ],
                ),
                for (final l in doc.lines)
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: surface),
                    children: [
                      tableCell(l.item),
                      tableCell(_isoDate(l.date)),
                      tableCell(money(l.rate), right: true),
                      tableCell(Duration(seconds: l.seconds).hms, right: true),
                      tableCell(money(l.amount), right: true),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 8),

            // ── Totals ──
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text('TOTAL:  ', style: labelStyle),
                pw.Text(doc.totalTime.hms, style: valueStyle),
                pw.SizedBox(width: 16),
                pw.Text(money(doc.subtotal), style: valueStyle),
              ],
            ),
            if (doc.tax != null) ...[
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Text('${doc.tax!.label} (${doc.tax!.rate}%):  ', style: labelStyle),
                  pw.Text(money(doc.tax!.amount), style: valueStyle),
                ],
              ),
            ],
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text('AMOUNT DUE:  ', style: labelStyle),
                pw.Text(
                  '${money(doc.amountDue)} ${doc.currency}',
                  style: pw.TextStyle(
                    color: primary,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
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
