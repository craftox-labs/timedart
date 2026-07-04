import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/util/parse_rate.dart';
import 'package:time_tracker/features/deletions.dart';

// Add/edit/delete a job. Presented adaptively — a modal dialog on wide windows,
// a bottom sheet on narrow — mirroring showTaskEditor / showEntryEditor.
// Returns the new job's id when one was just created (so the caller can select
// it), or null on edit / delete / cancel.
Future<int?> showJobEditor(
  BuildContext context, {
  required AppDatabase db,
  Job? job,
  int? initialClientId,
}) {
  final wide = MediaQuery.sizeOf(context).width >= AppTokens.breakpointMd;
  if (wide) {
    return showDialog<int?>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceXl),
            child: JobForm(
              db: db,
              initial: job,
              initialClientId: initialClientId,
            ),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<int?>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: JobForm(db: db, initial: job, initialClientId: initialClientId),
      ),
    ),
  );
}

class JobForm extends StatefulWidget {
  const JobForm({
    super.key,
    required this.db,
    this.initial,
    this.initialClientId,
  });
  final AppDatabase db;
  final Job? initial; // null = create, set = edit
  final int? initialClientId; // preselect the client when adding under one
  @override
  State<JobForm> createState() => _JobFormState();
}

class _JobFormState extends State<JobForm> {
  late final Stream<List<Client>> _clientsStream = widget.db.watchClients();
  late final _code = TextEditingController(text: widget.initial?.code ?? '');
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late int? _clientId =
      widget.initial?.clientId ?? widget.initialClientId; // preselect
  late final _rate = TextEditingController(
    text: widget.initial?.rate?.toString() ?? '',
  );
  String? _rateError;

  @override
  void dispose() {
    _code.dispose();
    _title.dispose();
    _rate.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.initial != null;

  Future<void> _submit() async {
    if (_code.text.trim().isEmpty ||
        _title.text.trim().isEmpty ||
        _clientId == null) {
      return;
    }
    final parsed = parseRate(_rate.text);
    if (parsed.error != null) {
      setState(() => _rateError = parsed.error);
      return;
    }
    setState(() => _rateError = null);
    final rate = parsed.value;

    int? createdJobId;
    try {
      if (_isEdit) {
        await widget.db.updateJob(
          id: widget.initial!.id,
          clientId: _clientId!, // allow reassigning the client
          code: _code.text.trim(),
          title: _title.text.trim(),
          rate: rate,
        );
      } else {
        createdJobId = await widget.db.addJob(
          clientId: _clientId!,
          code: _code.text.trim(),
          title: _title.text.trim(),
          rate: rate,
        );
      }
    } catch (e) {
      // e.g. the unique job-code constraint
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save job: $e')));
      }
      return;
    }
    if (mounted) Navigator.pop(context, createdJobId);
  }

  Future<void> _confirmDelete() async {
    final deleted = await confirmDeleteJob(context, widget.db, widget.initial!);
    if (deleted && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final form = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEdit ? 'Edit job' : 'New job',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        const SizedBox(height: AppTokens.spaceXl),
        StreamBuilder<List<Client>>(
          stream: _clientsStream,
          builder: (context, snap) {
            final clients = snap.data ?? [];
            final value = clients.any((c) => c.id == _clientId)
                ? _clientId
                : null;
            return InputDecorator(
              decoration: const InputDecoration(labelText: 'Client'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: value,
                  hint: const Text('Select a client'),
                  items: [
                    for (final c in clients)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (id) => setState(() => _clientId = id),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppTokens.spaceXl),
        TextField(
          controller: _code,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(labelText: 'Code'),
        ),
        const SizedBox(height: AppTokens.spaceXl),
        TextField(
          controller: _title,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: AppTokens.spaceXl),
        TextField(
          controller: _rate,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Rate',
            errorText: _rateError,
          ),
        ),
        const SizedBox(height: AppTokens.spaceXl),
        Row(
          children: [
            if (_isEdit)
              TextButton(
                onPressed: _confirmDelete,
                child: const Text('Delete'),
              ),
            const Spacer(),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            FilledButton(
              onPressed: _submit,
              child: Text(_isEdit ? 'Save' : 'Add'),
            ),
          ],
        ),
      ],
    ),
  );

    // In edit mode, `d` triggers Delete (a focused field eats it while typing).
    return _isEdit
        ? DeleteHotkey(onDelete: _confirmDelete, child: form)
        : form;
  }
}
