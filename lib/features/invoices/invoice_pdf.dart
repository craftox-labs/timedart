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
  // Mona Sans is a variable font whose wght axis defaults to 200 (ExtraLight),
  // and the pdf package can't shift a variable axis — it renders one static
  // instance per file. So the three preview weights (value w400, label w500,
  // bold w600 in InvoiceLayout) are shipped as pre-instanced static ttfs and
  // mapped here one-to-one. Flutter's preview, by contrast, reads the single
  // variable font and interpolates the wght axis from the fontWeight directly.
  final font = pw.Font.ttf(
    await rootBundle.load('assets/fonts/MonaSans-Regular.ttf'),
  ); // w400 — values
  final medium = pw.Font.ttf(
    await rootBundle.load('assets/fonts/MonaSans-Medium.ttf'),
  ); // w500 — labels (fontWeightLabel)
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/MonaSans-SemiBold.ttf'),
  ); // w600 — headings (fontWeightBold)

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

  // The masthead logo: the profile's own logo, else the fallback the document
  // asks for — the timedart mark (default profile), a neutral "[Logo]" box
  // (template previews), or nothing (null → a real logo-less invoice). Built
  // here (async can load the asset) so the sync page builder just drops it in.
  // Mirrors the preview's choice in invoice_preview.dart.
  final pw.Widget? logoWidget;
  if (doc.logo != null) {
    logoWidget = pw.Image(
      pw.MemoryImage(doc.logo!),
      height: _p(InvoiceLayout.logoHeight),
    );
  } else {
    switch (doc.logoFallback) {
      case LogoFallback.brand:
        final bytes = (await rootBundle.load(
          'assets/logo/timedart_logo_horizontal.png',
        )).buffer.asUint8List();
        logoWidget = pw.Image(
          pw.MemoryImage(bytes),
          height: _p(InvoiceLayout.logoHeight),
        );
      case LogoFallback.placeholder:
        logoWidget = pw.Container(
          width: _p(InvoiceLayout.logoPlaceholderWidth),
          height: _p(InvoiceLayout.logoHeight),
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: muted),
            borderRadius: pw.BorderRadius.circular(
              _p(InvoiceLayout.logoPlaceholderRadius),
            ),
          ),
          child: pw.Text(
            'Logo',
            style: pw.TextStyle(
              font: medium,
              color: muted,
              fontSize: _p(InvoiceLayout.fontValue),
            ),
          ),
        );
      case LogoFallback.none:
        logoWidget = null;
    }
  }

  // Small-caps labels (ATT:/RE:/field + table-header labels): [fontWeightLabel]
  // (w500) → the [medium] instance.
  final labelStyle = pw.TextStyle(
    font: medium,
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

  bool present(String? s) => s != null && s.trim().isNotEmpty;

  // One row of payment fields, padded with empty cells so column widths stay
  // constant across rows. Mirrors invoice_preview.dart's _paymentRow.
  const payColumns = 3;
  pw.Widget paymentRow(List<(String, String)> row) => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (var c = 0; c < payColumns; c++) ...[
        if (c > 0) pw.SizedBox(width: _p(InvoiceLayout.gridGutter)),
        pw.Expanded(
          child: c < row.length ? field(row[c].$1, row[c].$2) : pw.SizedBox(),
        ),
      ],
    ],
  );

  final paymentFields = doc.paymentFields;
  final paymentRows = <List<(String, String)>>[
    for (var i = 0; i < paymentFields.length; i += payColumns)
      paymentFields.sublist(
        i,
        (i + payColumns).clamp(0, paymentFields.length),
      ),
  ];

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
                  if (present(doc.senderAddress)) ...[
                    pw.SizedBox(
                      height: _p(InvoiceLayout.mastheadContactGap),
                    ),
                    pw.Text(
                      doc.senderAddress!.trim(),
                      style: pw.TextStyle(
                        font: font,
                        color: muted,
                        fontSize: _p(InvoiceLayout.fontValue),
                      ),
                    ),
                  ],
                  pw.SizedBox(height: _p(InvoiceLayout.mastheadContactGap)),
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
                          pw.TextSpan(text: entry.$1, style: pw.TextStyle(font: medium, color: primary)),
                          pw.TextSpan(text: ' ${entry.$2}'),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (logoWidget != null)
              pw.SizedBox(width: _p(InvoiceLayout.sectionGap)),
            ?logoWidget,
          ],
        ),
        pw.SizedBox(height: _p(InvoiceLayout.sectionGap)),

        // ── Title (Tax Invoice / Invoice) ──
        pw.Text(
          doc.title.toUpperCase(),
          style: pw.TextStyle(
            font: bold,
            color: primary,
            fontSize: _p(InvoiceLayout.fontPaymentsHeading),
          ),
        ),
        pw.SizedBox(height: _p(InvoiceLayout.headlineGap)),

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
        // Buyer address + tax number — shown only when present. Mirrors
        // invoice_preview.dart's recipient grid.
        if (doc.recipientAddress != null || doc.recipientAbn != null) ...[
          pw.SizedBox(height: _p(InvoiceLayout.totalsGap)),
          pw.Row(
            children: [
              pw.Expanded(
                child: doc.recipientAddress != null
                    ? field('ADDRESS', doc.recipientAddress)
                    : pw.SizedBox(),
              ),
              pw.SizedBox(width: _p(InvoiceLayout.gridGutter)),
              pw.Expanded(
                child: doc.recipientAbn != null
                    ? field(doc.recipientAbnLabel, doc.recipientAbn)
                    : pw.SizedBox(),
              ),
            ],
          ),
        ],
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
                      font: medium,
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

        // ── Payments ── (omitted entirely when there's nothing to show)
        if (paymentRows.isNotEmpty || present(doc.paymentLink)) ...[
          pw.Text(
            'Please make payments to:',
            style: pw.TextStyle(
              font: bold,
              color: primary,
              fontSize: _p(InvoiceLayout.fontPaymentsHeading),
            ),
          ),
          pw.SizedBox(height: _p(InvoiceLayout.paymentsHeadingGap)),
          if (present(doc.paymentLink)) ...[
            field('Link', doc.paymentLink),
            pw.SizedBox(height: _p(InvoiceLayout.paymentsFieldGap)),
          ],
          for (final (i, row) in paymentRows.indexed) ...[
            if (i > 0) pw.SizedBox(height: _p(InvoiceLayout.paymentsFieldGap)),
            paymentRow(row),
          ],
          if (doc.region.paymentNote != null) ...[
            pw.SizedBox(height: _p(InvoiceLayout.paymentsFieldGap)),
            pw.Text(
              doc.region.paymentNote!,
              style: pw.TextStyle(
                font: font,
                color: muted,
                fontSize: _p(InvoiceLayout.fontValue),
              ),
            ),
          ],
        ],
      ],
    ),
  );
  return doc0.save();
}
