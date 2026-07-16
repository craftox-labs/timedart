import 'package:flutter/material.dart';
import 'package:timedart/constants/format.dart';
import 'package:timedart/constants/layout.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/invoices/invoice_document.dart';
import 'package:timedart/features/invoices/invoice_layout.dart';
import 'package:timedart/features/invoices/invoice_layout_plan.dart';
import 'package:timedart/features/invoices/invoice_region.dart';

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

/// The invoice preview laid out as a page — a sheet at the print proportions of
/// the document's region ([InvoiceRegion.pageSize]: A4 everywhere, Letter for
/// the US). Fills [brandingPreviewFrame] edge to edge. Scrolls vertically inside
/// its parent when the invoice runs longer than one page height. Pass
/// [scrollable] = false when embedding inside an outer scroll view. [size]
/// overrides the region-derived page size (tests only).
Widget invoicePreviewPage({
  required InvoiceDocument doc,
  required InvoiceTemplate template,
  InvoicePageSize? size,
  bool scrollable = true,
}) {
  final pageSize = size ?? doc.region.pageSize;
  return LayoutBuilder(
    builder: (context, c) {
      const designWidth = InvoiceLayout.designWidth;
      // The design canvas is A4-width; a wider page (Letter) makes the sheet
      // proportionally wider and centres the fixed-width content, so the extra
      // width reads as side margin — matching how the PDF widens its margins.
      // Column math stays keyed to one content width, so nothing reflows.
      final pageWidth =
          designWidth * pageSize.widthPt / InvoiceLayout.pdfPageWidth;
      final sheet = Container(
        width: pageWidth,
        constraints: BoxConstraints(minHeight: pageWidth * pageSize.ratio),
        color: Color(template.colorBackground),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: designWidth,
            child: InvoicePreview(doc: doc, template: template),
          ),
        ),
      );
      // Scale the fixed-width design sheet to fill the available width at any
      // screen size — up as well as down. FittedBox only rescales when given a
      // tight width, so pin the page to the pane width (falling back to the
      // native width if the pane is horizontally unbounded).
      final targetWidth = c.maxWidth.isFinite ? c.maxWidth : pageWidth;
      final page = SizedBox(
        width: targetWidth,
        child: FittedBox(
          fit: BoxFit.fitWidth,
          alignment: Alignment.topCenter,
          child: sheet,
        ),
      );
      // On a phone the fit-to-width page renders design text at ~6px — faithful
      // but unreadable. Make the preview zoomable: fit-to-width is the resting/
      // overview scale, pinch or double-tap to zoom in and pan to read. Same
      // page widget, so preview still == PDF layout.
      if (context.isNarrow) {
        final zoomable = _ZoomablePage(page: page);
        // The invoice view hands us a bounded slot (an Expanded) to fill, so
        // the viewer pans within that. The editor previews (scrollable: false)
        // sit in an unbounded outer scroll with no viewport of their own, so
        // give the zoom window an A4-proportioned box: the resting (fit-width)
        // view then shows a whole page in true proportion rather than a
        // crunched slice, and pinch/pan reveals a longer invoice that overflows.
        if (scrollable) return zoomable;
        return SizedBox(
          width: targetWidth,
          height: targetWidth * pageSize.ratio,
          child: zoomable,
        );
      }
      return scrollable ? SingleChildScrollView(child: page) : page;
    },
  );
}

/// Wraps the fit-to-width invoice [page] in an [InteractiveViewer] so a phone
/// user can pinch or double-tap to zoom past the tiny overview scale and pan to
/// read. `constrained: false` lets the page keep its natural (fit-width) size as
/// the scale-1 resting state — that's the overview — with [_maxScale] headroom
/// to zoom in and vertical pan covering a page taller than the viewport.
class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({required this.page});

  final Widget page;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage>
    with SingleTickerProviderStateMixin {
  // Fit-width text renders at ~0.44 scale on a ~360px phone, so ~2.5x brings
  // 14px design text back to a readable size. maxScale leaves pinch headroom.
  static const double _doubleTapScale = 2.5;
  static const double _maxScale = 5;

  final _controller = TransformationController();
  // Created eagerly in initState, not as a lazy `late` field: a lazy initializer
  // would first run inside dispose() if the user never double-tapped, and
  // building an AnimationController there does a TickerMode ancestor lookup on a
  // deactivated element — a crash on close.
  late final AnimationController _anim;
  Animation<Matrix4>? _zoomAnim;
  TapDownDetails? _lastTap;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    final current = _controller.value;
    final zoomedIn = current.getMaxScaleOnAxis() > 1.01;
    final Matrix4 target;
    if (zoomedIn) {
      target = Matrix4.identity();
    } else {
      // Zoom in centred on the tapped point: scale up, then translate so that
      // point stays put under the finger.
      final focal = _lastTap?.localPosition ?? Offset.zero;
      target = Matrix4.identity()
        ..translateByDouble(
          -focal.dx * (_doubleTapScale - 1),
          -focal.dy * (_doubleTapScale - 1),
          0,
          1,
        )
        ..scaleByDouble(
          _doubleTapScale,
          _doubleTapScale,
          _doubleTapScale,
          1,
        );
    }
    _zoomAnim = Matrix4Tween(begin: current, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
    )..addListener(() => _controller.value = _zoomAnim!.value);
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (d) => _lastTap = d,
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        constrained: false,
        minScale: 1,
        maxScale: _maxScale,
        boundaryMargin: const EdgeInsets.all(AppTokens.spaceLg),
        transformationController: _controller,
        child: widget.page,
      ),
    );
  }
}

/// On-screen WYSIWYG preview of an [InvoiceDocument] rendered with an
/// [InvoiceTemplate]. Both this painter and invoice_pdf.dart consume the same
/// [InvoiceLayoutPlan] from [InvoiceLayout.resolve] for every layout decision,
/// so what you see matches the export by construction, not by hand-mirroring.
/// Spacing/typography still come from [InvoiceLayout]; edit that to restyle both.
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
    final plan = InvoiceLayout.resolve(doc);
    return Container(
      color: _bg,
      padding: const EdgeInsets.all(InvoiceLayout.pageMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _masthead(plan.masthead),
          const SizedBox(height: InvoiceLayout.sectionGap),
          _party(plan.party, plan.geometry),
          const SizedBox(height: InvoiceLayout.partyBlockGap),
          _recipientGrid(plan.recipient, plan.geometry),
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
          _totals(plan.totals),
          if (plan.totals.showReverseCharge) ...[
            const SizedBox(height: InvoiceLayout.totalsGap),
            Text(
              InvoiceDocument.reverseChargeStatement,
              style: TextStyle(
                color: _primary,
                fontSize: InvoiceLayout.fontLabel,
                fontWeight: InvoiceLayout.fontWeightLabel,
              ),
            ),
          ],
          const SizedBox(height: InvoiceLayout.sectionGap),
          _payments(plan.payments),
        ],
      ),
    );
  }

  // Business details sit at the left edge; the logo anchors the right edge,
  // both vertically centred so the logo sits on the details block's midline.
  // Separating the two gives whatever icon/logo the user supplies its own room
  // rather than stacking text beneath it.
  Widget _masthead(MastheadPlan masthead) {
    final logo = _logo(masthead.logo);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
              if (masthead.showAddress)
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
                  children: _contactSpans(masthead.contact),
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
  Widget? _logo(LogoPlan logo) {
    switch (logo.slot) {
      case LogoSlot.image:
        return Image.memory(logo.image!, height: InvoiceLayout.logoHeight);
      case LogoSlot.brandMark:
        return Image.asset(
          'assets/logo/timedart_logo_horizontal.png',
          height: InvoiceLayout.logoHeight,
        );
      case LogoSlot.placeholder:
        return _logoPlaceholder();
      case LogoSlot.none:
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
  List<InlineSpan> _contactSpans(List<ContactSpan> contact) {
    final prefixStyle = TextStyle(
      fontWeight: InvoiceLayout.fontWeightLabel,
      color: _primary,
    );
    return [
      for (final (i, entry) in contact.indexed) ...[
        if (i > 0) const TextSpan(text: '    '),
        TextSpan(text: entry.prefix, style: prefixStyle),
        TextSpan(text: ' ${entry.value}'),
      ],
    ];
  }

  Widget _party(PartyPlan party, GeometryPlan geometry) {
    Widget headField(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _label),
        Text(
          value,
          style: TextStyle(
            color: _primary,
            fontSize: InvoiceLayout.fontHeadline,
            fontWeight: InvoiceLayout.fontWeightBold,
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          doc.title.toUpperCase(),
          style: TextStyle(
            color: _primary,
            fontSize: InvoiceLayout.fontPaymentsHeading,
            fontWeight: InvoiceLayout.fontWeightBold,
          ),
        ),
        const SizedBox(height: InvoiceLayout.headlineGap),
        Text(
          _iso(doc.issueDate),
          style: TextStyle(
            color: _primary,
            fontSize: InvoiceLayout.fontLabel,
          ),
        ),
        if (party.showInvoiceNumber)
          Text(
            doc.invoiceNumber!,
            style: TextStyle(
              color: _primary,
              fontSize: InvoiceLayout.fontInvoiceNumber,
              fontWeight: InvoiceLayout.fontWeightBold,
            ),
          ),
        const SizedBox(height: InvoiceLayout.headlineGap),
        // ATT takes ORGANISATION's half-width (two quarters) so RE starts on
        // the EMAIL column's left edge below, not the org/email seam.
        Row(
          children: [
            SizedBox(
              width: geometry.attColWidth,
              child: headField('ATT:', party.attValue),
            ),
            const SizedBox(width: InvoiceLayout.gridGutter),
            Expanded(child: headField('RE:', doc.reference)),
          ],
        ),
      ],
    );
  }

  Widget _recipientGrid(RecipientPlan recipient, GeometryPlan geometry) {
    // First line: ORGANISATION (half) | EMAIL (quarter) | PHONE (quarter).
    // ORGANISATION spans half so it sits under ATT above, and EMAIL/PHONE
    // fall under RE. (The company moved here from the old TO row once ATT
    // took the contact person.) Second line: ADDRESS spanning the org+email
    // columns, with the tax number aligned under PHONE — or ADDRESS
    // full-width when there's no tax number. Shown only when address/tax exist.
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _field(doc.region.organisationLabel, doc.organisation),
            ),
            const SizedBox(width: InvoiceLayout.gridGutter),
            Expanded(child: _field('EMAIL', doc.recipientEmail)),
            const SizedBox(width: InvoiceLayout.gridGutter),
            Expanded(child: _field('PHONE', doc.recipientPhone)),
          ],
        ),
        if (recipient.showSecondRow) ...[
          const SizedBox(height: InvoiceLayout.recipientGap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: recipient.showAddress
                    ? _field('ADDRESS', doc.recipientAddress)
                    : const SizedBox(),
              ),
              if (recipient.showTaxCell) ...[
                const SizedBox(width: InvoiceLayout.gridGutter),
                // Fixed to PHONE's quarter so it lands on its edges above.
                SizedBox(
                  width: geometry.recipientQuarter,
                  child: _field(doc.recipientAbnLabel, doc.recipientAbn),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

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

  // One totals line: a right-aligned bare label over the first three columns,
  // then caller-supplied cells over the last two (TIME + TOTAL). The two
  // leading gutters reproduce the ITEM|DATE and DATE|RATE gaps folded into the
  // merged label span; with the trailing gutter that makes four gutters total,
  // matching the line rows so every value box lands under its column exactly.
  Widget _totalsRow(String label, int labelSpan, List<Widget> trailing) =>
      Padding(
        padding: const EdgeInsets.only(
          bottom: InvoiceLayout.rowMarginBottom,
        ),
        child: Row(
          children: [
            _gutter,
            _gutter,
            Expanded(
              flex: labelSpan,
              child: _txt(label, right: true, style: _label),
            ),
            _gutter,
            ...trailing,
          ],
        ),
      );

  Widget _totals(TotalsPlan totals) => Column(
    children: [
      // TOTAL: time and amount each in their own box, aligned to the columns.
      _totalsRow('TOTAL:', totals.labelSpan, [
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
      if (totals.showTaxRow)
        _totalsRow('${doc.tax!.label} (${doc.tax!.rate}%):', totals.labelSpan, [
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
              width: totals.amountDueWidth,
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

  Widget _payments(PaymentsPlan payments) {
    // Nothing to pay to — omit the whole block rather than show an empty heading.
    if (!payments.visible) {
      return const SizedBox.shrink();
    }
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
        if (payments.showLink) ...[
          _field('LINK', doc.paymentLink),
          if (payments.rows.isNotEmpty)
            const SizedBox(height: InvoiceLayout.paymentsFieldGap),
        ],
        for (final (i, row) in payments.rows.indexed) ...[
          if (i > 0) const SizedBox(height: InvoiceLayout.paymentsFieldGap),
          _paymentRow(row),
        ],
        if (payments.showPaymentNote) ...[
          const SizedBox(height: InvoiceLayout.paymentsFieldGap),
          Text(
            doc.region.paymentNote!,
            style: TextStyle(color: _muted, fontSize: InvoiceLayout.fontValue),
          ),
        ],
      ],
    );
  }

  // One row of payment fields. The row's items divide its full width evenly, so
  // a short row (e.g. a lone BANK) still spans 100% — columns intentionally do
  // NOT align across rows of differing counts.
  Widget _paymentRow(List<PayField> row) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var c = 0; c < row.length; c++) ...[
        if (c > 0) const SizedBox(width: InvoiceLayout.gridGutter),
        Expanded(child: _field(row[c].label, row[c].value)),
      ],
    ],
  );
}
