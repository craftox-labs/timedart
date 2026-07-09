import 'package:time_tracker/features/invoices/bank_validators.dart';

// The invoice region shapes tax + identity conventions (PRD #117, slice #120):
// which tax label to default to, how to label the buyer's tax ID on the
// recipient block, and whether a taxed invoice is titled "Tax Invoice" (the
// Australian tax-invoice rule) or plainly "Invoice".
//
// Deliberately pure — no Flutter/drift imports — so it's unit-testable in
// isolation and the tests can encode each region's convention as a fixture
// (they are the compliance guard). Persisted as the enum's [name] in
// Profiles.region; [fromName] parses it back, defaulting unknown/null to
// [other] so an unrecognised value can never crash a render.
enum InvoiceRegion {
  au(
    'Australia',
    defaultTaxLabel: 'GST',
    buyerTaxIdLabel: 'ABN',
    defaultCurrency: 'AUD',
  ),
  uk(
    'United Kingdom',
    defaultTaxLabel: 'VAT',
    buyerTaxIdLabel: 'VAT NO.',
    defaultCurrency: 'GBP',
  ),
  eu(
    'European Union',
    defaultTaxLabel: 'VAT',
    buyerTaxIdLabel: 'VAT NO.',
    defaultCurrency: 'EUR',
  ),
  us(
    'United States',
    defaultTaxLabel: null,
    buyerTaxIdLabel: 'TAX NO.',
    defaultCurrency: 'USD',
  ),
  ca(
    'Canada',
    defaultTaxLabel: 'GST/HST',
    buyerTaxIdLabel: 'GST NO.',
    defaultCurrency: 'CAD',
  ),
  other(
    'Other',
    defaultTaxLabel: null,
    buyerTaxIdLabel: 'TAX NO.',
    defaultCurrency: null,
  );

  const InvoiceRegion(
    this.label, {
    required this.defaultTaxLabel,
    required this.buyerTaxIdLabel,
    required this.defaultCurrency,
  });

  /// Human-readable region name for the profile editor's region picker.
  final String label;

  /// Pre-fills the profile's tax label when the region is chosen; null means
  /// the region has no default sales tax on services (US, Other).
  final String? defaultTaxLabel;

  /// The recipient-block label for the buyer's tax identifier.
  final String buyerTaxIdLabel;

  /// The region's most common invoicing currency (ISO code), pre-filled when the
  /// region is chosen; null ([other]) means no sensible default, so the field is
  /// left as-is. Always user-editable.
  final String? defaultCurrency;

  /// Parse a persisted region name back to the enum. Unknown or null → [other].
  static InvoiceRegion fromName(String? name) {
    for (final r in values) {
      if (r.name == name) return r;
    }
    return InvoiceRegion.other;
  }

  /// The invoice title. Only Australia distinguishes a GST-registered taxable
  /// sale as a "Tax Invoice"; every other region uses a plain "Invoice".
  String invoiceTitle({required bool hasTax}) =>
      (this == InvoiceRegion.au && hasTax) ? 'Tax Invoice' : 'Invoice';

  /// The region-specific bank identifiers, in display order. The universal
  /// fields (account name, sender tax ID, bank name) are shown around these by
  /// both the editor and the invoice, so they're not repeated here.
  List<BankField> get bankFields => switch (this) {
    InvoiceRegion.au => const [
      BankField.bsb,
      BankField.account,
      BankField.payid,
      BankField.bic,
    ],
    InvoiceRegion.uk => const [
      BankField.sortCode,
      BankField.account,
      BankField.iban,
      BankField.bic,
    ],
    InvoiceRegion.eu => const [BankField.iban, BankField.bic],
    InvoiceRegion.us => const [
      BankField.routing,
      BankField.account,
      // For international wires the note advertises — a US beneficiary needs a
      // SWIFT/BIC alongside the ABA routing used for domestic ACH/wire.
      BankField.bic,
    ],
    InvoiceRegion.ca => const [
      BankField.institution,
      BankField.transit,
      BankField.account,
    ],
    InvoiceRegion.other => const [
      BankField.iban,
      BankField.bic,
      BankField.account,
    ],
  };

  /// A short payment caption printed under the bank block, or null. US invoices
  /// note the domestic-vs-international rail; other regions have none.
  String? get paymentNote => this == InvoiceRegion.us
      ? 'Pay by ACH (domestic) or wire (international).'
      : null;

  /// Reverse charge (the customer accounts for VAT) is an EU/UK B2B mechanism;
  /// offered only for those regions.
  bool get supportsReverseCharge =>
      this == InvoiceRegion.uk || this == InvoiceRegion.eu;
}

/// One bank identifier, with its invoice-block label and editor-field label.
/// Which fields a region uses (and their order) is [InvoiceRegion.bankFields];
/// the value/controller wiring lives in the document + editor. [validate]
/// surfaces a non-blocking format hint (null = acceptable/empty).
enum BankField {
  bsb('BSB', 'BSB'),
  account('ACCOUNT', 'Account'),
  payid('PAYID', 'PayID'),
  sortCode('SORT CODE', 'Sort code'),
  iban('IBAN', 'IBAN'),
  routing('ROUTING (ABA)', 'Routing number'),
  institution('INSTITUTION', 'Institution number'),
  transit('TRANSIT', 'Transit number'),
  bic('SWIFT/BIC', 'SWIFT / BIC');

  const BankField(this.invoiceLabel, this.editorLabel);

  final String invoiceLabel;
  final String editorLabel;

  /// Non-blocking format check for this field's value (null = ok/empty).
  String? validate(String value) => switch (this) {
    BankField.bsb => bsbError(value),
    BankField.sortCode => sortCodeError(value),
    BankField.iban => ibanError(value),
    BankField.routing => abaError(value),
    _ => null,
  };
}
