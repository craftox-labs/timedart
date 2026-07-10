import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/constants/format.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/invoices/invoice_document.dart';
import 'package:timedart/features/invoices/invoice_region.dart';

// Pure-logic coverage for the invoice view-model (PRD #79). Constructs domain
// rows directly (no DB) and asserts the resolved values + arithmetic.

final _t = DateTime(2026, 4, 25, 9);
final _issue = DateTime(2026, 6, 15);

InvoiceProfile _profile({
  String currency = 'AUD',
  String? taxLabel,
  double? taxRate,
  String? address,
  String? abn,
  String? payeeName,
  String? bankName,
  String? bankBsb,
  String? bankAccount,
  String? swift,
  String? iban,
  String? sortCode,
  String? routingNumber,
  String? payid,
  String? institutionNumber,
  String? transitNumber,
  String? paymentLink,
  InvoiceRegion region = InvoiceRegion.au,
  bool showBank = true,
  bool showPaymentLink = true,
  bool showTax = true,
  bool reverseCharge = false,
}) => InvoiceProfile(
  id: 1,
  name: 'Default',
  businessName: 'tmox.net',
  currency: currency,
  taxLabel: taxLabel,
  taxRate: taxRate,
  address: address,
  abn: abn,
  payeeName: payeeName,
  bankName: bankName,
  bankBsb: bankBsb,
  bankAccount: bankAccount,
  swift: swift,
  iban: iban,
  sortCode: sortCode,
  routingNumber: routingNumber,
  payid: payid,
  institutionNumber: institutionNumber,
  transitNumber: transitNumber,
  paymentLink: paymentLink,
  isDefault: true,
  region: region.name,
  showBank: showBank,
  showPaymentLink: showPaymentLink,
  showTax: showTax,
  showRateColumn: true,
  showTimeColumn: true,
  reverseCharge: reverseCharge,
);

Client _client({
  String name = 'Care Direct',
  String? contactName = 'Julien Remond',
  String? email = 'julien@dispensedirect.com.au',
  String? phone,
  String? address,
  String? abn,
  double defaultRate = 46,
}) => Client(
  id: 1,
  name: name,
  contactName: contactName,
  email: email,
  phone: phone,
  address: address,
  abn: abn,
  defaultRate: defaultRate,
);

Project _project({String code = 'CD002', double? rate}) => Project(
  id: 1,
  clientId: 1,
  code: code,
  title: 'Care Direct work',
  rate: rate,
  status: 'active',
  createdAt: _t,
);

Task _task({int id = 1, double? rate, String title = 'Mobile'}) => Task(
  id: id,
  projectId: 1,
  title: title,
  rate: rate,
  status: 'active',
  createdAt: _t,
);

TimeEntry _entry({
  int id = 1,
  int? taskId = 1,
  String? description,
  int seconds = 3600,
}) => TimeEntry(
  id: id,
  projectId: 1,
  taskId: taskId,
  description: description,
  startedAt: _t,
  endedAt: _t.add(Duration(seconds: seconds)),
  seconds: seconds,
);

InvoiceDocument _doc({
  InvoiceProfile? profile,
  Project? project,
  Client? client,
  List<Task>? tasks,
  required List<TimeEntry> entries,
  String? invoiceNumber,
  bool? showBank,
  bool? showPaymentLink,
  bool? showTax,
}) => buildInvoiceDocument(
  profile: profile ?? _profile(),
  project: project ?? _project(),
  client: client ?? _client(),
  tasks: tasks ?? [_task()],
  entries: entries,
  from: DateTime(2026, 4, 1),
  to: DateTime(2026, 4, 30),
  issueDate: _issue,
  invoiceNumber: invoiceNumber,
  showBank: showBank,
  showPaymentLink: showPaymentLink,
  showTax: showTax,
);

void main() {
  group('line resolution', () {
    test('amount = hours * effective rate', () {
      final doc = _doc(entries: [_entry(seconds: 1800)]); // 0.5h @ 46
      expect(doc.lines.single.hours, closeTo(0.5, 1e-9));
      expect(doc.lines.single.amount, closeTo(23, 1e-9));
    });

    test('rate resolves task override → project → client default', () {
      final doc = buildInvoiceDocument(
        profile: _profile(),
        project: _project(rate: 80), // project overrides client default (46)
        client: _client(defaultRate: 46),
        tasks: [_task(id: 1, rate: 120), _task(id: 2)], // task 1 overrides project
        entries: [
          _entry(id: 1, taskId: 1, seconds: 3600), // → 120
          _entry(id: 2, taskId: 2, seconds: 3600), // → project 80
        ],
        from: DateTime(2026, 4, 1),
        to: DateTime(2026, 4, 30),
        issueDate: _issue,
      );
      expect(doc.lines[0].rate, 120);
      expect(doc.lines[1].rate, 80);
    });

    test('rate falls to client default when project has none', () {
      final doc = buildInvoiceDocument(
        profile: _profile(),
        project: _project(rate: null),
        client: _client(defaultRate: 46),
        tasks: [_task(id: 1)],
        entries: [_entry(taskId: 1)],
        from: DateTime(2026, 4, 1),
        to: DateTime(2026, 4, 30),
        issueDate: _issue,
      );
      expect(doc.lines.single.rate, 46);
    });

    test('label: task title, task+note, note-only, dash', () {
      final doc = buildInvoiceDocument(
        profile: _profile(),
        project: _project(),
        client: _client(),
        tasks: [_task(id: 1, title: 'Mobile')],
        entries: [
          _entry(id: 1, taskId: 1), // task title only
          _entry(id: 2, taskId: 1, description: 'bugfix'), // task · note
          _entry(id: 3, taskId: null, description: 'ad hoc'), // note only
          _entry(id: 4, taskId: null), // dash
        ],
        from: DateTime(2026, 4, 1),
        to: DateTime(2026, 4, 30),
        issueDate: _issue,
      );
      expect(doc.lines[0].item, 'Mobile');
      expect(doc.lines[1].item, 'Mobile · bugfix');
      expect(doc.lines[2].item, 'ad hoc');
      expect(doc.lines[3].item, '—');
    });

    test('one line per entry, in the given order', () {
      final doc = _doc(
        entries: [_entry(id: 1), _entry(id: 2), _entry(id: 3)],
      );
      expect(doc.lines.length, 3);
    });
  });

  group('totals + time', () {
    test('subtotal sums line amounts; total == subtotal with no tax', () {
      final doc = _doc(
        entries: [_entry(id: 1, seconds: 3600), _entry(id: 2, seconds: 1800)],
      ); // (1 + 0.5)h @ 46 = 69
      expect(doc.subtotal, closeTo(69, 1e-9));
      expect(doc.tax, isNull);
      expect(doc.total, closeTo(69, 1e-9));
      expect(doc.amountDue, closeTo(69, 1e-9));
    });

    test('total time as hh:mm:ss', () {
      final doc = _doc(
        entries: [
          _entry(id: 1, seconds: 6464), // 01:47:44
          _entry(id: 2, seconds: 8910), // 02:28:30
        ],
      );
      expect(doc.totalSeconds, 15374);
      expect(doc.totalTime.hms, '04:16:14');
    });
  });

  group('tax', () {
    test('with label + rate → subtotal, tax, total', () {
      final doc = _doc(
        profile: _profile(taxLabel: 'GST', taxRate: 10),
        entries: [_entry(seconds: 3600)], // subtotal 46
      );
      expect(doc.subtotal, closeTo(46, 1e-9));
      expect(doc.tax!.label, 'GST');
      expect(doc.tax!.rate, 10);
      expect(doc.tax!.amount, closeTo(4.6, 1e-9));
      expect(doc.total, closeTo(50.6, 1e-9));
    });

    test('no tax when rate is null or label blank', () {
      expect(_doc(profile: _profile(taxLabel: 'GST'), entries: [_entry()]).tax,
          isNull); // rate null
      expect(
          _doc(profile: _profile(taxLabel: '  ', taxRate: 10), entries: [_entry()])
              .tax,
          isNull); // label blank
    });
  });

  group('header, parties, currency', () {
    test('reference is the project code; currency passes through', () {
      final doc = _doc(entries: [_entry()]);
      expect(doc.reference, 'CD002');
      expect(doc.currency, 'AUD');
      expect(doc.issueDate, _issue);
    });

    test('attention is the full contact person; org is client.name', () {
      final doc = _doc(entries: [_entry()]);
      expect(doc.attention, 'Julien Remond');
      expect(doc.recipientContact, 'Julien Remond');
      expect(doc.organisation, 'Care Direct');
    });

    test('blank invoice number and contact resolve to null', () {
      final doc = _doc(
        client: _client(contactName: '   '),
        entries: [_entry()],
        invoiceNumber: '  ',
      );
      expect(doc.invoiceNumber, isNull);
      expect(doc.attention, isNull);
      expect(doc.recipientContact, isNull);
    });
  });

  group('buyer address + tax number', () {
    test('client address and ABN carry into the document', () {
      final doc = _doc(
        client: _client(
          address: '10 Sample St, Sydney NSW 2000',
          abn: '12 345 678 901',
        ),
        entries: [_entry()],
      );
      expect(doc.recipientAddress, '10 Sample St, Sydney NSW 2000');
      expect(doc.recipientAbn, '12 345 678 901');
    });

    test('blank/absent buyer address and ABN resolve to null', () {
      final doc = _doc(
        client: _client(address: '   ', abn: null),
        entries: [_entry()],
      );
      expect(doc.recipientAddress, isNull);
      expect(doc.recipientAbn, isNull);
    });
  });

  group('payment fields + sender identity', () {
    test('sender address carries through from the profile', () {
      final doc = _doc(
        profile: _profile(address: '12 Wallaby Way, Sydney'),
        entries: [_entry()],
      );
      expect(doc.senderAddress, '12 Wallaby Way, Sydney');
    });

    test('AU paymentFields: NAME, region ids (BSB/account/SWIFT), ABN, BANK — '
        'incl. BSB + account (the previously-unrendered P0 fields)', () {
      final doc = _doc(
        profile: _profile(
          region: InvoiceRegion.au,
          payeeName: 'tmox Pty Ltd',
          bankBsb: '062-000',
          bankAccount: '12345678',
          abn: '12 345 678 901',
          swift: 'CTBAAU2S',
          bankName: 'Commonwealth Bank',
        ),
        entries: [_entry()],
      );
      expect(doc.paymentFields, [
        ('NAME', 'tmox Pty Ltd'),
        ('BSB', '062-000'),
        ('ACCOUNT', '12345678'),
        ('SWIFT/BIC', 'CTBAAU2S'),
        ('ABN', '12 345 678 901'), // sender tax ID, region-labelled
        ('BANK', 'Commonwealth Bank'),
      ]);
    });

    test('blank/absent bank fields are dropped from paymentFields', () {
      final doc = _doc(
        profile: _profile(
          payeeName: 'tmox Pty Ltd',
          bankBsb: '   ', // blank → dropped
          bankAccount: '12345678',
        ),
        entries: [_entry()],
      );
      expect(doc.paymentFields, [
        ('NAME', 'tmox Pty Ltd'),
        ('ACCOUNT', '12345678'),
      ]);
    });

    test('no bank details → paymentFields is empty', () {
      expect(_doc(entries: [_entry()]).paymentFields, isEmpty);
    });

    test('EU shows IBAN + BIC (no BSB/account), region-labelled tax ID', () {
      final doc = _doc(
        profile: _profile(
          region: InvoiceRegion.eu,
          payeeName: 'Studio GmbH',
          iban: 'DE89370400440532013000',
          swift: 'COBADEFFXXX',
          bankBsb: '062-000', // present but NOT in EU's field set → omitted
          abn: 'DE123456789',
        ),
        entries: [_entry()],
      );
      expect(doc.paymentFields, [
        ('NAME', 'Studio GmbH'),
        ('IBAN', 'DE89370400440532013000'),
        ('SWIFT/BIC', 'COBADEFFXXX'),
        ('VAT NO.', 'DE123456789'),
      ]);
    });

    test('US shows routing + account + SWIFT/BIC (for wires) + ACH/wire note', () {
      final doc = _doc(
        profile: _profile(
          region: InvoiceRegion.us,
          payeeName: 'Acme LLC',
          routingNumber: '021000021',
          bankAccount: '000123456789',
          swift: 'CMFGUS33', // needed for the international wire the note offers
        ),
        entries: [_entry()],
      );
      expect(doc.paymentFields, [
        ('NAME', 'Acme LLC'),
        ('ROUTING (ABA)', '021000021'),
        ('ACCOUNT', '000123456789'),
        ('SWIFT/BIC', 'CMFGUS33'),
      ]);
      expect(doc.region.paymentNote, contains('ACH'));
    });

    test('UK shows sort code + account + IBAN + BIC', () {
      final doc = _doc(
        profile: _profile(
          region: InvoiceRegion.uk,
          payeeName: 'Ltd Co',
          sortCode: '20-30-40',
          bankAccount: '12345678',
          iban: 'GB33BUKB20201555555555',
          swift: 'BUKBGB22',
        ),
        entries: [_entry()],
      );
      expect(doc.paymentFields, [
        ('NAME', 'Ltd Co'),
        ('SORT CODE', '20-30-40'),
        ('ACCOUNT', '12345678'),
        ('IBAN', 'GB33BUKB20201555555555'),
        ('SWIFT/BIC', 'BUKBGB22'),
      ]);
    });
  });

  group('region → title + buyer tax-ID label', () {
    test('AU with tax → "Tax Invoice"; buyer label "ABN"', () {
      final doc = _doc(
        profile: _profile(
          region: InvoiceRegion.au,
          taxLabel: 'GST',
          taxRate: 10,
        ),
        entries: [_entry()],
      );
      expect(doc.region, InvoiceRegion.au);
      expect(doc.title, 'Tax Invoice');
      expect(doc.recipientAbnLabel, 'ABN');
    });

    test('AU without tax → plain "Invoice"', () {
      final doc = _doc(
        profile: _profile(region: InvoiceRegion.au), // no tax label/rate
        entries: [_entry()],
      );
      expect(doc.title, 'Invoice');
    });

    test('UK → "Invoice"; buyer label "VAT NO." even when taxed', () {
      final doc = _doc(
        profile: _profile(
          region: InvoiceRegion.uk,
          taxLabel: 'VAT',
          taxRate: 20,
        ),
        entries: [_entry()],
      );
      expect(doc.title, 'Invoice');
      expect(doc.recipientAbnLabel, 'VAT NO.');
    });

    test('US → "Invoice"; buyer label "TAX NO."', () {
      final doc = _doc(
        profile: _profile(region: InvoiceRegion.us),
        entries: [_entry()],
      );
      expect(doc.title, 'Invoice');
      expect(doc.recipientAbnLabel, 'TAX NO.');
    });
  });

  group('inclusion flags (deliberate omission)', () {
    InvoiceProfile bankedTaxed() => _profile(
      taxLabel: 'GST',
      taxRate: 10,
      payeeName: 'tmox',
      bankBsb: '062-000',
      bankAccount: '12345678',
      paymentLink: 'https://pay.me/x',
    );

    test('profile defaults drive inclusion when no override', () {
      final doc = _doc(
        profile: bankedTaxed(),
        entries: [_entry(seconds: 3600)],
      );
      expect(doc.showBank, isTrue);
      expect(doc.showPaymentLink, isTrue);
      expect(doc.tax, isNotNull);
    });

    test('showTax off (profile default) removes the tax line AND its amount',
        () {
      final doc = _doc(
        profile: bankedTaxed().copyWith(showTax: false),
        entries: [_entry(seconds: 3600)], // subtotal 46
      );
      expect(doc.tax, isNull);
      expect(doc.total, closeTo(46, 1e-9)); // no GST added
    });

    test('per-invoice override beats the profile default', () {
      final profile = bankedTaxed(); // all show* true
      final doc = _doc(
        profile: profile,
        entries: [_entry(seconds: 3600)],
        showBank: false,
        showPaymentLink: false,
        showTax: false,
      );
      expect(doc.showBank, isFalse);
      expect(doc.showPaymentLink, isFalse);
      expect(doc.tax, isNull);
    });

    test('override can also turn a block back ON over a false default', () {
      final doc = _doc(
        profile: bankedTaxed().copyWith(showBank: false),
        entries: [_entry()],
        showBank: true,
      );
      expect(doc.showBank, isTrue);
    });
  });

  group('reverse charge (EU/UK B2B)', () {
    test('UK reverse charge suppresses the VAT amount + sets the flag', () {
      final doc = _doc(
        profile: _profile(
          region: InvoiceRegion.uk,
          taxLabel: 'VAT',
          taxRate: 20,
          reverseCharge: true,
        ),
        entries: [_entry(seconds: 3600)], // subtotal 46
      );
      expect(doc.reverseCharge, isTrue);
      expect(doc.tax, isNull); // customer accounts for VAT
      expect(doc.total, closeTo(46, 1e-9)); // no VAT added
    });

    test('EU reverse charge also applies', () {
      final doc = _doc(
        profile: _profile(
          region: InvoiceRegion.eu,
          taxLabel: 'VAT',
          taxRate: 21,
          reverseCharge: true,
        ),
        entries: [_entry()],
      );
      expect(doc.reverseCharge, isTrue);
      expect(doc.tax, isNull);
    });

    test('reverse charge is ignored outside EU/UK (region-gated)', () {
      final doc = _doc(
        profile: _profile(
          region: InvoiceRegion.au,
          taxLabel: 'GST',
          taxRate: 10,
          reverseCharge: true, // set, but AU doesn't support it
        ),
        entries: [_entry(seconds: 3600)],
      );
      expect(doc.reverseCharge, isFalse);
      expect(doc.tax, isNotNull); // GST still applies
    });

    test('reverse-charge statement is the fixed, non-substitutable wording', () {
      expect(
        InvoiceDocument.reverseChargeStatement,
        contains('Reverse charge'),
      );
    });
  });
}
