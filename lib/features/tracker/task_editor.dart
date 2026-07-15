import 'package:flutter/material.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/constants/text_styles.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/util/parse_rate.dart';
import 'package:timedart/features/deletions.dart';
import 'package:timedart/widgets/entity_editor.dart';

// Add/edit/delete a task under a project, in the shared adaptive entity-editor
// shell.
Future<void> showTaskEditor(
  BuildContext context, {
  required AppDatabase db,
  required String projectId,
  Task? task,
}) => showEntityEditor<void>(
  context,
  builder: (ctx) => TaskForm(db: db, projectId: projectId, task: task),
);

class TaskForm extends StatefulWidget {
  const TaskForm({super.key, required this.db, required this.projectId, this.task});
  final AppDatabase db;
  final String projectId;
  final Task? task; // null = create, set = edit

  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  late final _title = TextEditingController(text: widget.task?.title ?? '');
  late final _rate = TextEditingController(
    text: rateText(widget.task?.rate),
  );
  String? _titleError;
  String? _rateError;

  // The rate field shows the *effective* rate: the task's own rate if set, else
  // the inherited default (project.rate ?? client.defaultRate) so the user sees
  // what's actually charged. `_rateOverridden` tracks whether that value is the
  // task's own — an untouched inherited value is saved back as null (keep
  // inheriting), so editing a task doesn't silently pin its rate.
  late bool _rateOverridden = widget.task?.rate != null;
  bool _settingRateProgrammatically = false;

  bool get _isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    _rate.addListener(_onRateEdited);
    _loadInheritedRate();
  }

  void _onRateEdited() {
    if (_settingRateProgrammatically || _rateOverridden) return;
    setState(() => _rateOverridden = true);
  }

  // Fill the blank rate with the inherited default so the user sees the live
  // value; guarded so this programmatic write doesn't count as an override.
  Future<void> _loadInheritedRate() async {
    if (_rateOverridden) return;
    final project = await widget.db.getProject(widget.projectId);
    final client = await widget.db.getClient(project.clientId);
    if (!mounted || _rateOverridden) return;
    setState(() {
      _settingRateProgrammatically = true;
      _rate.text = rateText(project.rate ?? client.defaultRate);
      _settingRateProgrammatically = false;
    });
  }

  @override
  void dispose() {
    _rate.removeListener(_onRateEdited);
    _title.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final parsed = parseRate(_rate.text);
    setState(() {
      _titleError = title.isEmpty ? 'Enter a task name' : null;
      _rateError = parsed.error;
    });
    if (_titleError != null || _rateError != null) return;

    // Only persist a rate the user actually took ownership of; an untouched
    // inherited value stays null so the task keeps following the default.
    final rate = _rateOverridden ? parsed.value : null;
    try {
      if (_isEdit) {
        await widget.db.updateTask(
          id: widget.task!.id,
          title: title,
          rate: rate,
        );
      } else {
        await widget.db.addTask(
          projectId: widget.projectId,
          title: title,
          rate: rate,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save task: $e')));
      }
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmDelete() async {
    final deleted = await confirmDeleteTask(context, widget.db, widget.task!);
    if (deleted && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return EntityForm(
      title: _isEdit ? 'Edit task' : 'New task',
      isEdit: _isEdit,
      submitLabel: _isEdit ? 'Save' : 'Add',
      onSubmit: _submit,
      onCancel: () => Navigator.pop(context),
      onDelete: _isEdit ? _confirmDelete : null,
      fields: [
        TextField(
          controller: _title,
          autofocus: !_isEdit,
          decoration: InputDecoration(
            labelText: 'Task',
            hintText: 'What is this work?',
            errorText: _titleError,
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: AppTokens.spaceLg),
        TextField(
          controller: _rate,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Rate (\$/h)',
            errorText: _rateError,
          ),
          onSubmitted: (_) => _submit(),
        ),
        // Hint as its own line — flush left with the field, with a gap above —
        // rather than the decoration's indented, tight helperText.
        const SizedBox(height: AppTokens.spaceSm),
        Text(
          _rateOverridden
              ? 'Set for this task — clear to inherit the default'
              : 'Inherited default — edit to set a task-specific rate',
          style: Theme.of(context).extension<AppTextStyles>()!.rowMeta,
        ),
      ],
    );
  }
}
