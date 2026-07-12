import 'package:flutter/material.dart';
import 'package:timedart/data/database.dart';
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

  bool get _isEdit => widget.task != null;

  @override
  void dispose() {
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

    try {
      if (_isEdit) {
        await widget.db.updateTask(
          id: widget.task!.id,
          title: title,
          rate: parsed.value,
        );
      } else {
        await widget.db.addTask(
          projectId: widget.projectId,
          title: title,
          rate: parsed.value,
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
            hintText: 'Overrides the project rate — leave blank to inherit',
            errorText: _rateError,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }
}
