import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/util/parse_rate.dart';
import 'package:time_tracker/widgets/confirm_dialog.dart';

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

    final parsed = parseRate(_rate.text);
    if (parsed.error != null) {
      setState(() => _rateError = parsed.error);
      return;
    }
    setState(() => _rateError = null);
    final rate = parsed.value;

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save client: $e')));
      }
      return;
    }
    if (mounted) widget.onDone();
  }

  Future<void> _confirmDelete() async {
    final ok = await confirmDelete(
      context,
      title: 'Delete client?',
      message: '"${widget.initial!.name}" will be removed.',
    );
    if (!ok) return;
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

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isEdit ? 'Edit client' : 'New client',
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
        ),
      ],
    ),
  );
}
