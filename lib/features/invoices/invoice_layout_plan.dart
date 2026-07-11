// The resolved layout decisions for one invoice — the seam between *what an
// invoice looks like* and *how it is painted*.
//
// [InvoiceLayout.resolve] turns an [InvoiceDocument] into an [InvoiceLayoutPlan]
// once; both painters (the on-screen preview and the PDF exporter) consume the
// plan and make NO layout decision of their own. Presence (which cells/rows/
// blocks appear), the risky geometry (the recipient quarter width the preview
// used to re-measure per widget), and the chunked payment rows are all decided
// here, so the two outputs cannot drift.
//
// Pure Dart — imports nothing from Flutter or the `pdf` package. Widths are in
// design pixels (the 820px canvas); the PDF painter multiplies by pdfScale, the
// preview uses them as-is — exactly the existing convention. The plan carries
// only layout decisions; raw data (numbers, labels, formatted money/time) still
// comes from the [InvoiceDocument] the painter also holds.
import 'dart:typed_data';

/// What fills the masthead logo slot, resolved from the document's logo bytes
/// and [LogoFallback] once (was a three-way branch in each painter).
enum LogoSlot {
  none, // draw nothing
  brandMark, // the app's timedart mark (default profile only)
  placeholder, // a neutral "[Logo]" box (template-editor previews)
  image, // the profile's own logo bytes
}

/// The masthead logo, resolved. [image] is non-null iff [slot] is
/// [LogoSlot.image].
class LogoPlan {
  final LogoSlot slot;
  final Uint8List? image;
  const LogoPlan(this.slot, [this.image]);
}

/// One entry on the masthead contact line, e.g. ('e.', 'me@co') — the painter
/// styles the prefix (bold, muted) and joins entries with the separator.
class ContactSpan {
  final String prefix;
  final String value;
  const ContactSpan(this.prefix, this.value);
}

/// One (label, value) payment field, already ordered and non-empty.
class PayField {
  final String label;
  final String value;
  const PayField(this.label, this.value);
}

class MastheadPlan {
  final LogoPlan logo;
  final bool showAddress;
  final List<ContactSpan> contact; // ordered e./t./w., empties dropped
  const MastheadPlan({
    required this.logo,
    required this.showAddress,
    required this.contact,
  });
}

class PartyPlan {
  final bool showInvoiceNumber;
  final String attValue; // attention ?? organisation, resolved once
  const PartyPlan({required this.showInvoiceNumber, required this.attValue});
}

/// Recipient grid presence. Row 1 (org/email/phone) is always drawn; row 2
/// (address + buyer tax id) and its cells are conditional.
class RecipientPlan {
  final bool showSecondRow; // address present OR tax cell present
  final bool showAddress; // recipientAddress present
  final bool showTaxCell; // recipientAbn present
  const RecipientPlan({
    required this.showSecondRow,
    required this.showAddress,
    required this.showTaxCell,
  });
}

class TotalsPlan {
  final int labelSpan; // colItem + colDate + colRate
  final double amountDueWidth; // spans TIME + TOTAL + their gutter (design px)
  final bool showTaxRow; // doc.tax != null
  final bool showReverseCharge; // XOR with showTaxRow, enforced in resolve
  const TotalsPlan({
    required this.labelSpan,
    required this.amountDueWidth,
    required this.showTaxRow,
    required this.showReverseCharge,
  });
}

class PaymentsPlan {
  final bool visible; // the block is drawn at all
  final List<List<PayField>> rows; // showBank-gated, chunked into columns
  final bool showLink; // showPaymentLink AND a non-blank link
  final bool showPaymentNote; // bank fields present AND region has a note
  const PaymentsPlan({
    required this.visible,
    required this.rows,
    required this.showLink,
    required this.showPaymentNote,
  });
}

/// Resolved widths in design pixels. The single source for the recipient
/// quarter width the preview used to re-measure in two separate LayoutBuilders.
class GeometryPlan {
  final double recipientQuarter; // ORG-grid quarter (tax cell width)
  final double attColWidth; // ATT column = 2 × quarter (RE aligns over EMAIL)
  const GeometryPlan({
    required this.recipientQuarter,
    required this.attColWidth,
  });
}

/// The whole resolved layout for one invoice. Both painters take this plus the
/// source [InvoiceDocument]; the plan owns every decision, the document owns the
/// data.
class InvoiceLayoutPlan {
  final MastheadPlan masthead;
  final PartyPlan party;
  final RecipientPlan recipient;
  final TotalsPlan totals;
  final PaymentsPlan payments;
  final GeometryPlan geometry;
  const InvoiceLayoutPlan({
    required this.masthead,
    required this.party,
    required this.recipient,
    required this.totals,
    required this.payments,
    required this.geometry,
  });
}
