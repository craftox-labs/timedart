import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/features/invoices/invoice_document.dart';
import 'package:timedart/features/invoices/invoice_layout.dart';
import 'package:timedart/features/invoices/invoice_layout_plan.dart';
import 'package:timedart/features/invoices/invoice_region.dart';

// Golden coverage for the layout seam: assert the decisions InvoiceLayout.resolve
// makes for a document, so preview/PDF parity is checked here — not by exporting
// a PDF and eyeballing it. Constructs InvoiceDocument directly (no DB).

final _d = DateTime(2026, 6, 15);

InvoiceDocument _doc({
  String? invoiceNumber = 'INV-1',
  InvoiceRegion region = InvoiceRegion.au,
  Uint8List? logo,
  LogoFallback logoFallback = LogoFallback.none,
  String? senderEmail = 'me@co',
  String? senderPhone = '+61 400',
  String? senderWebsite = 'co.example',
  String? senderAddress = '1 Sender St',
  String? senderAbn = '11 111 111 111',
  String? attention = 'Alex',
  String organisation = 'Client Co',
  String? recipientAddress = '2 Client Rd',
  String? recipientAbn = '22 222 222 222',
  InvoiceTax? tax,
  bool reverseCharge = false,
  bool showBank = true,
  bool showPaymentLink = true,
  String? paymentLink = 'pay.example/x',
  String? payeeName = 'Payee',
  String? bankName = 'Big Bank',
  String? bankBsb = '062-000',
  String? bankAccount = '1234 5678',
}) => InvoiceDocument(
  invoiceNumber: invoiceNumber,
  issueDate: _d,
  periodFrom: _d,
  periodTo: _d,
  reference: 'REF',
  region: region,
  title: 'Invoice',
  businessName: 'Me Co',
  logo: logo,
  logoFallback: logoFallback,
  senderEmail: senderEmail,
  senderPhone: senderPhone,
  senderWebsite: senderWebsite,
  senderAddress: senderAddress,
  senderAbn: senderAbn,
  attention: attention,
  recipientContact: attention,
  organisation: organisation,
  recipientEmail: 'acct@client',
  recipientPhone: '+61 401',
  recipientAddress: recipientAddress,
  recipientAbn: recipientAbn,
  recipientAbnLabel: region.buyerTaxIdLabel,
  lines: const [],
  currency: 'AUD',
  tax: tax,
  showBank: showBank,
  showPaymentLink: showPaymentLink,
  reverseCharge: reverseCharge,
  payeeName: payeeName,
  bankName: bankName,
  bankBsb: bankBsb,
  bankAccount: bankAccount,
  swift: null,
  paymentLink: paymentLink,
);

void main() {
  group('recipient grid presence', () {
    test('AU with buyer tax id → tax cell and second row shown', () {
      final p = InvoiceLayout.resolve(_doc());
      expect(p.recipient.showTaxCell, isTrue);
      expect(p.recipient.showSecondRow, isTrue);
      expect(p.recipient.showAddress, isTrue);
    });

    test('no address, no tax id → second row collapses', () {
      final p = InvoiceLayout.resolve(
        _doc(recipientAddress: null, recipientAbn: null),
      );
      expect(p.recipient.showTaxCell, isFalse);
      expect(p.recipient.showAddress, isFalse);
      expect(p.recipient.showSecondRow, isFalse);
    });

    test('address only → second row shown, no tax cell', () {
      final p = InvoiceLayout.resolve(_doc(recipientAbn: null));
      expect(p.recipient.showSecondRow, isTrue);
      expect(p.recipient.showTaxCell, isFalse);
    });
  });

  group('totals: tax XOR reverse charge', () {
    test('tax present → tax row, no reverse charge', () {
      final p = InvoiceLayout.resolve(
        _doc(tax: const InvoiceTax(label: 'GST', rate: 10, amount: 5)),
      );
      expect(p.totals.showTaxRow, isTrue);
      expect(p.totals.showReverseCharge, isFalse);
    });

    test('EU reverse charge, no tax → reverse charge, no tax row', () {
      final p = InvoiceLayout.resolve(
        _doc(region: InvoiceRegion.eu, tax: null, reverseCharge: true),
      );
      expect(p.totals.showTaxRow, isFalse);
      expect(p.totals.showReverseCharge, isTrue);
    });

    test('never both, even if the upstream invariant breaks', () {
      final p = InvoiceLayout.resolve(
        _doc(
          region: InvoiceRegion.eu,
          tax: const InvoiceTax(label: 'VAT', rate: 20, amount: 4),
          reverseCharge: true,
        ),
      );
      expect(p.totals.showTaxRow && p.totals.showReverseCharge, isFalse);
    });
  });

  group('payments', () {
    test('bank fields chunk into rows of payColumns', () {
      final p = InvoiceLayout.resolve(_doc());
      expect(p.payments.rows, isNotEmpty);
      for (final row in p.payments.rows) {
        expect(row.length, lessThanOrEqualTo(InvoiceLayout.payColumns));
      }
      final flat = p.payments.rows.expand((r) => r).toList();
      expect(flat.length, greaterThan(0));
      // Chunking preserves order and count.
      expect(p.payments.visible, isTrue);
    });

    test('showBank off → no rows; block still visible via link', () {
      final p = InvoiceLayout.resolve(_doc(showBank: false));
      expect(p.payments.rows, isEmpty);
      expect(p.payments.showLink, isTrue);
      expect(p.payments.visible, isTrue);
    });

    test('blank link is not shown', () {
      final p = InvoiceLayout.resolve(_doc(paymentLink: '   '));
      expect(p.payments.showLink, isFalse);
    });

    test('no bank, no link → block hidden', () {
      final p = InvoiceLayout.resolve(_doc(showBank: false, paymentLink: null));
      expect(p.payments.visible, isFalse);
    });

    test('payment note gated on bank fields present (US has a note)', () {
      final usWithBank = InvoiceLayout.resolve(_doc(region: InvoiceRegion.us));
      final usNoBank = InvoiceLayout.resolve(
        _doc(region: InvoiceRegion.us, showBank: false),
      );
      expect(usWithBank.payments.showPaymentNote, isTrue);
      expect(usNoBank.payments.showPaymentNote, isFalse);
      // AU has no payment note regardless of bank fields.
      expect(InvoiceLayout.resolve(_doc()).payments.showPaymentNote, isFalse);
    });
  });

  group('masthead', () {
    test('logo bytes → image slot', () {
      final p = InvoiceLayout.resolve(_doc(logo: Uint8List.fromList([1, 2, 3])));
      expect(p.masthead.logo.slot, LogoSlot.image);
      expect(p.masthead.logo.image, isNotNull);
    });

    test('fallbacks resolve to their slots', () {
      expect(
        InvoiceLayout.resolve(_doc(logoFallback: LogoFallback.brand))
            .masthead.logo.slot,
        LogoSlot.brandMark,
      );
      expect(
        InvoiceLayout.resolve(_doc(logoFallback: LogoFallback.placeholder))
            .masthead.logo.slot,
        LogoSlot.placeholder,
      );
      expect(
        InvoiceLayout.resolve(_doc(logoFallback: LogoFallback.none))
            .masthead.logo.slot,
        LogoSlot.none,
      );
    });

    test('contact spans in e./t./w. order, empties dropped', () {
      final p = InvoiceLayout.resolve(_doc(senderPhone: null));
      expect(p.masthead.contact.map((c) => c.prefix), ['e.', 'w.']);
      expect(p.masthead.showAddress, isTrue);
    });
  });

  group('party + geometry', () {
    test('att falls back to organisation', () {
      final p = InvoiceLayout.resolve(_doc(attention: null));
      expect(p.party.attValue, 'Client Co');
      expect(p.party.showInvoiceNumber, isTrue);
    });

    test('geometry resolves the recipient quarter once', () {
      final p = InvoiceLayout.resolve(_doc());
      expect(p.geometry.recipientQuarter, InvoiceLayout.recipientCol);
      expect(p.geometry.attColWidth, 2 * InvoiceLayout.recipientCol);
    });
  });
}
