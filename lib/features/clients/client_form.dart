import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';

class ClientForm extends StatefulWidget {
  const ClientForm({
    super.key,
    required this.db,
    this.initial,
    required this.onDone,
  });
  final AppDatabase db;
  final Client? initial; // null = create, set = edit
  final VoidCallback onDone;
  @override
  State<ClientForm> createState() => _ClientFormState();
}

class _ClientFormState extends State<ClientForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _email = TextEditingController(text: widget.initial?.email ?? '');
  late final _rate = TextEditingController(
    text: widget.initial?.defaultRate?.toString() ?? '',
  );
  String? _rateError;

  bool get _isEdit => widget.initial != null;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) return;

    // Rate is optional, but a non-empty value must parse.
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

    final email = _email.text.trim().isEmpty ? null : _email.text.trim();
    try {
      if (_isEdit) {
        await widget.db.updateClient(
          id: widget.initial!.id,
          name: _name.text.trim(),
          email: email,
          defaultRate: rate,
        );
      } else {
        await widget.db.addClient(
          name: _name.text.trim(),
          email: email,
          defaultRate: rate,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save client: $e')),
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
        title: const Text('Delete client?'),
        content: Text('"${widget.initial!.name}" will be removed.'),
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
        await widget.db.deleteClient(widget.initial!.id);
      } catch (e) {
        // FK restrict: the client still has jobs.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot delete a client that still has jobs.'),
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
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        TextField(
          controller: _email,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: AppTokens.spaceXl),
        TextField(
          controller: _rate,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Default Rate',
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
  );
}
