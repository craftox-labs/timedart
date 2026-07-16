import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/widgets/confirm_dialog.dart';

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
// a blocked delete (the row still has live children) offers a deliberate,
// count-warned cascade that removes the parent and everything under it (#75) —
// the guard stays the default, this is the explicit escape hatch. Returns true
// only if something was deleted.

String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// "3 projects, 8 tasks and 41 time entries" — non-zero parts only, Oxford-less
/// "and" before the last. "time entry" has an irregular plural.
String _impactPhrase(DeleteImpact i) {
  final parts = <String>[
    if (i.projects > 0) _plural(i.projects, 'project'),
    if (i.tasks > 0) _plural(i.tasks, 'task'),
    if (i.entries > 0) '${i.entries} time ${i.entries == 1 ? 'entry' : 'entries'}',
  ];
  if (parts.isEmpty) return 'no other items';
  if (parts.length == 1) return parts.first;
  return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
}

Future<bool> confirmDeleteClient(
  BuildContext context,
  AppDatabase db,
  Client client,
) async {
  final ok = await confirmDelete(
    context,
    title: 'Delete client?',
    message: '"${client.name}" will be removed. This can\'t be undone.',
  );
  if (!ok) return false;
  try {
    await db.deleteClient(client.id);
  } on DeleteBlockedException {
    final impact = await db.clientDeleteImpact(client.id);
    if (!context.mounted) return false;
    final cascade = await confirmAction(
      context,
      title: 'Delete client and everything under it?',
      message: '"${client.name}" still has ${_impactPhrase(impact)}. '
          'Deleting the client removes all of it, and this can\'t be undone.',
      confirmLabel: 'Delete everything',
    );
    if (!cascade) return false;
    try {
      await db.deleteClientCascade(client.id);
    } catch (_) {
      if (context.mounted) {
        await showInfoDialog(
          context,
          title: "Can't delete client",
          message: 'Something went wrong deleting this client.',
        );
      }
      return false;
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      await showInfoDialog(
        context,
        title: "Can't delete client",
        message: 'Something went wrong deleting this client.',
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
    message: '"${project.title}" will be removed. This can\'t be undone.',
  );
  if (!ok) return false;
  try {
    await db.deleteProject(project.id);
  } on DeleteBlockedException {
    final impact = await db.projectDeleteImpact(project.id);
    if (!context.mounted) return false;
    final cascade = await confirmAction(
      context,
      title: 'Delete project and everything under it?',
      message: '"${project.title}" still has ${_impactPhrase(impact)}. '
          'Deleting the project removes all of it, and this can\'t be undone.',
      confirmLabel: 'Delete everything',
    );
    if (!cascade) return false;
    try {
      await db.deleteProjectCascade(project.id);
    } catch (_) {
      if (context.mounted) {
        await showInfoDialog(
          context,
          title: "Can't delete project",
          message: 'Something went wrong deleting this project.',
        );
      }
      return false;
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      await showInfoDialog(
        context,
        title: "Can't delete project",
        message: 'Something went wrong deleting this project.',
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
    message: '"${task.title}" will be removed. This can\'t be undone.',
  );
  if (!ok) return false;
  try {
    await db.deleteTask(task.id);
  } on DeleteBlockedException {
    final impact = await db.taskDeleteImpact(task.id);
    if (!context.mounted) return false;
    final cascade = await confirmAction(
      context,
      title: 'Delete task and its time entries?',
      message: '"${task.title}" still has ${_impactPhrase(impact)}. '
          'Deleting the task removes them, and this can\'t be undone.',
      confirmLabel: 'Delete everything',
    );
    if (!cascade) return false;
    try {
      await db.deleteTaskCascade(task.id);
    } catch (_) {
      if (context.mounted) {
        await showInfoDialog(
          context,
          title: "Can't delete task",
          message: 'Something went wrong deleting this task.',
        );
      }
      return false;
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      await showInfoDialog(
        context,
        title: "Can't delete task",
        message: 'Something went wrong deleting this task.',
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
        ? 'This time entry will be removed. This can\'t be undone.'
        : '"$label" will be removed. This can\'t be undone.',
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
