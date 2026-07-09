import 'package:flutter/material.dart';
import 'package:time_tracker/constants/format.dart';
import 'package:time_tracker/constants/tokens.dart';
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
      border: Border.all(color: AppTokens.colorBorder),
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppTokens.radiusSm - 1),
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
      // Scale the fixed-width design sheet to fill the available width at any
      // screen size — up as well as down. FittedBox only rescales when given a
      // tight width, so pin the page to the pane width (falling back to the
      // native width if the pane is horizontally unbounded).
      final targetWidth = c.maxWidth.isFinite ? c.maxWidth : designWidth;
      final page = SizedBox(
        width: targetWidth,
        child: FittedBox(
          fit: BoxFit.fitWidth,
          alignment: Alignment.topCenter,
          child: sheet,
        ),
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
  Color get _text =>
      Color(template.colorText); // text on surface (field box values)
  Color get _muted => _primary.withValues(
    alpha: InvoiceLayout.mutedAlpha,
  ); // secondary text on background

  String get _sym => currencySymbol(doc.currency);
  String _moneyNum(double a) => a.toStringAsFixed(2);

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

  // Business details sit at the left edge; the logo anchors the right edge on
  // the same top line. Separating the two gives whatever icon/logo the user
  // supplies its own room rather than stacking text beneath it.
  Widget _masthead() {
    final logo = _logo();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            spacing: InvoiceLayout.mastheadContactGap,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                doc.businessName,
                style: TextStyle(
                  color: _primary,
                  fontSize: InvoiceLayout.fontPaymentsHeading,
                  fontWeight: InvoiceLayout.fontWeightBold,
                ),
              ),
              if (_present(doc.senderAddress))
                Text(
                  doc.senderAddress!.trim(),
                  style: TextStyle(
                    color: _muted,
                    fontSize: InvoiceLayout.fontValue,
                  ),
                ),
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: _muted,
                    fontSize: InvoiceLayout.fontValue,
                  ),
                  children: _contactSpans(),
                ),
              ),
            ],
          ),
        ),
        // No gap or logo at all when there's nothing to show (a real invoice
        // for a logo-less profile).
        if (logo != null) const SizedBox(width: InvoiceLayout.sectionGap),
        ?logo,
      ],
    );
  }

  // The masthead logo: the profile's own logo, else the fallback chosen by the
  // document (timedart mark / placeholder box / nothing → null).
  Widget? _logo() {
    if (doc.logo != null) {
      return Image.memory(doc.logo!, height: InvoiceLayout.logoHeight);
    }
    switch (doc.logoFallback) {
      case LogoFallback.brand:
        return Image.asset(
          'assets/logo/timedart_logo_horizontal.png',
          height: InvoiceLayout.logoHeight,
        );
      case LogoFallback.placeholder:
        return _logoPlaceholder();
      case LogoFallback.none:
        return null;
    }
  }

  // Shown only in template-editor previews: a neutral outlined box so the
  // masthead keeps its shape without borrowing the app's brand mark.
  Widget _logoPlaceholder() => Container(
    width: InvoiceLayout.logoPlaceholderWidth,
    height: InvoiceLayout.logoHeight,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: _muted),
      borderRadius: BorderRadius.circular(InvoiceLayout.logoPlaceholderRadius),
    ),
    child: Text(
      'Logo',
      style: TextStyle(
        color: _muted,
        fontSize: InvoiceLayout.fontValue,
        fontWeight: InvoiceLayout.fontWeightLabel,
      ),
    ),
  );

  // Masthead contact line: bold "e." / "t." / "w." prefixes, regular values,
  // four spaces between entries. Only present fields appear.
  List<InlineSpan> _contactSpans() {
    final prefixStyle = TextStyle(
      fontWeight: InvoiceLayout.fontWeightLabel,
      color: _primary,
    );
    final entries = <(String, String)>[
      if (doc.senderEmail != null) ('e.', doc.senderEmail!),
      if (doc.senderPhone != null) ('t.', doc.senderPhone!),
      if (doc.senderWebsite != null) ('w.', doc.senderWebsite!),
    ];
    return [
      for (final (i, entry) in entries.indexed) ...[
        if (i > 0) const TextSpan(text: '    '),
        TextSpan(text: entry.$1, style: prefixStyle),
        TextSpan(text: ' ${entry.$2}'),
      ],
    ];
  }

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
      // Buyer address + tax number — required on compliant invoices above the
      // local threshold. Shown only when present (unlike the fields above,
      // which keep a '—' placeholder), so a client without them adds no rows.
      if (doc.recipientAddress != null || doc.recipientAbn != null) ...[
        const SizedBox(height: InvoiceLayout.totalsGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: doc.recipientAddress != null
                  ? _field('ADDRESS', doc.recipientAddress)
                  : const SizedBox(),
            ),
            const SizedBox(width: InvoiceLayout.gridGutter),
            Expanded(
              child: doc.recipientAbn != null
                  ? _field('ABN / TAX NO.', doc.recipientAbn)
                  : const SizedBox(),
            ),
          ],
        ),
      ],
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

  // Plain text sized to a single line — content for a cell box or a bare label.
  Widget _txt(String s, {bool right = false, TextStyle? style}) => Text(
    s,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: right ? TextAlign.right : TextAlign.left,
    style: style ?? _value,
  );

  // Currency symbol left-aligned, number right-aligned, within a cell box.
  Widget _splitRow(String left, String right, {TextStyle? style}) => Row(
    children: [
      Text(left, style: style ?? _value),
      const Spacer(),
      Text(right, style: style ?? _value),
    ],
  );

  // A single surface box occupying [flex] columns. Its own fill + padding is
  // what draws the column divisions when boxes are separated by gutters.
  Widget _box({required int flex, required Widget child}) => Expanded(
    flex: flex,
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: InvoiceLayout.rowPaddingH,
        vertical: InvoiceLayout.rowPaddingV,
      ),
      decoration: _rowDecoration,
      child: child,
    ),
  );

  // Header label, aligned to the column's surface edge (no interior padding):
  // ITEM flush-left, the rest flush-right, matching the box outlines beneath.
  Widget _headCell(String s, int flex, {bool right = false}) => Expanded(
    flex: flex,
    child: _txt(s, right: right, style: _label),
  );

  static const _gutter = SizedBox(width: InvoiceLayout.gridGutter);

  Widget _table() => Column(
    children: [
      Row(
        children: [
          _headCell('ITEM', InvoiceLayout.colItem),
          _gutter,
          _headCell('DATE', InvoiceLayout.colDate, right: true),
          _gutter,
          _headCell(
            'RATE (${doc.currency})',
            InvoiceLayout.colRate,
            right: true,
          ),
          _gutter,
          _headCell('TIME (HRS)', InvoiceLayout.colTime, right: true),
          _gutter,
          _headCell('TOTAL', InvoiceLayout.colTotal, right: true),
        ],
      ),
      const SizedBox(height: InvoiceLayout.tableHeaderGap),
      for (final l in doc.lines)
        Padding(
          padding: const EdgeInsets.only(bottom: InvoiceLayout.rowMarginBottom),
          child: Row(
            children: [
              _box(flex: InvoiceLayout.colItem, child: _txt(l.item)),
              _gutter,
              _box(
                flex: InvoiceLayout.colDate,
                child: _txt(_iso(l.date), right: true),
              ),
              _gutter,
              _box(
                flex: InvoiceLayout.colRate,
                child: _splitRow(_sym, _moneyNum(l.rate)),
              ),
              _gutter,
              _box(
                flex: InvoiceLayout.colTime,
                child: _txt(Duration(seconds: l.seconds).hms, right: true),
              ),
              _gutter,
              _box(
                flex: InvoiceLayout.colTotal,
                child: _splitRow(_sym, _moneyNum(l.amount)),
              ),
            ],
          ),
        ),
    ],
  );

  BoxDecoration get _rowDecoration => BoxDecoration(
    color: _surface,
    borderRadius: BorderRadius.circular(InvoiceLayout.fieldRadius),
  );

  // Flex of the leftover label area (first three columns) and the value box
  // (last two columns). Totals labels sit bare on the background; only the
  // figures get a surface box, spanning those last two columns.
  static const _labelSpan =
      InvoiceLayout.colItem + InvoiceLayout.colDate + InvoiceLayout.colRate;

  // One totals line: a right-aligned bare label over the first three columns,
  // then caller-supplied cells over the last two (TIME + TOTAL). The two
  // leading gutters reproduce the ITEM|DATE and DATE|RATE gaps folded into the
  // merged label span; with the trailing gutter that makes four gutters total,
  // matching the line rows so every value box lands under its column exactly.
  Widget _totalsRow(String label, List<Widget> trailing) => Padding(
    padding: const EdgeInsets.only(bottom: InvoiceLayout.rowMarginBottom),
    child: Row(
      children: [
        _gutter,
        _gutter,
        Expanded(
          flex: _labelSpan,
          child: _txt(label, right: true, style: _label),
        ),
        _gutter,
        ...trailing,
      ],
    ),
  );

  Widget _totals() => Column(
    children: [
      // TOTAL: time and amount each in their own box, aligned to the columns.
      _totalsRow('TOTAL:', [
        _box(
          flex: InvoiceLayout.colTime,
          child: _txt(doc.totalTime.hms, right: true),
        ),
        _gutter,
        _box(
          flex: InvoiceLayout.colTotal,
          child: _splitRow(_sym, _moneyNum(doc.subtotal)),
        ),
      ]),
      if (doc.tax != null)
        _totalsRow('${doc.tax!.label} (${doc.tax!.rate}%):', [
          const Spacer(flex: InvoiceLayout.colTime),
          _gutter,
          _box(
            flex: InvoiceLayout.colTotal,
            child: _splitRow(_sym, _moneyNum(doc.tax!.amount)),
          ),
        ]),
      const SizedBox(height: InvoiceLayout.amountDueGap),
      // AMOUNT DUE: the label fills the leftover width; the value box takes an
      // exact pixel width so it spans the TIME + TOTAL columns (plus the gutter
      // between them) and lines up with those columns exactly — a flex slot
      // can't, since it can't reclaim that internal gutter.
      Padding(
        padding: const EdgeInsets.only(bottom: InvoiceLayout.rowMarginBottom),
        child: Row(
          children: [
            Expanded(child: _txt('AMOUNT DUE:', right: true, style: _label)),
            _gutter,
            Container(
              width: InvoiceLayout.totalsValueWidth,
              padding: const EdgeInsets.symmetric(
                horizontal: InvoiceLayout.rowPaddingH,
                vertical: InvoiceLayout.rowPaddingV,
              ),
              decoration: _rowDecoration,
              child: Row(
                children: [
                  Text(
                    '$_sym ${_moneyNum(doc.amountDue)}',
                    style: TextStyle(
                      color: _text,
                      fontSize: InvoiceLayout.fontAmountDue,
                      fontWeight: InvoiceLayout.fontWeightBold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    doc.currency,
                    style: TextStyle(
                      color: _text,
                      fontSize: InvoiceLayout.fontLabel,
                      fontWeight: InvoiceLayout.fontWeightLabel,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );

  // Number of payment fields per row. The present bank fields (NAME, BSB,
  // ACCOUNT, ACN/ABN, SWIFT/BIC, BANK) wrap across rows so nothing is clipped
  // and empty fields are dropped entirely.
  static const _payColumns = 3;

  Widget _payments() {
    final fields = doc.paymentFields;
    // Nothing to pay to — omit the whole block rather than show an empty heading.
    if (fields.isEmpty && !_present(doc.paymentLink)) {
      return const SizedBox.shrink();
    }
    final rows = <List<(String, String)>>[
      for (var i = 0; i < fields.length; i += _payColumns)
        fields.sublist(
          i,
          (i + _payColumns).clamp(0, fields.length),
        ),
    ];
    return Column(
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
        if (_present(doc.paymentLink)) ...[
          _field('Link', doc.paymentLink),
          const SizedBox(height: InvoiceLayout.paymentsFieldGap),
        ],
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: InvoiceLayout.paymentsFieldGap),
          _paymentRow(row),
        ],
      ],
    );
  }

  // One row of payment fields, padded with empty cells so column widths stay
  // constant across rows (a two-field row aligns with a three-field row above).
  Widget _paymentRow(List<(String, String)> row) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var c = 0; c < _payColumns; c++) ...[
        if (c > 0) const SizedBox(width: InvoiceLayout.gridGutter),
        Expanded(
          child: c < row.length
              ? _field(row[c].$1, row[c].$2)
              : const SizedBox(),
        ),
      ],
    ],
  );

  static bool _present(String? s) => s != null && s.trim().isNotEmpty;
}
