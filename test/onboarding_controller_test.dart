import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/invoices/invoice_region.dart';
import 'package:timedart/features/onboarding/onboarding_controller.dart';

// Coverage for the onboarding→persistence wiring (PRD #133, phase c): finishing
// applies the captured inputs to the seeded DEFAULT profile (no duplicate) and
// sets the onboarding-complete flag. Runs against an in-memory DB.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  test(
    'applyOnboarding edits the default profile in place and sets the flag',
    () async {
      // Precondition: fresh install → not complete, no profiles yet.
      expect(await db.isOnboardingComplete(), isFalse);

      final logo = Uint8List.fromList([9, 8, 7]);
      await applyOnboarding(
        db,
        OnboardingInputs(
          businessName: 'Acme Pty Ltd',
          logo: logo,
          logoMime: 'image/png',
          email: 'hi@acme.example',
          region: InvoiceRegion.au,
        ),
      );

      // Still exactly one profile — the seeded default, edited in place.
      final profiles = await db.select(db.profiles).get();
      expect(profiles.length, 1);
      final p = profiles.single;
      expect(p.isDefault, isTrue);
      expect(p.businessName, 'Acme Pty Ltd');
      expect(p.email, 'hi@acme.example');
      expect(p.logo, logo);
      expect(p.region, 'au');
      expect(p.currency, 'AUD');
      expect(p.taxLabel, 'GST');

      expect(await db.isOnboardingComplete(), isTrue);
    },
  );

  test(
    'skipping everything keeps the seeded defaults but still completes',
    () async {
      await applyOnboarding(db, OnboardingInputs.empty);

      final p = (await db.defaultProfile())!;
      // ensureInvoiceDefaults seeds these — onboarding left them untouched.
      expect(p.businessName, 'Your Business');
      expect(p.currency, 'USD');
      expect(await db.isOnboardingComplete(), isTrue);
    },
  );
}
