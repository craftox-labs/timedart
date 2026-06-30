import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';

class JobForm extends StatefulWidget {
  const JobForm({
    super.key,
    required this.db,
    this.initial,
    required this.onDone,
  });
  final AppDatabase db;
  final Job? initial; // null = create, set = edit
  final VoidCallback onDone;
  @override
  State<JobForm> createState() => _JobFormState();
}

class _JobFormState extends State<JobForm> {
  late final Stream<List<Client>> _clientsStream = widget.db.watchClients();
  late final _code = TextEditingController(text: widget.initial?.code ?? '');
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late int? _clientId = widget.initial?.clientId; // pre-select in edit mode
  late final _rate = TextEditingController(
    text: widget.initial?.rate?.toString() ?? '',
  );

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
    final rate = _rate.text.trim().isEmpty
        ? null
        : double.tryParse(_rate.text.trim());
    if (_isEdit) {
      await widget.db.updateJob(
        id: widget.initial!.id,
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
    if (mounted) widget.onDone(); // close the edit screen
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
      await widget.db.deleteJob(widget.initial!.id);
      if (mounted) widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      children: [
        StreamBuilder<List<Client>>(
          stream: _clientsStream,
          builder: (context, snap) {
            final clients = snap.data ?? [];
            final value = clients.any((c) => c.id == _clientId)
                ? _clientId
                : null;
            return DropdownButton<int>(
              value: value,
              hint: const Text('Client'),
              items: [
                for (final c in clients)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (id) => setState(() => _clientId = id),
            );
          },
        ),
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
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _rate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Default Rate'),
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            if (_isEdit)
              TextButton(
                onPressed: _confirmDelete,
                child: const Text('Delete'),
              ),
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
  );
}
