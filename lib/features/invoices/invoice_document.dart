// A pure, UI-free view-model for a rendered invoice (PRD #79).
//
// buildInvoiceDocument resolves the raw domain objects — the sender
// InvoiceProfile, the Project/Client, the period's Tasks and TimeEntries — into
// display-ready values and all the invoice arithmetic. Both renderers (the PDF
// exporter and the on-screen preview) read numbers and text from here rather
// than recomputing them, so the two can't drift.
//
// Deliberately imports NOTHING from Flutter or the `pdf` package: the logic is
// portable and unit-testable in isolation. Money/time *formatting* lives in
// `constants/format.dart` (also pure) and is applied by the renderers, so this
// module holds raw numbers and the currency code.
import 'dart:typed_data';

import 'package:timedart/data/database.dart';
import 'package:timedart/features/invoices/invoice_region.dart';

/// What a renderer shows in the masthead when [InvoiceDocument.logo] is null.
enum LogoFallback {
  brand, // the app's timedart mark — only the default profile
  placeholder, // a neutral "[Logo]" box — template-editor previews only
  none, // nothing at all — a real invoice for a profile with no logo
}

/// One billable line: a task/entry with its date, tracked time, and rate.
class InvoiceLineItem {
  final String item; // task title, plus the entry's own note when set
  final DateTime date; // the entry's start
  final int seconds; // tracked time (for hh:mm:ss)
  final double rate; // effective $/hr for this line

  const InvoiceLineItem({
    required this.item,
    required this.date,
    required this.seconds,
    required this.rate,
  });

  double get hours => seconds / 3600;
  double get amount => hours * rate;
}

/// An optional tax component. Present only when the profile defines a label and
/// rate; absent entirely for tax-free jurisdictions (no line rendered).
class InvoiceTax {
  final String label; // e.g. GST, VAT
  final double rate; // percent, e.g. 10.0
  final double amount; // subtotal * rate / 100

  const InvoiceTax({
    required this.label,
    required this.rate,
    required this.amount,
  });
}

/// The resolved invoice. Amounts are non-null because a client's default rate is
/// required (every line resolves `task.rate ?? project.rate ?? client.defaultRate`).
class InvoiceDocument {
  // Header
  final String? invoiceNumber; // entered at export; may be absent
  final DateTime issueDate;
  final DateTime periodFrom;
  final DateTime periodTo;
  final String reference; // the project code (RE:)
  final InvoiceRegion region; // sender's region — shapes tax/identity/title
  final String title; // "Tax Invoice" (AU + tax) or "Invoice"

  // Sender (from the profile)
  final String businessName;
  final Uint8List? logo; // business logo bytes (PNG/JPG)
  final LogoFallback logoFallback; // what to show when [logo] is null
  final String? senderEmail;
  final String? senderPhone;
  final String? senderWebsite;
  final String? senderAddress;
  final String? senderAbn;

  // Recipient (from the client)
  final String? attention; // full contact person (ATT:)
  final String? recipientContact; // full contact name (retained; grid shows org)
  final String organisation; // client.name (ORGANISATION)
  final String? recipientEmail;
  final String? recipientPhone;
  final String? recipientAddress; // client.address
  final String? recipientAbn; // client.abn (buyer tax ID)
  final String recipientAbnLabel; // region's buyer tax-ID label (ABN/VAT NO./…)

  // Lines + money
  final List<InvoiceLineItem> lines;
  final String currency;
  final InvoiceTax? tax;

  // Resolved invoice-inclusion flags (profile default, optionally overridden
  // per invoice at export). Let the sender deliberately omit a block even when
  // the data exists — no bank block on a card-paid invoice, no tax line on a
  // tax-exempt job. (showTax off is applied upstream: [tax] is already null.)
  final bool showBank;
  final bool showPaymentLink;
  // EU/UK B2B: the customer accounts for VAT. When true, [tax] is null (no VAT
  // amount) and the renderers print [reverseChargeStatement] in its place.
  final bool reverseCharge;

  /// The fixed reverse-charge wording. Not substitutable (EU VAT Directive
  /// Art. 226(11a); CJEU C-247/21) — both renderers print exactly this.
  static const reverseChargeStatement =
      'Reverse charge — customer accounts for VAT.';

  // Payment (from the profile). Which of these appear on the invoice — and in
  // what order — is decided per region (see [paymentFields]); the columns not
  // used by a region stay null.
  final String? payeeName;
  final String? bankName;
  final String? bankBsb;
  final String? bankAccount;
  final String? swift; // SWIFT/BIC
  final String? iban;
  final String? sortCode;
  final String? routingNumber;
  final String? payid;
  final String? institutionNumber;
  final String? transitNumber;
  final String? paymentLink;

  const InvoiceDocument({
    required this.invoiceNumber,
    required this.issueDate,
    required this.periodFrom,
    required this.periodTo,
    required this.reference,
    required this.region,
    required this.title,
    required this.businessName,
    required this.logo,
    required this.logoFallback,
    required this.senderEmail,
    required this.senderPhone,
    required this.senderWebsite,
    required this.senderAddress,
    required this.senderAbn,
    required this.attention,
    required this.recipientContact,
    required this.organisation,
    required this.recipientEmail,
    required this.recipientPhone,
    required this.recipientAddress,
    required this.recipientAbn,
    required this.recipientAbnLabel,
    required this.lines,
    required this.currency,
    required this.tax,
    this.showBank = true,
    this.showPaymentLink = true,
    this.reverseCharge = false,
    required this.payeeName,
    required this.bankName,
    required this.bankBsb,
    required this.bankAccount,
    required this.swift,
    this.iban,
    this.sortCode,
    this.routingNumber,
    this.payid,
    this.institutionNumber,
    this.transitNumber,
    required this.paymentLink,
  });

  double get subtotal => lines.fold(0, (sum, l) => sum + l.amount);
  double get total => subtotal + (tax?.amount ?? 0);
  double get amountDue => total;
  int get totalSeconds => lines.fold(0, (sum, l) => sum + l.seconds);
  Duration get totalTime => Duration(seconds: totalSeconds);

  String? _bankFieldValue(BankField f) => switch (f) {
    BankField.bsb => bankBsb,
    BankField.account => bankAccount,
    BankField.payid => payid,
    BankField.sortCode => sortCode,
    BankField.iban => iban,
    BankField.routing => routingNumber,
    BankField.institution => institutionNumber,
    BankField.transit => transitNumber,
    BankField.bic => swift,
  };

  /// The payment/bank fields to print, in order, as (label, value) pairs —
  /// empties dropped so a renderer shows only what the profile filled in, and
  /// the identifiers ordered per the sender's [region] (AU shows BSB+account,
  /// EU shows IBAN+BIC, …). Both renderers read this so the payment block can't
  /// drift between preview and PDF. Around the region identifiers sit the
  /// universal fields: account name, sender tax ID (region-labelled), and bank.
  List<(String, String)> get paymentFields {
    final out = <(String, String)>[];
    void add(String label, String? value) {
      final v = value?.trim();
      if (v != null && v.isNotEmpty) out.add((label, v));
    }

    add('NAME', payeeName);
    for (final f in region.bankFields) {
      add(f.invoiceLabel, _bankFieldValue(f));
    }
    add(region.buyerTaxIdLabel, senderAbn); // supplier's own tax ID
    add('BANK', bankName);
    return out;
  }
}

/// Resolve the domain objects into an [InvoiceDocument]. Pure: no DB, no I/O —
/// [issueDate] is injected so callers (and tests) control it. [entries] are
/// rendered in the order given (the caller sorts, typically by start).
InvoiceDocument buildInvoiceDocument({
  required InvoiceProfile profile,
  required Project project,
  required Client client,
  required List<Task> tasks,
  required List<TimeEntry> entries,
  required DateTime from,
  required DateTime to,
  required DateTime issueDate,
  String? invoiceNumber,
  // Per-invoice inclusion overrides (export-time); null → use the profile's
  // stored default. Let one invoice drop a block without editing the profile.
  bool? showBank,
  bool? showPaymentLink,
  bool? showTax,
}) {
  final taskById = {for (final t in tasks) t.id: t};

  final lines = [
    for (final e in entries)
      InvoiceLineItem(
        item: _label(taskById[e.taskId], e.description),
        date: e.startedAt,
        seconds: e.seconds,
        // task override → project rate → client default (always non-null).
        rate: taskById[e.taskId]?.rate ?? project.rate ?? client.defaultRate,
      ),
  ];

  final region = InvoiceRegion.fromName(profile.region);
  final resolvedShowBank = showBank ?? profile.showBank;
  final resolvedShowLink = showPaymentLink ?? profile.showPaymentLink;
  final resolvedShowTax = showTax ?? profile.showTax;
  // Reverse charge applies only to EU/UK; it removes the VAT amount (the
  // customer accounts for it) — so it also suppresses the tax line.
  final reverseCharge = region.supportsReverseCharge && profile.reverseCharge;

  final subtotal = lines.fold<double>(0, (sum, l) => sum + l.amount);
  final taxLabel = profile.taxLabel?.trim();
  final taxRate = profile.taxRate;
  // showTax off (or reverse charge) removes the line AND its amount.
  final tax = (resolvedShowTax &&
          !reverseCharge &&
          taxLabel != null &&
          taxLabel.isNotEmpty &&
          taxRate != null)
      ? InvoiceTax(
          label: taxLabel,
          rate: taxRate,
          amount: subtotal * taxRate / 100,
        )
      : null;

  return InvoiceDocument(
    invoiceNumber: _blankToNull(invoiceNumber),
    issueDate: issueDate,
    periodFrom: from,
    periodTo: to,
    reference: project.code ?? project.title, // code, else title (#331)
    region: region,
    title: region.invoiceTitle(hasTax: tax != null),
    showBank: resolvedShowBank,
    showPaymentLink: resolvedShowLink,
    reverseCharge: reverseCharge,
    businessName: profile.businessName,
    logo: profile.logo,
    // A real invoice: the default profile falls back to the timedart mark;
    // any other logo-less profile shows nothing.
    logoFallback: profile.isDefault ? LogoFallback.brand : LogoFallback.none,
    senderEmail: profile.email,
    senderPhone: profile.phone,
    senderWebsite: profile.website,
    senderAddress: profile.address,
    senderAbn: profile.abn,
    // ATT: the client's full contact person (#139). The organisation name
    // moves into the recipient grid (ORGANISATION), replacing the old TO row.
    attention: _blankToNull(client.contactName),
    recipientContact: _blankToNull(client.contactName),
    organisation: client.name,
    recipientEmail: client.email,
    recipientPhone: client.phone,
    recipientAddress: _blankToNull(client.address),
    recipientAbn: _blankToNull(client.abn),
    recipientAbnLabel: region.buyerTaxIdLabel,
    lines: lines,
    currency: profile.currency,
    tax: tax,
    payeeName: profile.payeeName,
    bankName: profile.bankName,
    bankBsb: profile.bankBsb,
    bankAccount: profile.bankAccount,
    swift: profile.swift,
    iban: profile.iban,
    sortCode: profile.sortCode,
    routingNumber: profile.routingNumber,
    payid: profile.payid,
    institutionNumber: profile.institutionNumber,
    transitNumber: profile.transitNumber,
    paymentLink: profile.paymentLink,
  );
}

/// A synthetic [InvoiceDocument] for branding previews — a fixed set of
/// placeholder line items plus a stand-in recipient, dressed with a real
/// [profile]'s sender/payment/tax fields. Lets the theme/profile/template
/// editors show a live, representative invoice without a real project or any tracked
/// time. Pure: [issueDate] is injected so it's deterministic in tests/previews.
InvoiceDocument sampleInvoiceDocument({
  required InvoiceProfile profile,
  required DateTime issueDate,
}) {
  final from = DateTime(issueDate.year, issueDate.month);
  final lines = <InvoiceLineItem>[
    InvoiceLineItem(
      item: 'Design · Homepage layout',
      date: from,
      seconds: 3 * 3600 + 30 * 60,
      rate: 120,
    ),
    InvoiceLineItem(
      item: 'Development · API integration',
      date: from.add(const Duration(days: 6)),
      seconds: 5 * 3600,
      rate: 120,
    ),
    InvoiceLineItem(
      item: 'Review · Client walkthrough',
      date: from.add(const Duration(days: 12)),
      seconds: 45 * 60,
      rate: 90,
    ),
  ];

  final region = InvoiceRegion.fromName(profile.region);
  final reverseCharge = region.supportsReverseCharge && profile.reverseCharge;
  final subtotal = lines.fold<double>(0, (sum, l) => sum + l.amount);
  final taxLabel = profile.taxLabel?.trim();
  final taxRate = profile.taxRate;
  final tax =
      (profile.showTax &&
          !reverseCharge &&
          taxLabel != null &&
          taxLabel.isNotEmpty &&
          taxRate != null)
      ? InvoiceTax(label: taxLabel, rate: taxRate, amount: subtotal * taxRate / 100)
      : null;

  return InvoiceDocument(
    invoiceNumber: 'INV-0001',
    showBank: profile.showBank,
    showPaymentLink: profile.showPaymentLink,
    reverseCharge: reverseCharge,
    issueDate: issueDate,
    periodFrom: from,
    periodTo: issueDate,
    reference: 'SAMPLE',
    region: region,
    title: region.invoiceTitle(hasTax: tax != null),
    businessName: profile.businessName,
    // A template preview is about the visual style, not identity — the logo
    // comes from the profile — so it always shows the neutral placeholder.
    logo: null,
    logoFallback: LogoFallback.placeholder,
    senderEmail: profile.email,
    senderPhone: profile.phone,
    senderWebsite: profile.website,
    senderAddress: profile.address,
    senderAbn: profile.abn,
    attention: 'Alex',
    recipientContact: 'Alex Rivera',
    organisation: 'Sample Client Co.',
    recipientEmail: 'accounts@example.com',
    recipientPhone: '+61 400 000 000',
    recipientAddress: '10 Sample Street, Sydney NSW 2000',
    recipientAbn: '12 345 678 901',
    recipientAbnLabel: region.buyerTaxIdLabel,
    lines: lines,
    currency: profile.currency,
    tax: tax,
    payeeName: profile.payeeName,
    bankName: profile.bankName,
    bankBsb: profile.bankBsb,
    bankAccount: profile.bankAccount,
    swift: profile.swift,
    iban: profile.iban,
    sortCode: profile.sortCode,
    routingNumber: profile.routingNumber,
    payid: profile.payid,
    institutionNumber: profile.institutionNumber,
    transitNumber: profile.transitNumber,
    paymentLink: profile.paymentLink,
  );
}

/// A structure-only [InvoiceDocument] for the profile editor's preview: real
/// sender/payment/tax fields from [profile], but no fabricated client, project, or
/// tracked-time data — those fields are blanked (rendering as the same '—'
/// placeholder empty fields already use) since a profile has no relationship
/// to any particular client or invoice. Contrast [sampleInvoiceDocument],
/// which fills in a stand-in client + line items so the theme/template
/// editors can show what a *populated* invoice looks like.
InvoiceDocument profilePreviewDocument({
  required InvoiceProfile profile,
  required DateTime issueDate,
}) {
  final region = InvoiceRegion.fromName(profile.region);
  final reverseCharge = region.supportsReverseCharge && profile.reverseCharge;
  final taxLabel = profile.taxLabel?.trim();
  final taxRate = profile.taxRate;
  // A single placeholder line so the Details table + totals read like a real
  // invoice; the client/recipient stays blanked ('—') as before.
  final lines = <InvoiceLineItem>[
    InvoiceLineItem(
      item: 'Sample task · Time entry',
      date: issueDate,
      seconds: 1 * 3600 + 30 * 60,
      rate: 120,
    ),
  ];
  final subtotal = lines.fold<double>(0, (sum, l) => sum + l.amount);
  final tax =
      (profile.showTax &&
          !reverseCharge &&
          taxLabel != null &&
          taxLabel.isNotEmpty &&
          taxRate != null)
      ? InvoiceTax(
          label: taxLabel,
          rate: taxRate,
          amount: subtotal * taxRate / 100,
        )
      : null;

  return InvoiceDocument(
    invoiceNumber: null,
    showBank: profile.showBank,
    showPaymentLink: profile.showPaymentLink,
    reverseCharge: reverseCharge,
    issueDate: issueDate,
    periodFrom: issueDate,
    periodTo: issueDate,
    reference: '—',
    region: region,
    title: region.invoiceTitle(hasTax: tax != null),
    businessName: profile.businessName,
    logo: profile.logo,
    // Mirror the real invoice: brand mark for the default, nothing otherwise.
    logoFallback: profile.isDefault ? LogoFallback.brand : LogoFallback.none,
    senderEmail: profile.email,
    senderPhone: profile.phone,
    senderWebsite: profile.website,
    senderAddress: profile.address,
    senderAbn: profile.abn,
    attention: '—',
    recipientContact: null,
    organisation: '',
    recipientEmail: null,
    recipientPhone: null,
    recipientAddress: null,
    recipientAbn: null,
    recipientAbnLabel: region.buyerTaxIdLabel,
    lines: lines,
    currency: profile.currency,
    tax: tax,
    payeeName: profile.payeeName,
    bankName: profile.bankName,
    bankBsb: profile.bankBsb,
    bankAccount: profile.bankAccount,
    swift: profile.swift,
    iban: profile.iban,
    sortCode: profile.sortCode,
    routingNumber: profile.routingNumber,
    payid: profile.payid,
    institutionNumber: profile.institutionNumber,
    transitNumber: profile.transitNumber,
    paymentLink: profile.paymentLink,
  );
}

// The line label: task title, plus the entry's own note when it has one; falls
// back to the note alone, then a dash. Mirrors the old ProjectInvoice labelling.
String _label(Task? task, String? description) {
  final desc = description?.trim();
  final hasDesc = desc != null && desc.isNotEmpty;
  if (task == null) return hasDesc ? desc : '—';
  return hasDesc ? '${task.title} · $desc' : task.title;
}

String? _blankToNull(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}
