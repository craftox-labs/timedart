import 'package:timedart/data/database.dart';
import 'package:timedart/features/invoices/invoice_document.dart';

/// Bridges the data layer and the pure [buildInvoiceDocument]: fetches the rows
/// for a project's invoice over a period plus the branding — the default
/// [InvoiceProfile] and an [InvoiceTemplate] — and assembles a document + its
/// template. Lives in the feature layer (it may depend on both `data` and the
/// pure builder); the data layer stays ignorant of invoice view-models.
///
/// [profileId] overrides which profile to invoice with (the export-time picker);
/// when null the default profile is used. The template (visual style) follows
/// from the chosen profile, falling back to the default template. Returns null
/// when there's no profile or template (shouldn't happen after
/// [AppDatabase.ensureInvoiceDefaults], but callers handle it).
Future<({InvoiceDocument doc, InvoiceTemplate template})?> loadInvoiceDocument(
  AppDatabase db, {
  required int projectId,
  required DateTime from,
  required DateTime to,
  required DateTime issueDate,
  int? profileId,
  String? invoiceNumber,
  // Per-invoice inclusion overrides (null → the profile's stored default).
  bool? showBank,
  bool? showPaymentLink,
  bool? showTax,
}) async {
  final profile =
      profileId != null ? await db.profileById(profileId) : await db.defaultProfile();
  if (profile == null) return null;
  final template = profile.templateId != null
      ? await db.templateById(profile.templateId!)
      : await db.defaultTemplate();
  if (template == null) return null;
  final project = await db.getProject(projectId);
  final client = await db.getClient(project.clientId);
  final tasks = await db.tasksForProject(projectId);
  final entries = await db.entriesForProjectInPeriod(projectId, from, to);

  final doc = buildInvoiceDocument(
    profile: profile,
    project: project,
    client: client,
    tasks: tasks,
    entries: entries,
    from: from,
    to: to,
    issueDate: issueDate,
    invoiceNumber: invoiceNumber,
    showBank: showBank,
    showPaymentLink: showPaymentLink,
    showTax: showTax,
  );
  return (doc: doc, template: template);
}
