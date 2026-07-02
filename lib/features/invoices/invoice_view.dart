import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/invoices/invoice_pdf.dart';

/// Read-only invoice builder for one client: pick a date range, preview the
/// aggregated lines, export a PDF. Generates on demand — stores nothing.
class InvoiceView extends StatefulWidget {
  const InvoiceView({
    super.key,
    required this.db,
    required this.client,
    required this.onDone,
  });
  final AppDatabase db;
  final Client client;
  final VoidCallback onDone;

  @override
  State<InvoiceView> createState() => _InvoiceViewState();
}

class _InvoiceViewState extends State<InvoiceView> {
  late DateTimeRange _range;
  late Future<List<InvoiceLine>> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Default to the current month, month-start through today.
    _range = DateTimeRange(start: DateTime(now.year, now.month), end: now);
    _load();
  }

  void _load() {
    _future = widget.db.invoiceLines(
      clientId: widget.client.id,
      from: _range.start,
      // include the whole end day
      to: DateTime(_range.end.year, _range.end.month, _range.end.day, 23, 59, 59),
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

  Future<void> _exportPdf(List<InvoiceLine> lines) async {
    final bytes = await buildInvoicePdf(
      client: widget.client,
      lines: lines,
      from: _range.start,
      to: _range.end,
    );
    // Opens the native print/preview dialog (save-as-PDF from there).
    await Printing.layoutPdf(onLayout: (_) => bytes);
  }

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';

  String _fmtHours(int seconds) => (seconds / 3600).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invoice · ${widget.client.name}', style: theme.textTheme.titleLarge),
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
            child: FutureBuilder<List<InvoiceLine>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final lines = snap.data ?? [];
                if (lines.isEmpty) {
                  return const Center(
                    child: Text('No tracked time in this period.'),
                  );
                }
                final total = lines
                    .where((l) => l.amount != null)
                    .fold<double>(0, (sum, l) => sum + l.amount!);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView(
                        children: [
                          for (final l in lines)
                            ListTile(
                              dense: true,
                              title: Text('${l.jobCode} · ${l.jobTitle}'),
                              subtitle: Text('${_fmtHours(l.seconds)} h'
                                  '${l.rate == null ? '' : ' @ \$${l.rate!.toStringAsFixed(2)}/hr'}'),
                              trailing: Text(
                                l.amount == null
                                    ? 'no rate'
                                    : '\$${l.amount!.toStringAsFixed(2)}',
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
                          Text('Total', style: theme.textTheme.titleMedium),
                          Text(
                            '\$${total.toStringAsFixed(2)}',
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
                          onPressed: () => _exportPdf(lines),
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
