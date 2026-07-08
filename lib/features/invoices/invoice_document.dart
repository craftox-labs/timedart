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

import 'package:time_tracker/data/database.dart';

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
  final String? attention; // contact's first name (ATT:)
  final String? recipientContact; // full contact name (TO person)
  final String organisation; // client.name (ORGANISATION)
  final String? recipientEmail;
  final String? recipientPhone;

  // Lines + money
  final List<InvoiceLineItem> lines;
  final String currency;
  final InvoiceTax? tax;

  // Payment (from the profile)
  final String? payeeName;
  final String? bankName;
  final String? bankBsb;
  final String? bankAccount;
  final String? swift;
  final String? paymentLink;

  const InvoiceDocument({
    required this.invoiceNumber,
    required this.issueDate,
    required this.periodFrom,
    required this.periodTo,
    required this.reference,
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
    required this.lines,
    required this.currency,
    required this.tax,
    required this.payeeName,
    required this.bankName,
    required this.bankBsb,
    required this.bankAccount,
    required this.swift,
    required this.paymentLink,
  });

  double get subtotal => lines.fold(0, (sum, l) => sum + l.amount);
  double get total => subtotal + (tax?.amount ?? 0);
  double get amountDue => total;
  int get totalSeconds => lines.fold(0, (sum, l) => sum + l.seconds);
  Duration get totalTime => Duration(seconds: totalSeconds);
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

  final subtotal = lines.fold<double>(0, (sum, l) => sum + l.amount);
  final taxLabel = profile.taxLabel?.trim();
  final taxRate = profile.taxRate;
  final tax = (taxLabel != null && taxLabel.isNotEmpty && taxRate != null)
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
    reference: project.code,
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
    attention: _firstName(client.contactName),
    recipientContact: _blankToNull(client.contactName),
    organisation: client.name,
    recipientEmail: client.email,
    recipientPhone: client.phone,
    lines: lines,
    currency: profile.currency,
    tax: tax,
    payeeName: profile.payeeName,
    bankName: profile.bankName,
    bankBsb: profile.bankBsb,
    bankAccount: profile.bankAccount,
    swift: profile.swift,
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

  final subtotal = lines.fold<double>(0, (sum, l) => sum + l.amount);
  final taxLabel = profile.taxLabel?.trim();
  final taxRate = profile.taxRate;
  final tax = (taxLabel != null && taxLabel.isNotEmpty && taxRate != null)
      ? InvoiceTax(label: taxLabel, rate: taxRate, amount: subtotal * taxRate / 100)
      : null;

  return InvoiceDocument(
    invoiceNumber: 'INV-0001',
    issueDate: issueDate,
    periodFrom: from,
    periodTo: issueDate,
    reference: 'SAMPLE',
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
    lines: lines,
    currency: profile.currency,
    tax: tax,
    payeeName: profile.payeeName,
    bankName: profile.bankName,
    bankBsb: profile.bankBsb,
    bankAccount: profile.bankAccount,
    swift: profile.swift,
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
  final taxLabel = profile.taxLabel?.trim();
  final taxRate = profile.taxRate;
  // No lines to tax against, so amount is always 0 — the label/rate are the
  // only structurally meaningful part of a zero-transaction preview.
  final tax = (taxLabel != null && taxLabel.isNotEmpty && taxRate != null)
      ? InvoiceTax(label: taxLabel, rate: taxRate, amount: 0)
      : null;

  return InvoiceDocument(
    invoiceNumber: null,
    issueDate: issueDate,
    periodFrom: issueDate,
    periodTo: issueDate,
    reference: '—',
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
    lines: const [],
    currency: profile.currency,
    tax: tax,
    payeeName: profile.payeeName,
    bankName: profile.bankName,
    bankBsb: profile.bankBsb,
    bankAccount: profile.bankAccount,
    swift: profile.swift,
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

String? _firstName(String? contact) {
  final t = contact?.trim();
  if (t == null || t.isEmpty) return null;
  return t.split(RegExp(r'\s+')).first;
}

String? _blankToNull(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}
