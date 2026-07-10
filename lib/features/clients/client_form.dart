import 'package:flutter/material.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/util/parse_rate.dart';
import 'package:timedart/features/deletions.dart';

// Add/edit/delete a client. Presented adaptively — a modal dialog on wide
// windows, a bottom sheet on narrow — mirroring showTaskEditor / showProjectEditor.
Future<void> showClientEditor(
  BuildContext context, {
  required AppDatabase db,
  Client? client,
}) {
  final wide = MediaQuery.sizeOf(context).width >= AppTokens.breakpointMd;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceXl),
            child: ClientForm(db: db, initial: client),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        child: ClientForm(db: db, initial: client),
      ),
    ),
  );
}

class ClientForm extends StatefulWidget {
  const ClientForm({super.key, required this.db, this.initial});
  final AppDatabase db;
  final Client? initial; // null = create, set = edit
  @override
  State<ClientForm> createState() => _ClientFormState();
}

class _ClientFormState extends State<ClientForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _contact = TextEditingController(
    text: widget.initial?.contactName ?? '',
  );
  late final _email = TextEditingController(text: widget.initial?.email ?? '');
  late final _phone = TextEditingController(text: widget.initial?.phone ?? '');
  late final _address = TextEditingController(
    text: widget.initial?.address ?? '',
  );
  late final _abn = TextEditingController(text: widget.initial?.abn ?? '');
  late final _rate = TextEditingController(
    text: widget.initial?.defaultRate.toString() ?? '',
  );
  String? _rateError;

  bool get _isEdit => widget.initial != null;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _abn.dispose();
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
    // A client's default rate is required — it's the fallback every project inherits.
    final rate = parsed.value;
    if (rate == null) {
      setState(() => _rateError = 'A default rate is required');
      return;
    }
    setState(() => _rateError = null);

    String? clean(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final email = clean(_email);
    final contact = clean(_contact);
    final phone = clean(_phone);
    final address = clean(_address);
    final abn = clean(_abn);
    try {
      if (_isEdit) {
        await widget.db.updateClient(
          id: widget.initial!.id,
          name: _name.text.trim(),
          contactName: contact,
          email: email,
          phone: phone,
          address: address,
          abn: abn,
          defaultRate: rate,
        );
      } else {
        await widget.db.addClient(
          name: _name.text.trim(),
          contactName: contact,
          email: email,
          phone: phone,
          address: address,
          abn: abn,
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
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmDelete() async {
    final deleted = await confirmDeleteClient(
      context,
      widget.db,
      widget.initial!,
    );
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
            _isEdit ? 'Edit client' : 'New client',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        const SizedBox(height: AppTokens.spaceXl),
        TextField(
          controller: _name,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: AppTokens.spaceLg),
        TextField(
          controller: _contact,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(labelText: 'Contact name'),
        ),
        const SizedBox(height: AppTokens.spaceLg),
        TextField(
          controller: _email,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: AppTokens.spaceLg),
        TextField(
          controller: _phone,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(labelText: 'Phone'),
        ),
        const SizedBox(height: AppTokens.spaceLg),
        TextField(
          controller: _address,
          onSubmitted: (_) => _submit(),
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Address'),
        ),
        const SizedBox(height: AppTokens.spaceLg),
        TextField(
          controller: _abn,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(labelText: 'ABN / Tax number'),
        ),
        const SizedBox(height: AppTokens.spaceXl),
        TextField(
          controller: _rate,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => _submit(),
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
