import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';

class JobForm extends StatefulWidget {
  const JobForm({
    super.key,
    required this.db,
    this.initial,
    this.initialClientId,
    required this.onDone,
  });
  final AppDatabase db;
  final Job? initial; // null = create, set = edit
  final int? initialClientId; // preselect the client when adding under one
  final VoidCallback onDone;
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
    // Rate is optional, but a non-empty value must be a valid number —
    // don't silently drop "5o" to null.
    final rateText = _rate.text.trim();
    double? rate;
    if (rateText.isNotEmpty) {
      rate = double.tryParse(rateText);
      if (rate == null) {
        setState(() => _rateError = 'Enter a number, or leave blank');
        return;
      }
    }
    setState(() => _rateError = null);

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
        await widget.db.addJob(
          clientId: _clientId!,
          code: _code.text.trim(),
          title: _title.text.trim(),
          rate: rate,
        );
      }
    } catch (e) {
      // e.g. the unique job-code constraint
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save job: $e')),
        );
      }
      return;
    }
    if (mounted) widget.onDone();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete job?'),
        content: Text('"${widget.initial!.title}" will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await widget.db.deleteJob(widget.initial!.id);
      } catch (e) {
        // FK restrict: the job has time entries recorded against it.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot delete a job that has time entries.'),
            ),
          );
        }
        return;
      }
      if (mounted) widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isEdit ? 'Edit job' : 'New job',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppTokens.spaceMd),
        // Title stays pinned at the top; the fields + actions center in the
        // remaining vertical space.
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                decoration: const InputDecoration(labelText: 'Code'),
              ),
              const SizedBox(height: AppTokens.spaceXl),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: AppTokens.spaceXl),
              TextField(
                controller: _rate,
                keyboardType: TextInputType.number,
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
                    onPressed: widget.onDone,
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
        ),
      ],
    ),
  );
}
