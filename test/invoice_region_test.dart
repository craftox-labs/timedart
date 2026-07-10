import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/features/invoices/invoice_region.dart';

// The region resolver is the compliance guard: each region's tax label, buyer
// tax-ID label, and invoice-title rule are pinned here as fixtures so a change
// to a convention is a deliberate, reviewed edit — not something you have to
// remember region by region.

void main() {
  group('default tax label', () {
    test('per region', () {
      expect(InvoiceRegion.au.defaultTaxLabel, 'GST');
      expect(InvoiceRegion.uk.defaultTaxLabel, 'VAT');
      expect(InvoiceRegion.eu.defaultTaxLabel, 'VAT');
      expect(InvoiceRegion.ca.defaultTaxLabel, 'GST/HST');
      expect(InvoiceRegion.us.defaultTaxLabel, isNull); // no sales tax on services
      expect(InvoiceRegion.other.defaultTaxLabel, isNull);
    });
  });

  group('default currency', () {
    test('per region; Other has none', () {
      expect(InvoiceRegion.au.defaultCurrency, 'AUD');
      expect(InvoiceRegion.uk.defaultCurrency, 'GBP');
      expect(InvoiceRegion.eu.defaultCurrency, 'EUR');
      expect(InvoiceRegion.us.defaultCurrency, 'USD');
      expect(InvoiceRegion.ca.defaultCurrency, 'CAD');
      expect(InvoiceRegion.other.defaultCurrency, isNull);
    });
  });

  group('buyer tax-ID label', () {
    test('per region', () {
      expect(InvoiceRegion.au.buyerTaxIdLabel, 'ABN');
      expect(InvoiceRegion.uk.buyerTaxIdLabel, 'VAT NO.');
      expect(InvoiceRegion.eu.buyerTaxIdLabel, 'VAT NO.');
      expect(InvoiceRegion.ca.buyerTaxIdLabel, 'GST NO.');
      expect(InvoiceRegion.us.buyerTaxIdLabel, 'TAX NO.');
      expect(InvoiceRegion.other.buyerTaxIdLabel, 'TAX NO.');
    });
  });

  group('invoice title', () {
    test('only AU with tax is a "Tax Invoice"', () {
      expect(InvoiceRegion.au.invoiceTitle(hasTax: true), 'Tax Invoice');
      expect(InvoiceRegion.au.invoiceTitle(hasTax: false), 'Invoice');
    });

    test('every non-AU region is a plain "Invoice" regardless of tax', () {
      for (final r in InvoiceRegion.values.where((r) => r != InvoiceRegion.au)) {
        expect(r.invoiceTitle(hasTax: true), 'Invoice', reason: r.name);
        expect(r.invoiceTitle(hasTax: false), 'Invoice', reason: r.name);
      }
    });
  });

  group('organisationLabel', () {
    test('US uses the z-spelling; every other region uses the s', () {
      expect(InvoiceRegion.us.organisationLabel, 'ORGANIZATION');
      for (final r in InvoiceRegion.values) {
        if (r == InvoiceRegion.us) continue;
        expect(r.organisationLabel, 'ORGANISATION', reason: r.name);
      }
    });
  });

  group('fromName', () {
    test('round-trips every region name', () {
      for (final r in InvoiceRegion.values) {
        expect(InvoiceRegion.fromName(r.name), r);
      }
    });

    test('unknown or null → other (never crashes a render)', () {
      expect(InvoiceRegion.fromName(null), InvoiceRegion.other);
      expect(InvoiceRegion.fromName(''), InvoiceRegion.other);
      expect(InvoiceRegion.fromName('atlantis'), InvoiceRegion.other);
    });
  });
}
