import 'package:flutter/material.dart';
import 'package:time_tracker/constants/format.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/invoices/invoice_document.dart';
import 'package:time_tracker/features/invoices/invoice_layout.dart';

/// A bordered frame that hugs an invoice preview tightly — the border traces
/// the sheet's true edges so it reads as the actual page boundary rather than
/// an arbitrary panel outline. Wrapped in [Center] so a stretching ancestor
/// can't force it wider than its child. The child is clipped to a radius inset
/// by the border width so corners meet cleanly.
Widget brandingPreviewFrame({required Widget child}) => Center(
  child: Container(
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFF2A2A2A)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: child,
    ),
  ),
);

/// Standard print page proportions (height ÷ width). A4 is the default; Letter
/// is offered for US output. A page-size picker is a later setting (#99).
enum InvoicePageSize {
  a4(297 / 210),
  letter(279 / 216);

  const InvoicePageSize(this.ratio);
  final double ratio; // height / width
}

/// The invoice preview laid out as a page — a sheet at the chosen print
/// proportions. Fills [brandingPreviewFrame] edge to edge. Scrolls vertically
/// inside its parent when the invoice runs longer than one page height.
/// Pass [scrollable] = false when embedding inside an outer scroll view.
Widget invoicePreviewPage({
  required InvoiceDocument doc,
  required InvoiceTemplate template,
  InvoicePageSize size = InvoicePageSize.a4,
  bool scrollable = true,
}) {
  return LayoutBuilder(
    builder: (context, c) {
      const designWidth = InvoiceLayout.designWidth;
      final sheet = Container(
        width: designWidth,
        constraints: BoxConstraints(minHeight: designWidth * size.ratio),
        color: Color(template.colorBackground),
        child: InvoicePreview(doc: doc, template: template),
      );
      final page = c.maxWidth >= designWidth
          ? sheet
          : FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              child: sheet,
            );
      return scrollable ? SingleChildScrollView(child: page) : page;
    },
  );
}

/// On-screen WYSIWYG preview of an [InvoiceDocument] rendered with an
/// [InvoiceTemplate]. Mirrors invoice_pdf.dart so what you see matches
/// the export. Both renderers read from [InvoiceLayout] — edit that file
/// to restyle both outputs simultaneously.
class InvoicePreview extends StatelessWidget {
  final InvoiceDocument doc;
  final InvoiceTemplate template;
  const InvoicePreview({super.key, required this.doc, required this.template});

  Color get _bg => Color(template.colorBackground);
  Color get _surface => Color(template.colorSurface);
  Color get _primary => Color(template.colorPrimary);
  Color get _text => Color(template.colorText); // text on surface (field box values)
  Color get _muted => _primary.withValues(alpha: 0.55); // secondary text on background

  String _money(double a) => formatCurrency(a, doc.currency);
  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  TextStyle get _label => TextStyle(
    color: _primary,
    fontSize: InvoiceLayout.fontLabel,
    fontWeight: InvoiceLayout.fontWeightLabel,
  );
  TextStyle get _value => TextStyle(
    color: _text,
    fontSize: InvoiceLayout.fontValue,
    fontWeight: InvoiceLayout.fontWeightValue,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      padding: const EdgeInsets.all(InvoiceLayout.pageMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _masthead(),
          const SizedBox(height: InvoiceLayout.sectionGap),
          _party(),
          const SizedBox(height: InvoiceLayout.partyBlockGap),
          _recipientGrid(),
          const SizedBox(height: InvoiceLayout.detailsBlockGap),
          Text(
            'Details',
            style: TextStyle(
              color: _primary,
              fontSize: InvoiceLayout.fontDetailsHeading,
              fontWeight: InvoiceLayout.fontWeightBold,
            ),
          ),
          const SizedBox(height: InvoiceLayout.detailsHeadingGap),
          _table(),
          const SizedBox(height: InvoiceLayout.totalsGap),
          _totals(),
          const SizedBox(height: InvoiceLayout.sectionGap),
          _payments(),
        ],
      ),
    );
  }

  Widget _masthead() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Spacer(),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          template.logo != null
              ? Image.memory(template.logo!, height: InvoiceLayout.logoHeight)
              : Image.asset(
                  'assets/logo/timedart_logo_horizontal.png',
                  height: InvoiceLayout.logoHeight,
                ),
          const SizedBox(height: InvoiceLayout.fieldValueGap),
          Text(
            [
              if (doc.senderEmail != null) 'e. ${doc.senderEmail}',
              if (doc.senderPhone != null) 't. ${doc.senderPhone}',
            ].join('    '),
            style: TextStyle(
              color: _muted,
              fontSize: InvoiceLayout.fontLabel,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _party() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('ATT:', style: _label),
      Text(
        doc.attention ?? doc.organisation,
        style: TextStyle(
          color: _primary,
          fontSize: InvoiceLayout.fontHeadline,
          fontWeight: InvoiceLayout.fontWeightBold,
        ),
      ),
      const SizedBox(height: InvoiceLayout.headlineGap),
      Text('RE:', style: _label),
      Text(
        doc.reference,
        style: TextStyle(
          color: _primary,
          fontSize: InvoiceLayout.fontHeadline,
          fontWeight: InvoiceLayout.fontWeightBold,
        ),
      ),
      const SizedBox(height: InvoiceLayout.headlineGap),
      Text(
        _iso(doc.issueDate),
        style: TextStyle(color: _primary, fontSize: InvoiceLayout.fontLabel),
      ),
      if (doc.invoiceNumber != null)
        Text(
          doc.invoiceNumber!,
          style: TextStyle(
            color: _primary,
            fontSize: InvoiceLayout.fontInvoiceNumber,
            fontWeight: InvoiceLayout.fontWeightBold,
          ),
        ),
    ],
  );

  Widget _recipientGrid() => Column(
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _field('TO', doc.recipientContact)),
          const SizedBox(width: InvoiceLayout.gridGutter),
          Expanded(child: _field('EMAIL', doc.recipientEmail)),
        ],
      ),
      const SizedBox(height: InvoiceLayout.totalsGap),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _field('ORGANISATION', doc.organisation)),
          const SizedBox(width: InvoiceLayout.gridGutter),
          Expanded(child: _field('PHONE', doc.recipientPhone)),
        ],
      ),
    ],
  );

  Widget _field(String label, String? value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label:', style: _label),
      const SizedBox(height: InvoiceLayout.fieldValueGap),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: InvoiceLayout.fieldPaddingH,
          vertical: InvoiceLayout.fieldPaddingV,
        ),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(InvoiceLayout.fieldRadius),
        ),
        child: Text(
          value == null || value.isEmpty ? '—' : value,
          style: _value,
        ),
      ),
    ],
  );

  Widget _cell(String s, int flex, {bool right = false, TextStyle? style}) =>
      Expanded(
        flex: flex,
        child: Text(
          s,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: right ? TextAlign.right : TextAlign.left,
          style: style ?? _value,
        ),
      );

  Widget _table() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: InvoiceLayout.rowPaddingH,
        ),
        child: Row(
          children: [
            _cell('ITEM', InvoiceLayout.colItem, style: _label),
            _cell('DATE', InvoiceLayout.colDate, style: _label),
            _cell('RATE (${doc.currency})', InvoiceLayout.colRate, right: true, style: _label),
            _cell('TIME (HRS)', InvoiceLayout.colTime, right: true, style: _label),
            _cell('TOTAL', InvoiceLayout.colTotal, right: true, style: _label),
          ],
        ),
      ),
      const SizedBox(height: InvoiceLayout.tableHeaderGap),
      for (final l in doc.lines)
        Container(
          margin: const EdgeInsets.only(bottom: InvoiceLayout.rowMarginBottom),
          padding: const EdgeInsets.symmetric(
            horizontal: InvoiceLayout.rowPaddingH,
            vertical: InvoiceLayout.rowPaddingV,
          ),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(InvoiceLayout.fieldRadius),
          ),
          child: Row(
            children: [
              _cell(l.item, InvoiceLayout.colItem),
              _cell(_iso(l.date), InvoiceLayout.colDate),
              _cell(_money(l.rate), InvoiceLayout.colRate, right: true),
              _cell(Duration(seconds: l.seconds).hms, InvoiceLayout.colTime, right: true),
              _cell(_money(l.amount), InvoiceLayout.colTotal, right: true),
            ],
          ),
        ),
    ],
  );

  Widget _totals() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: InvoiceLayout.rowPaddingH,
        ),
        child: Row(
          children: [
            _cell('TOTAL:', InvoiceLayout.colItem + InvoiceLayout.colDate + InvoiceLayout.colRate, right: true, style: _label),
            _cell(doc.totalTime.hms, InvoiceLayout.colTime, right: true, style: _value),
            _cell(_money(doc.subtotal), InvoiceLayout.colTotal, right: true, style: _value),
          ],
        ),
      ),
      if (doc.tax != null)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: InvoiceLayout.rowPaddingH,
            vertical: InvoiceLayout.fieldValueGap,
          ),
          child: Row(
            children: [
              _cell(
                '${doc.tax!.label} (${doc.tax!.rate}%):',
                InvoiceLayout.colItem + InvoiceLayout.colDate + InvoiceLayout.colRate + InvoiceLayout.colTime,
                right: true,
                style: _label,
              ),
              _cell(_money(doc.tax!.amount), InvoiceLayout.colTotal, right: true, style: _value),
            ],
          ),
        ),
      const SizedBox(height: InvoiceLayout.amountDueGap),
      // AMOUNT DUE aligned to the TOTAL column (flex 9 spacer + flex 2 value,
      // matching the 3/2/2/2/2 table grid's last-two-column span).
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: InvoiceLayout.rowPaddingH,
        ),
        child: Row(
          children: [
            _cell('AMOUNT DUE:', InvoiceLayout.colItem + InvoiceLayout.colDate + InvoiceLayout.colRate + InvoiceLayout.colTime, right: true, style: _label),
            _cell(
              '${_money(doc.amountDue)} ${doc.currency}',
              InvoiceLayout.colTotal,
              right: true,
              style: TextStyle(
                color: _primary,
                fontSize: InvoiceLayout.fontAmountDue,
                fontWeight: InvoiceLayout.fontWeightBold,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _payments() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Please make payments to:',
        style: TextStyle(
          color: _primary,
          fontSize: InvoiceLayout.fontPaymentsHeading,
          fontWeight: InvoiceLayout.fontWeightBold,
        ),
      ),
      const SizedBox(height: InvoiceLayout.paymentsHeadingGap),
      if (doc.paymentLink != null) ...[
        _field('Link', doc.paymentLink),
        const SizedBox(height: InvoiceLayout.paymentsFieldGap),
      ],
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _field('NAME', doc.payeeName)),
          const SizedBox(width: InvoiceLayout.gridGutter),
          Expanded(child: _field('ACN/ABN', doc.senderAbn)),
          const SizedBox(width: InvoiceLayout.gridGutter),
          Expanded(child: _field('SWIFT/BIC', doc.swift)),
          const SizedBox(width: InvoiceLayout.gridGutter),
          Expanded(child: _field('BANK', doc.bankName)),
        ],
      ),
    ],
  );
}
