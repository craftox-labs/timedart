import 'dart:async';
import 'package:flutter/material.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/features/invoices/invoice_document.dart';
import 'package:timedart/features/invoices/invoice_pdf.dart';
import 'package:timedart/features/invoices/invoice_preview.dart';
import 'package:timedart/features/invoices/invoice_repository.dart';
import 'package:timedart/features/invoices/pdf_saver.dart';
import 'package:timedart/widgets/dropdown_field.dart';

/// Read-only invoice builder for one project: pick a date range, preview the
/// itemised entries, export a PDF. Generates on demand — stores nothing.
class InvoiceView extends StatefulWidget {
  const InvoiceView({
    super.key,
    required this.db,
    required this.project,
    required this.onDone,
  });
  final AppDatabase db;
  final Project project;
  final VoidCallback onDone;

  @override
  State<InvoiceView> createState() => _InvoiceViewState();
}

class _InvoiceViewState extends State<InvoiceView> {
  late DateTimeRange _range;
  late Future<({InvoiceDocument doc, InvoiceTemplate template})?> _future;
  // Export-time profile chosen on the fly (its details + template), no need to
  // change settings.
  List<InvoiceProfile> _profiles = const [];
  int? _profileId; // null → the default profile
  // Which blocks (bank/payment link/tax) appear is the selected profile's
  // concern — set once there, not per invoice.
  final _invoiceNumber = TextEditingController();
  // Last resolved doc+template, kept so a reload (e.g. typing an invoice number)
  // shows the previous preview instead of a spinner while the new one loads.
  ({InvoiceDocument doc, InvoiceTemplate template})? _last;
  // Watches the project + its joined client row so edits made elsewhere
  // (name, contact, rate, address, tax no., …) live-refresh the open preview
  // instead of needing a close/reopen (#138).
  StreamSubscription<(Project, Client)?>? _sourceSub;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: DateTime(now.year, now.month), end: now);
    _load();
    // Re-run _load() whenever the underlying project/client data changes.
    // The stream's initial emit is harmless — _last keeps the preview
    // flicker-free while the reload resolves.
    _sourceSub = widget.db.watchProjectWithClient(widget.project.id).listen((_) {
      if (!mounted) return;
      setState(_load);
    });
    // Populate the profile picker; default it to the default profile so the
    // dropdown reflects what renders, then reload so the preview matches.
    widget.db.watchProfiles().first.then((list) {
      if (!mounted) return;
      setState(() {
        _profiles = list;
        _profileId ??= _defaultProfileId(list);
        _load();
      });
    });
  }

  @override
  void dispose() {
    _sourceSub?.cancel();
    _invoiceNumber.dispose();
    super.dispose();
  }

  int? _defaultProfileId(List<InvoiceProfile> list) {
    for (final p in list) {
      if (p.isDefault) return p.id;
    }
    return list.isEmpty ? null : list.first.id;
  }

  String? get _invoiceNumberValue =>
      _invoiceNumber.text.trim().isEmpty ? null : _invoiceNumber.text.trim();

  void _load() {
    _future = loadInvoiceDocument(
      widget.db,
      projectId: widget.project.id,
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
      profileId: _profileId,
      invoiceNumber: _invoiceNumberValue,
      // showBank/showPaymentLink/showTax omitted → the profile's stored
      // defaults apply (loadInvoiceDocument: showX ?? profile.showX).
    );
  }

  // A self-contained range modal: two calendars (From / To) live in the dialog
  // itself, so the interactive picker never opens a separate full-screen page.
  Future<void> _pickRange() async {
    var start = _range.start;
    var end = _range.end;
    final first = DateTime(2000);
    final last = DateTime(2100);
    final wide = MediaQuery.sizeOf(context).width >= AppTokens.breakpointMd;

    Widget cal(String label, DateTime initial, ValueChanged<DateTime> onPick) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          SizedBox(
            width: 300,
            height: 320,
            child: CalendarDatePicker(
              initialDate: initial,
              firstDate: first,
              lastDate: last,
              onDateChanged: onPick,
            ),
          ),
        ],
      );
    }

    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invoice period'),
        content: SingleChildScrollView(
          child: wide
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    cal('From', start, (d) => start = d),
                    const SizedBox(width: AppTokens.spaceLg),
                    cal('To', end, (d) => end = d),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cal('From', start, (d) => start = d),
                    const SizedBox(height: AppTokens.spaceMd),
                    cal('To', end, (d) => end = d),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              // Normalise so From is never after To.
              start.isAfter(end)
                  ? DateTimeRange(start: end, end: start)
                  : DateTimeRange(start: start, end: end),
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
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
      final safe = widget.project.code.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

      // Build the branded document with the on-the-fly profile + invoice
      // number chosen above (issue date is today for now).
      final loaded = await loadInvoiceDocument(
        widget.db,
        projectId: widget.project.id,
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
        profileId: _profileId,
        invoiceNumber: _invoiceNumberValue,
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
      // Desktop prompts for a location and writes the file; web downloads it.
      final saved = await savePdf(bytes, 'invoice_$safe.pdf');
      if (saved == null) return; // cancelled (desktop only)
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved to $saved')));
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

  // Date range + Change dates, and the on-the-fly Profile + Invoice #. On
  // desktop they share one row with the branding right-aligned; on a narrow
  // pane they stack (date row above, template/number wrapping below).
  Widget _controls() {
    final dateText = Text(
      '${_fmtDate(_range.start)} – ${_fmtDate(_range.end)}',
      overflow: TextOverflow.ellipsis,
    );
    final changeDates = TextButton.icon(
      onPressed: _pickRange,
      icon: const Icon(Icons.date_range, size: AppTokens.iconSm),
      label: const Text('Change dates'),
    );
    final profileField = SizedBox(
      width: 220,
      child: DropdownButtonFormField<int>(
        initialValue: _profileId,
        isExpanded: true,
        icon: kDropdownChevron,
        decoration: const InputDecoration(labelText: 'Profile'),
        items: [
          for (final p in _profiles)
            DropdownMenuItem(value: p.id, child: Text(p.name)),
        ],
        onChanged: (v) => setState(() {
          _profileId = v;
          _load();
        }),
      ),
    );
    final invoiceField = SizedBox(
      width: 180,
      child: TextField(
        controller: _invoiceNumber,
        decoration: const InputDecoration(labelText: 'Invoice #'),
        // Live in the preview; _last keeps it flicker-free while loading.
        onChanged: (_) => setState(_load),
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= AppTokens.breakpointMd) {
          // Plain (not Flexible) date text: with only the Spacer taking the
          // slack, the branding fields sit flush against the right edge.
          return Row(
            children: [
              dateText,
              const SizedBox(width: AppTokens.spaceSm),
              changeDates,
              const Spacer(),
              profileField,
              const SizedBox(width: AppTokens.spaceSm),
              invoiceField,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(child: dateText),
                const SizedBox(width: AppTokens.spaceSm),
                changeDates,
              ],
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [profileField, invoiceField],
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Invoice" label keeps the Raleway italic titleLarge; the project
        // code/title drops to Mona (matching the editor "Template : name" split).
        Text.rich(
          TextSpan(
            style: theme.textTheme.titleLarge,
            children: [
              const TextSpan(text: 'Invoice'),
              TextSpan(
                text: ': ${widget.project.code} — ${widget.project.title}',
                style: TextStyle(
                  fontFamily: AppTokens.fontFamily,
                  fontStyle: FontStyle.normal,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceXs),
        _controls(),
        const SizedBox(height: AppTokens.spaceSm),
        Expanded(
          child: FutureBuilder<({InvoiceDocument doc, InvoiceTemplate template})?>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              if (snap.data != null) _last = snap.data;
              // Keep the previous preview visible while a reload is in flight.
              final loaded = snap.data ?? _last;
              if (loaded == null) {
                return snap.connectionState == ConnectionState.done
                    ? const Center(
                        child: Text('No invoice template configured.'),
                      )
                    : const Center(child: CircularProgressIndicator());
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
