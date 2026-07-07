import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/util/parse_rate.dart';
import 'package:time_tracker/features/deletions.dart';

// Add/edit/delete a task under a project. Presented adaptively — a modal dialog on
// wide windows, a bottom sheet on narrow — mirroring showEntryEditor.
Future<void> showTaskEditor(
  BuildContext context, {
  required AppDatabase db,
  required int projectId,
  Task? task,
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
            child: TaskForm(db: db, projectId: projectId, task: task),
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
        child: TaskForm(db: db, projectId: projectId, task: task),
      ),
    ),
  );
}

class TaskForm extends StatefulWidget {
  const TaskForm({super.key, required this.db, required this.projectId, this.task});
  final AppDatabase db;
  final int projectId;
  final Task? task; // null = create, set = edit

  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  late final _title = TextEditingController(text: widget.task?.title ?? '');
  late final _rate = TextEditingController(
    text: widget.task?.rate?.toString() ?? '',
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
    final form = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _isEdit ? 'Edit task' : 'New task',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppTokens.spaceXl),
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
            FilledButton(onPressed: _submit, child: const Text('Save')),
          ],
        ),
      ],
    );

    // In edit mode, `d` triggers Delete (a focused field eats it while typing).
    return _isEdit
        ? DeleteHotkey(onDelete: _confirmDelete, child: form)
        : form;
  }
}
