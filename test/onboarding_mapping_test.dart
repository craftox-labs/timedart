import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/features/invoices/invoice_region.dart';
import 'package:timedart/features/onboarding/onboarding_mapping.dart';

// Pure-function coverage for the onboarding → default-profile mapping (PRD
// #133): captured inputs produce the expected ProfilesCompanion, region drives
// currency + tax label, and skipped/empty inputs stay `absent` so the seeded
// defaults are never clobbered.
void main() {
  test('full input sets business fields + region-derived currency/tax', () {
    final logo = Uint8List.fromList([1, 2, 3]);
    final c = onboardingProfileUpdate(
      businessName: 'Acme Pty Ltd',
      logo: logo,
      logoMime: 'image/png',
      email: 'hi@acme.example',
      region: InvoiceRegion.au,
    );
    expect(c.businessName.value, 'Acme Pty Ltd');
    expect(c.email.value, 'hi@acme.example');
    expect(c.logo.value, logo);
    expect(c.logoMime.value, 'image/png');
    expect(c.region.value, 'au');
    expect(c.currency.value, 'AUD');
    expect(c.taxLabel.value, 'GST');
  });

  test('text fields are trimmed', () {
    final c = onboardingProfileUpdate(
      businessName: '  Acme  ',
      email: '  a@b.co ',
      region: InvoiceRegion.uk,
    );
    expect(c.businessName.value, 'Acme');
    expect(c.email.value, 'a@b.co');
    expect(c.region.value, 'uk');
    expect(c.currency.value, 'GBP');
    expect(c.taxLabel.value, 'VAT');
  });

  test('empty/blank inputs stay absent (seeded defaults untouched)', () {
    final c = onboardingProfileUpdate(
      businessName: '   ',
      email: '',
      // no logo, no region
    );
    expect(c.businessName.present, isFalse);
    expect(c.email.present, isFalse);
    expect(c.logo.present, isFalse);
    expect(c.logoMime.present, isFalse);
    expect(c.region.present, isFalse);
    expect(c.currency.present, isFalse);
    expect(c.taxLabel.present, isFalse);
  });

  test('logo and mime are absent together when no logo chosen', () {
    // A stray mime without a logo must not null-out anything.
    final c = onboardingProfileUpdate(
      logoMime: 'image/png',
      region: InvoiceRegion.us,
    );
    expect(c.logo.present, isFalse);
    expect(c.logoMime.present, isFalse);
  });

  test(
    'US region: currency set, tax label explicitly null (no services tax)',
    () {
      final c = onboardingProfileUpdate(region: InvoiceRegion.us);
      expect(c.region.value, 'us');
      expect(c.currency.value, 'USD');
      expect(c.taxLabel.present, isTrue);
      expect(c.taxLabel.value, isNull);
    },
  );

  test('Other region: no default currency → currency stays absent', () {
    final c = onboardingProfileUpdate(region: InvoiceRegion.other);
    expect(c.region.value, 'other');
    expect(c.currency.present, isFalse); // seeded currency kept
    expect(c.taxLabel.present, isTrue);
    expect(c.taxLabel.value, isNull);
  });
}
