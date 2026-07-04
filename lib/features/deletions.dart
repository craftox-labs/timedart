import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/widgets/confirm_dialog.dart';

/// Wraps an edit modal so pressing `d` runs [onDelete] (its Delete flow). A
/// focused text field consumes the keypress first, so `d` types normally while
/// editing a field and only deletes when focus is elsewhere in the modal.
///
/// The inner [Focus] takes focus when the modal opens so key events originate
/// *inside* this subtree — otherwise the dialog's focus scope sits above the
/// shortcut and `d` never reaches it.
class DeleteHotkey extends StatelessWidget {
  const DeleteHotkey({super.key, required this.onDelete, required this.child});
  final VoidCallback onDelete;
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.keyD): onDelete},
    child: Focus(autofocus: true, child: child),
  );
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
        message: 'This client still has jobs. Delete or reassign its jobs '
            'first.',
      );
    }
    return false;
  }
  return true;
}

Future<bool> confirmDeleteJob(
  BuildContext context,
  AppDatabase db,
  Job job,
) async {
  final ok = await confirmDelete(
    context,
    title: 'Delete job?',
    message: '"${job.title}" will be removed.',
  );
  if (!ok) return false;
  try {
    await db.deleteJob(job.id);
  } catch (_) {
    if (context.mounted) {
      await showInfoDialog(
        context,
        title: "Can't delete job",
        message: 'This job has time entries. Delete its entries first.',
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
