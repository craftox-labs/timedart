import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/features/invoices/invoice_fonts.dart';

// The invoice font registry is the single source of truth shared by the picker,
// the on-screen preview, and the PDF renderer. These fixtures pin the five
// bundled families, the resolve() fallback, and the invariant that every family
// carries three real weight assets — so a broken or missing weight is a
// deliberate, reviewed edit rather than a silent runtime asset-load failure.

void main() {
  group('registry', () {
    test('exposes the six curated families in picker order', () {
      expect(invoiceFontFamilies, [
        'Outfit',
        'IBM Plex Sans',
        'Libre Franklin',
        'Source Serif 4',
        'Spectral',
        'Plus Jakarta Sans',
      ]);
      // Outfit (the default) leads the picker.
      expect(invoiceFontFamilies.first, defaultInvoiceFontFamily);
    });

    test('every family has three non-empty, distinct weight assets', () {
      for (final entry in invoiceFonts.entries) {
        final f = entry.value;
        final assets = [
          f.pdfRegularAsset,
          f.pdfMediumAsset,
          f.pdfSemiBoldAsset,
        ];
        for (final a in assets) {
          expect(a, isNotEmpty, reason: '${entry.key} has an empty asset path');
          expect(
            a,
            startsWith('assets/fonts/'),
            reason: '${entry.key} asset must live under assets/fonts/',
          );
          expect(
            a,
            endsWith('.ttf'),
            reason: '${entry.key} asset must be a ttf',
          );
        }
        // The three weights map to three different files.
        expect(
          assets.toSet(),
          hasLength(3),
          reason: '${entry.key} has a duplicate weight asset',
        );
        expect(f.flutterFamily, isNotEmpty);
      }
    });

    test('display key matches flutterFamily for every family', () {
      for (final entry in invoiceFonts.entries) {
        expect(entry.value.flutterFamily, entry.key);
      }
    });
  });

  group('resolve', () {
    test('returns the exact entry for a known family', () {
      final ibm = resolveInvoiceFont('IBM Plex Sans');
      expect(ibm.flutterFamily, 'IBM Plex Sans');
      expect(ibm.pdfRegularAsset, 'assets/fonts/IBMPlexSans-Regular.ttf');
      expect(ibm.pdfMediumAsset, 'assets/fonts/IBMPlexSans-Medium.ttf');
      expect(ibm.pdfSemiBoldAsset, 'assets/fonts/IBMPlexSans-SemiBold.ttf');
    });

    test('falls back to Outfit for null', () {
      expect(resolveInvoiceFont(null).flutterFamily, defaultInvoiceFontFamily);
    });

    test('falls back to Outfit for an unknown/legacy value', () {
      expect(
        resolveInvoiceFont('Mona').flutterFamily,
        defaultInvoiceFontFamily,
      );
      expect(resolveInvoiceFont('').flutterFamily, defaultInvoiceFontFamily);
      expect(
        resolveInvoiceFont('does-not-exist'),
        same(invoiceFonts[defaultInvoiceFontFamily]),
      );
    });
  });
}
