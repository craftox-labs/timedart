import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/invoices/invoice_document.dart';
import 'package:time_tracker/features/invoices/invoice_pdf.dart';
import 'package:time_tracker/features/invoices/invoice_preview.dart';
import 'package:time_tracker/features/invoices/invoice_repository.dart';

/// Read-only invoice builder for one job: pick a date range, preview the
/// itemised entries, export a PDF. Generates on demand — stores nothing.
class InvoiceView extends StatefulWidget {
  const InvoiceView({
    super.key,
    required this.db,
    required this.job,
    required this.onDone,
  });
  final AppDatabase db;
  final Job job;
  final VoidCallback onDone;

  @override
  State<InvoiceView> createState() => _InvoiceViewState();
}

class _InvoiceViewState extends State<InvoiceView> {
  late DateTimeRange _range;
  late Future<({InvoiceDocument doc, InvoiceTemplate template})?> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: DateTime(now.year, now.month), end: now);
    _load();
  }

  void _load() {
    _future = loadInvoiceDocument(
      widget.db,
      jobId: widget.job.id,
      from: _range.start,
      to: DateTime(
        _range.end.year,
        _range.end.month,
        _range.end.day,
        23,
        59,
        59,
      ),
      issueDate: DateTime.now(),
    );
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() {
        _range = picked;
        _load();
      });
    }
  }

  Future<void> _exportPdf() async {
    try {
      final safe = widget.job.code.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      // Let the user choose where to save (native file dialog).
      final location = await getSaveLocation(
        suggestedName: 'invoice_$safe.pdf',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PDF', extensions: ['pdf']),
        ],
      );
      if (location == null) return; // cancelled

      // Build the branded document from the default template (#84 adds template
      // selection + a manual invoice number; issue date is today for now).
      final loaded = await loadInvoiceDocument(
        widget.db,
        jobId: widget.job.id,
        from: _range.start,
        to: DateTime(
          _range.end.year,
          _range.end.month,
          _range.end.day,
          23,
          59,
          59,
        ),
        issueDate: DateTime.now(),
      );
      if (loaded == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No invoice template configured.')),
          );
        }
        return;
      }

      final bytes = await buildBrandedInvoicePdf(
        doc: loaded.doc,
        template: loaded.template,
      );
      await File(location.path).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to ${location.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not export PDF: $e')));
      }
    }
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Invoice · ${widget.job.code} — ${widget.job.title}',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppTokens.spaceXs),
        Row(
          children: [
            // Flexible so a narrow content pane ellipsizes the date range
            // instead of overflowing the row.
            Flexible(
              child: Text(
                '${_fmtDate(_range.start)} – ${_fmtDate(_range.end)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            TextButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range, size: AppTokens.iconSm),
              label: const Text('Change dates'),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Expanded(
          child: FutureBuilder<({InvoiceDocument doc, InvoiceTemplate template})?>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              final loaded = snap.data;
              if (loaded == null) {
                return const Center(
                  child: Text('No invoice template configured.'),
                );
              }
              final doc = loaded.doc;
              final empty = doc.lines.isEmpty;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: brandingPreviewFrame(
                      child: empty
                          ? const Center(
                              child: Text('No tracked time in this period.'),
                            )
                          : invoicePreviewPage(
                              doc: doc,
                              template: loaded.template,
                            ),
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  Row(
                    children: [
                      const Spacer(),
                      OutlinedButton(
                        onPressed: widget.onDone,
                        child: const Text('Close'),
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                      FilledButton.icon(
                        onPressed: empty ? null : _exportPdf,
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Export PDF'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
