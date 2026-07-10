import 'package:drift/drift.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/invoices/invoice_region.dart';

// Maps the onboarding fast-track's captured inputs onto the seeded DEFAULT
// profile (PRD #133). Pure function — no DB access — so it's unit-testable and
// the root gate just applies the result via `updateProfileById(defaultId, …)`,
// creating no duplicate profile.
//
// The governing rule: skipped/empty inputs leave the seeded defaults untouched
// (an absent [Value] means "don't write this column"). Region — a single pick —
// drives currency and tax label the same way the profile editor does: the
// region's default currency fills the field (unless the region has none, in
// which case the seeded currency stays), and the region's default tax label is
// applied (null for US/Other, i.e. no sales tax on services).

/// Build the [ProfilesCompanion] update for the captured onboarding inputs.
/// Every argument is optional: a null/blank text field, an unset logo, or a
/// null [region] (the step was skipped) leaves that column at its seeded value.
ProfilesCompanion onboardingProfileUpdate({
  String? businessName,
  Uint8List? logo,
  String? logoMime,
  String? email,
  InvoiceRegion? region,
}) {
  // A trimmed value, or absent when empty — so a blank field never overwrites a
  // seeded default with an empty string.
  Value<String> textOrKeep(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? const Value.absent() : Value(t);
  }

  return ProfilesCompanion(
    businessName: textOrKeep(businessName),
    // Logo + its mime move together: set both when a logo was chosen, else
    // leave both untouched (never null out an existing logo on skip).
    logo: logo == null ? const Value.absent() : Value(logo),
    logoMime: logo == null ? const Value.absent() : Value(logoMime),
    email: textOrKeep(email),
    // Region step skipped → leave region/currency/taxLabel as seeded.
    region: region == null ? const Value.absent() : Value(region.name),
    // Fill the region's default currency; a region without one (Other) keeps
    // the seeded currency rather than blanking a required field.
    currency: region?.defaultCurrency == null
        ? const Value.absent()
        : Value(region!.defaultCurrency!),
    // The region determines the tax label outright: a real label (GST/VAT/…)
    // or null for regions with no default services tax (US/Other).
    taxLabel: region == null
        ? const Value.absent()
        : Value(region.defaultTaxLabel),
  );
}
