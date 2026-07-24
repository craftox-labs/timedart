import 'package:flutter/material.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/constants/text_styles.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/widgets/dropdown_field.dart';
import 'package:timedart/widgets/entity_editor.dart';
import 'package:timedart/util/parse_rate.dart';
import 'package:timedart/features/deletions.dart';

// Add/edit/delete a project, in the shared adaptive entity-editor shell.
// Returns the new project's id when one was just created (so the caller can
// select it), or null on edit / delete / cancel.
Future<String?> showProjectEditor(
  BuildContext context, {
  required AppDatabase db,
  Project? project,
  String? initialClientId,
}) => showEntityEditor<String?>(
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
  final String? initialClientId; // preselect the client when adding under one
  @override
  State<ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<ProjectForm> {
  // Include archived clients so editing a project under an archived client
  // still shows (and can reassign) its client rather than a blank picker (#246).
  late final Stream<List<Client>> _clientsStream = widget.db.watchClients(
    includeArchived: true,
  );
  late final _code = TextEditingController(text: widget.initial?.code ?? '');
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late String? _clientId =
      widget.initial?.clientId ?? widget.initialClientId; // preselect
  late final _rate = TextEditingController(
    text: rateText(widget.initial?.rate),
  );
  String? _clientError;
  String? _titleError;
  String? _rateError;

  // The rate field shows the *effective* rate: the project's own rate if set,
  // else the selected client's defaultRate (which it inherits) so the user sees
  // what's actually charged. `_rateOverridden` tracks whether that value is the
  // project's own — an untouched inherited value is saved back as null (keep
  // inheriting), and switching client refreshes the shown default.
  late bool _rateOverridden = widget.initial?.rate != null;
  bool _settingRateProgrammatically = false;

  @override
  void initState() {
    super.initState();
    _rate.addListener(_onRateEdited);
    if (_clientId != null) _loadInheritedRate(_clientId!);
  }

  void _onRateEdited() {
    if (_settingRateProgrammatically || _rateOverridden) return;
    setState(() => _rateOverridden = true);
  }

  // Show the selected client's default in the blank rate field; guarded so this
  // programmatic write isn't mistaken for the user overriding.
  Future<void> _loadInheritedRate(String clientId) async {
    if (_rateOverridden) return;
    final client = await widget.db.getClient(clientId);
    if (!mounted || _rateOverridden) return;
    setState(() {
      _settingRateProgrammatically = true;
      _rate.text = rateText(client.defaultRate);
      _settingRateProgrammatically = false;
    });
  }

  @override
  void dispose() {
    _rate.removeListener(_onRateEdited);
    _code.dispose();
    _title.dispose();
    _rate.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.initial != null;

  Future<void> _submit() async {
    final code = _code.text.trim();
    // Code is optional (#331). Store NULL (not '') when blank so the UNIQUE
    // constraint keeps treating code-less projects as distinct — many empty
    // strings would collide, but NULLs don't.
    final codeValue = code.isEmpty ? null : code;
    final title = _title.text.trim();
    final parsed = parseRate(_rate.text);
    // Flag each required field on its own control (not one combined bail-out),
    // and set the state before returning so the messages actually render.
    setState(() {
      _clientError = _clientId == null ? 'Select a client' : null;
      _titleError = title.isEmpty ? 'Enter a title' : null;
      _rateError = parsed.error;
    });
    if (_clientError != null || _titleError != null || _rateError != null) {
      return;
    }
    // Only persist a rate the user took ownership of; an untouched inherited
    // value stays null so the project keeps following the client's default.
    final rate = _rateOverridden ? parsed.value : null;

    String? createdProjectId;
    try {
      if (_isEdit) {
        await widget.db.updateProject(
          id: widget.initial!.id,
          clientId: _clientId!, // allow reassigning the client
          code: codeValue,
          title: title,
          rate: rate,
        );
      } else {
        createdProjectId = await widget.db.addProject(
          clientId: _clientId!,
          code: codeValue,
          title: title,
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

  // Archive takes a light confirm that points to the "Show archived" toggle;
  // unarchive is immediate. Close after either way.
  Future<void> _toggleArchive() async {
    final project = widget.initial!;
    if (project.archivedAt != null) {
      await widget.db.unarchiveProject(project.id);
      if (mounted) Navigator.pop(context);
      return;
    }
    final archived = await confirmArchiveProject(context, widget.db, project);
    if (archived && mounted) Navigator.pop(context);
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
      onArchive: _isEdit ? _toggleArchive : null,
      isArchived: widget.initial?.archivedAt != null,
      fields: [
        StreamBuilder<List<Client>>(
          stream: _clientsStream,
          builder: (context, snap) {
            final clients = snap.data ?? [];
            final value = clients.any((c) => c.id == _clientId)
                ? _clientId
                : null;
            return InputDecorator(
              decoration: InputDecoration(
                label: requiredLabel(context, 'Client'),
                errorText: _clientError,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: value,
                  icon: kDropdownChevron,
                  borderRadius: kDropdownMenuRadius,
                  hint: const Text('Select a client'),
                  items: [
                    for (final c in clients)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (id) {
                    setState(() => _clientId = id);
                    if (id != null) _loadInheritedRate(id);
                  },
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppTokens.spaceXl),
        TextField(
          controller: _code,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            label: Text('Code'),
          ),
        ),
        const SizedBox(height: AppTokens.spaceXl),
        TextField(
          controller: _title,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            label: requiredLabel(context, 'Title'),
            errorText: _titleError,
          ),
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
        // Hint as its own line — flush left with the field, with a gap above —
        // rather than the decoration's indented, tight helperText.
        const SizedBox(height: AppTokens.spaceSm),
        Text(
          _rateOverridden
              ? 'Set for this project — clear to inherit the default'
              : 'Inherited from the client — edit to set a project rate',
          style: Theme.of(context).extension<AppTextStyles>()!.rowMeta,
        ),
      ],
    );
  }
}
