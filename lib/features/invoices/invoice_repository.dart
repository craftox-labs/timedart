import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/invoices/invoice_document.dart';

/// Bridges the data layer and the pure [buildInvoiceDocument]: fetches the rows
/// for a job's invoice over a period plus the branding from the default
/// [InvoiceTemplate], and assembles a document + its theme. Lives in the feature
/// layer (it may depend on both `data` and the pure builder); the data layer
/// stays ignorant of invoice view-models.
///
/// Returns null when there's no default template (shouldn't happen after
/// [AppDatabase.ensureInvoiceDefaults], but callers handle it gracefully).
Future<({InvoiceDocument doc, InvoiceTheme theme})?> loadInvoiceDocument(
  AppDatabase db, {
  required int jobId,
  required DateTime from,
  required DateTime to,
  required DateTime issueDate,
  String? invoiceNumber,
}) async {
  final template = await db.defaultTemplate();
  if (template == null) return null;
  final profile = await db.profileById(template.profileId);
  final theme = await db.themeById(template.themeId);
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
  return (doc: doc, theme: theme);
}
