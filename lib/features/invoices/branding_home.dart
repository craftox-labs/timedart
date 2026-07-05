import 'package:flutter/material.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/invoices/invoice_document.dart';
import 'package:time_tracker/features/invoices/invoice_preview.dart';

/// The Branding-mode content pane: a live preview of how invoices look, driven
/// by the template/profile picked in the side panel. When nothing is picked it
/// falls back to the default template + profile. This is the preview surface the
/// template/profile editors build on (they add the form beside it).
class BrandingHome extends StatelessWidget {
  const BrandingHome({
    super.key,
    required this.db,
    this.selectedTemplateId,
    this.selectedProfileId,
  });

  final AppDatabase db;
  final int? selectedTemplateId; // null → the default template
  final int? selectedProfileId; // null → the default profile

  static T? _pick<T>(
    List<T> items,
    int? id,
    int Function(T) idOf,
    bool Function(T) isDefault,
  ) {
    if (items.isEmpty) return null;
    if (id != null) {
      for (final it in items) {
        if (idOf(it) == id) return it;
      }
    }
    for (final it in items) {
      if (isDefault(it)) return it;
    }
    return items.first;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Branding', style: t.textTheme.titleLarge),
        const SizedBox(height: AppTokens.spaceXs),
        Text(
          'Preview updates as you pick a template or profile.',
          style: t.textTheme.bodySmall,
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Expanded(
          child: StreamBuilder<List<InvoiceTemplate>>(
            stream: db.watchTemplates(),
            builder: (context, templateSnap) {
              return StreamBuilder<List<InvoiceProfile>>(
                stream: db.watchProfiles(),
                builder: (context, profileSnap) {
                  final templates = templateSnap.data;
                  final profiles = profileSnap.data;
                  if (templates == null || profiles == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final template = _pick(
                    templates,
                    selectedTemplateId,
                    (x) => x.id,
                    (x) => x.isDefault,
                  );
                  final profile = _pick(
                    profiles,
                    selectedProfileId,
                    (x) => x.id,
                    (x) => x.isDefault,
                  );
                  if (template == null || profile == null) {
                    return const Center(
                      child: Text('No branding configured yet.'),
                    );
                  }
                  final doc = sampleInvoiceDocument(
                    profile: profile,
                    issueDate: DateTime.now(),
                  );
                  return brandingPreviewFrame(
                    child: invoicePreviewPage(doc: doc, template: template),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
