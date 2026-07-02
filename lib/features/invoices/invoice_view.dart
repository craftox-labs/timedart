import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/invoices/invoice_pdf.dart';

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
  late Future<JobInvoice> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: DateTime(now.year, now.month), end: now);
    _load();
  }

  void _load() {
    _future = widget.db.jobInvoice(
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

  Future<void> _exportPdf(JobInvoice inv) async {
    try {
      final safe = inv.job.code.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      // Let the user choose where to save (native file dialog).
      final location = await getSaveLocation(
        suggestedName: 'invoice_$safe.pdf',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PDF', extensions: ['pdf']),
        ],
      );
      if (location == null) return; // cancelled

      final bytes = await buildInvoicePdf(
        inv: inv,
        from: _range.start,
        to: _range.end,
      );
      await File(location.path).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to ${location.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export PDF: $e')),
        );
      }
    }
  }

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
  String _fmtHours(int seconds) => (seconds / 3600).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invoice · ${widget.job.code} — ${widget.job.title}',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Row(
            children: [
              Text('${_fmtDate(_range.start)} – ${_fmtDate(_range.end)}'),
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
            child: FutureBuilder<JobInvoice>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final inv = snap.data!;
                if (inv.entries.isEmpty) {
                  return const Center(
                    child: Text('No tracked time in this period.'),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (inv.rate == null)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppTokens.spaceXs,
                        ),
                        child: Text(
                          'No rate set for this job or its client — amounts unavailable.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final e in inv.entries)
                            ListTile(
                              dense: true,
                              title: Text(e.task),
                              subtitle: Text(_fmtDate(e.startedAt)),
                              trailing: Text(
                                '${_fmtHours(e.seconds)} h'
                                '${inv.rate == null ? '' : ' · \$${((e.seconds / 3600) * inv.rate!).toStringAsFixed(2)}'}',
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.spaceMd,
                        vertical: AppTokens.spaceXs,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total (${_fmtHours(inv.totalSeconds)} h)',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            inv.total == null
                                ? '—'
                                : '\$${inv.total!.toStringAsFixed(2)}',
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
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
                          onPressed: () => _exportPdf(inv),
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
      ),
    );
  }
}
