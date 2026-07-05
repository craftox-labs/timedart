import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/invoices/invoice_document.dart';

/// Bridges the data layer and the pure [buildInvoiceDocument]: fetches the rows
/// for a job's invoice over a period plus the branding — the default
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
  required int jobId,
  required DateTime from,
  required DateTime to,
  required DateTime issueDate,
  int? profileId,
  String? invoiceNumber,
}) async {
  final profile =
      profileId != null ? await db.profileById(profileId) : await db.defaultProfile();
  if (profile == null) return null;
  final template = profile.templateId != null
      ? await db.templateById(profile.templateId!)
      : await db.defaultTemplate();
  if (template == null) return null;
  final job = await db.getJob(jobId);
  final client = await db.getClient(job.clientId);
  final tasks = await db.tasksForJob(jobId);
  final entries = await db.entriesForJobInPeriod(jobId, from, to);

  final doc = buildInvoiceDocument(
    profile: profile,
    job: job,
    client: client,
    tasks: tasks,
    entries: entries,
    from: from,
    to: to,
    issueDate: issueDate,
    invoiceNumber: invoiceNumber,
  );
  return (doc: doc, template: template);
}
