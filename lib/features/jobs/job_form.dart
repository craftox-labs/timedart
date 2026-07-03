import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/util/parse_rate.dart';
import 'package:time_tracker/widgets/confirm_dialog.dart';

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
  // Called when the form closes. Passes the new job's id when one was just
  // created (so the caller can select it), or null on edit/delete/cancel.
  final void Function(int? createdJobId) onDone;
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
    if (mounted) widget.onDone(createdJobId);
  }

  Future<void> _confirmDelete() async {
    final ok = await confirmDelete(
      context,
      title: 'Delete job?',
      message: '"${widget.initial!.title}" will be removed.',
    );
    if (!ok) return;
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
    if (mounted) widget.onDone(null);
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
                    onPressed: () => widget.onDone(null),
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
