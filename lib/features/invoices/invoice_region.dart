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
  au('Australia', defaultTaxLabel: 'GST', buyerTaxIdLabel: 'ABN'),
  uk('United Kingdom', defaultTaxLabel: 'VAT', buyerTaxIdLabel: 'VAT NO.'),
  eu('European Union', defaultTaxLabel: 'VAT', buyerTaxIdLabel: 'VAT NO.'),
  us('United States', defaultTaxLabel: null, buyerTaxIdLabel: 'TAX NO.'),
  ca('Canada', defaultTaxLabel: 'GST/HST', buyerTaxIdLabel: 'GST NO.'),
  other('Other', defaultTaxLabel: null, buyerTaxIdLabel: 'TAX NO.');

  const InvoiceRegion(
    this.label, {
    required this.defaultTaxLabel,
    required this.buyerTaxIdLabel,
  });

  /// Human-readable region name for the profile editor's region picker.
  final String label;

  /// Pre-fills the profile's tax label when the region is chosen; null means
  /// the region has no default sales tax on services (US, Other).
  final String? defaultTaxLabel;

  /// The recipient-block label for the buyer's tax identifier.
  final String buyerTaxIdLabel;

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
}
