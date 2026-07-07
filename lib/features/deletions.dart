import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/widgets/confirm_dialog.dart';

/// Wraps an edit modal so pressing `d` runs [onDelete] (its Delete flow), but
/// only when a text field isn't focused — a focused field still needs `d` for
/// typing. (A field inserts characters via the IME, yet the raw key event
/// still bubbles here, so a plain shortcut would wrongly eat it.)
///
/// Autofocuses so, on open with no field focused, the key originates inside
/// this subtree; otherwise the dialog's focus scope sits above us and `d`
/// never reaches the handler.
class DeleteHotkey extends StatelessWidget {
  const DeleteHotkey({super.key, required this.onDelete, required this.child});
  final VoidCallback onDelete;
  final Widget child;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyD) {
      return KeyEventResult.ignored;
    }
    // A text field is focused (its EditableText is the primary-focus context) →
    // leave `d` for typing.
    final ctx = FocusManager.instance.primaryFocus?.context;
    final editing =
        ctx != null && ctx.findAncestorWidgetOfExactType<EditableText>() != null;
    if (editing) return KeyEventResult.ignored;
    onDelete();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: true, onKeyEvent: _onKey, child: child);
}

// Confirm-then-delete for each entity, shared by the edit modals' Delete button
// and the app-wide `d` key. Each shows the warning, attempts the delete, and on
// a blocked delete (FK restrict) surfaces an info dialog — a SnackBar would be
// hidden behind an open modal. Returns true only if the row was deleted.

Future<bool> confirmDeleteClient(
  BuildContext context,
  AppDatabase db,
  Client client,
) async {
  final ok = await confirmDelete(
    context,
    title: 'Delete client?',
    message: '"${client.name}" will be removed.',
  );
  if (!ok) return false;
  try {
    await db.deleteClient(client.id);
  } catch (_) {
    if (context.mounted) {
      await showInfoDialog(
        context,
        title: "Can't delete client",
        message: 'This client still has projects. Delete or reassign its projects '
            'first.',
      );
    }
    return false;
  }
  return true;
}

Future<bool> confirmDeleteProject(
  BuildContext context,
  AppDatabase db,
  Project project,
) async {
  final ok = await confirmDelete(
    context,
    title: 'Delete project?',
    message: '"${project.title}" will be removed.',
  );
  if (!ok) return false;
  try {
    await db.deleteProject(project.id);
  } catch (_) {
    if (context.mounted) {
      await showInfoDialog(
        context,
        title: "Can't delete project",
        message: 'This project has time entries. Delete its entries first.',
      );
    }
    return false;
  }
  return true;
}

Future<bool> confirmDeleteTask(
  BuildContext context,
  AppDatabase db,
  Task task,
) async {
  final ok = await confirmDelete(
    context,
    title: 'Delete task?',
    message: '"${task.title}" will be removed.',
  );
  if (!ok) return false;
  try {
    await db.deleteTask(task.id);
  } catch (_) {
    if (context.mounted) {
      await showInfoDialog(
        context,
        title: "Can't delete task",
        message: 'This task has time entries. Delete its entries first.',
      );
    }
    return false;
  }
  return true;
}

Future<bool> confirmDeleteEntry(
  BuildContext context,
  AppDatabase db,
  TimeEntry entry,
) async {
  final label = entry.description?.trim();
  final ok = await confirmDelete(
    context,
    title: 'Delete entry?',
    message: label == null || label.isEmpty
        ? 'This time entry will be removed.'
        : '"$label" will be removed.',
  );
  if (!ok) return false;
  try {
    await db.deleteEntry(entry.id);
  } catch (_) {
    if (context.mounted) {
      await showInfoDialog(
        context,
        title: "Can't delete entry",
        message: 'Something went wrong deleting this entry.',
      );
    }
    return false;
  }
  return true;
}
