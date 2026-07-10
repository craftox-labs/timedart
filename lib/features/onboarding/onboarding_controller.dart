import 'dart:typed_data';

import 'package:timedart/data/database.dart';
import 'package:timedart/features/invoices/invoice_region.dart';
import 'package:timedart/features/onboarding/onboarding_mapping.dart';

// The onboarding→persistence wiring (PRD #133, phase c). Sits between the
// wizard UI (which collects [OnboardingInputs]) and the data layer: it maps the
// inputs onto the seeded DEFAULT profile and flips the onboarding-complete flag.
// Kept out of the widgets so it's testable against an in-memory database.

/// Everything the fast-track can capture. Every field is optional: a skipped
/// step leaves its value null, which the mapping treats as "keep the seeded
/// default". [empty] is the all-skipped case (finish with nothing captured).
class OnboardingInputs {
  const OnboardingInputs({
    this.businessName,
    this.logo,
    this.logoMime,
    this.email,
    this.region,
  });

  final String? businessName;
  final Uint8List? logo;
  final String? logoMime;
  final String? email;
  final InvoiceRegion? region;

  static const empty = OnboardingInputs();
}

/// Finish onboarding: ensure the defaults exist, apply the captured [inputs] to
/// the default profile (no duplicate — [onboardingProfileUpdate] leaves skipped
/// fields untouched), then mark onboarding complete. Idempotent seeding makes
/// this safe even though [AdaptiveShell] also seeds.
Future<void> applyOnboarding(AppDatabase db, OnboardingInputs inputs) async {
  await db.ensureInvoiceDefaults();
  final profile = await db.defaultProfile();
  if (profile != null) {
    await db.updateProfileById(
      profile.id,
      onboardingProfileUpdate(
        businessName: inputs.businessName,
        logo: inputs.logo,
        logoMime: inputs.logoMime,
        email: inputs.email,
        region: inputs.region,
      ),
    );
  }
  await db.setOnboardingComplete();
}
