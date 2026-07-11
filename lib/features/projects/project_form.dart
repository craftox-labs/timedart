import 'package:flutter/material.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/widgets/dropdown_field.dart';
import 'package:timedart/widgets/entity_editor.dart';
import 'package:timedart/util/parse_rate.dart';
import 'package:timedart/features/deletions.dart';

// Add/edit/delete a project, in the shared adaptive entity-editor shell.
// Returns the new project's id when one was just created (so the caller can
// select it), or null on edit / delete / cancel.
Future<int?> showProjectEditor(
  BuildContext context, {
  required AppDatabase db,
  Project? project,
  int? initialClientId,
}) => showEntityEditor<int?>(
  context,
  builder: (ctx) =>
      ProjectForm(db: db, initial: project, initialClientId: initialClientId),
);

class ProjectForm extends StatefulWidget {
  const ProjectForm({
    super.key,
    required this.db,
    this.initial,
    this.initialClientId,
  });
  final AppDatabase db;
  final Project? initial; // null = create, set = edit
  final int? initialClientId; // preselect the client when adding under one
  @override
  State<ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<ProjectForm> {
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

    int? createdProjectId;
    try {
      if (_isEdit) {
        await widget.db.updateProject(
          id: widget.initial!.id,
          clientId: _clientId!, // allow reassigning the client
          code: _code.text.trim(),
          title: _title.text.trim(),
          rate: rate,
        );
      } else {
        createdProjectId = await widget.db.addProject(
          clientId: _clientId!,
          code: _code.text.trim(),
          title: _title.text.trim(),
          rate: rate,
        );
      }
    } catch (e) {
      // e.g. the unique project-code constraint
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save project: $e')));
      }
      return;
    }
    if (mounted) Navigator.pop(context, createdProjectId);
  }

  Future<void> _confirmDelete() async {
    final deleted = await confirmDeleteProject(context, widget.db, widget.initial!);
    if (deleted && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return EntityForm(
      title: _isEdit ? 'Edit project' : 'New project',
      isEdit: _isEdit,
      submitLabel: _isEdit ? 'Save' : 'Add',
      onSubmit: _submit,
      onCancel: () => Navigator.pop(context),
      onDelete: _isEdit ? _confirmDelete : null,
      fields: [
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
                  icon: kDropdownChevron,
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
          decoration: InputDecoration(labelText: 'Rate', errorText: _rateError),
        ),
      ],
    );
  }
}
