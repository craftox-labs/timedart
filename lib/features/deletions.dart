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

// Shared confirm-then-delete flow for the three parent entities: a plain
// confirm; if the guarded delete is blocked by live children, offer the
// count-warned cascade. [noun] names the entity ("client"), [name] is quoted in
// the copy, and [cascadeTitle]/[cascadeClause] fill the cascade dialog. The
// three callbacks are the guarded delete, its impact count, and its cascade.
// Returns true iff something was deleted.
Future<bool> _confirmDeleteCascading(
  BuildContext context, {
  required String noun,
  required String name,
  required String cascadeTitle,
  required String cascadeClause,
  required Future<void> Function() delete,
  required Future<DeleteImpact> Function() impact,
  required Future<void> Function() cascade,
}) async {
  Future<bool> failed() async {
    if (context.mounted) {
      await showInfoDialog(
        context,
        title: "Can't delete $noun",
        message: 'Something went wrong deleting this $noun.',
      );
    }
    return false;
  }

  final ok = await confirmDelete(
    context,
    title: 'Delete $noun?',
    message: '"$name" will be removed. This can\'t be undone.',
  );
  if (!ok) return false;
  try {
    await delete();
  } on DeleteBlockedException {
    final counts = await impact();
    if (!context.mounted) return false;
    final go = await confirmAction(
      context,
      title: cascadeTitle,
      message: '"$name" still has ${_impactPhrase(counts)}. '
          '$cascadeClause, and this can\'t be undone.',
      confirmLabel: 'Delete everything',
    );
    if (!go) return false;
    try {
      await cascade();
    } catch (_) {
      return failed();
    }
    return true;
  } catch (_) {
    return failed();
  }
  return true;
}

Future<bool> confirmDeleteClient(
  BuildContext context,
  AppDatabase db,
  Client client,
) => _confirmDeleteCascading(
  context,
  noun: 'client',
  name: client.name,
  cascadeTitle: 'Delete client and everything under it?',
  cascadeClause: 'Deleting the client removes all of it',
  delete: () => db.deleteClient(client.id),
  impact: () => db.clientDeleteImpact(client.id),
  cascade: () => db.deleteClientCascade(client.id),
);

Future<bool> confirmDeleteProject(
  BuildContext context,
  AppDatabase db,
  Project project,
) => _confirmDeleteCascading(
  context,
  noun: 'project',
  name: project.title,
  cascadeTitle: 'Delete project and everything under it?',
  cascadeClause: 'Deleting the project removes all of it',
  delete: () => db.deleteProject(project.id),
  impact: () => db.projectDeleteImpact(project.id),
  cascade: () => db.deleteProjectCascade(project.id),
);

Future<bool> confirmDeleteTask(
  BuildContext context,
  AppDatabase db,
  Task task,
) => _confirmDeleteCascading(
  context,
  noun: 'task',
  name: task.title,
  cascadeTitle: 'Delete task and its time entries?',
  cascadeClause: 'Deleting the task removes them',
  delete: () => db.deleteTask(task.id),
  impact: () => db.taskDeleteImpact(task.id),
  cascade: () => db.deleteTaskCascade(task.id),
);

// Archiving is reversible, so it takes a light confirm (not the destructive
// delete flow) that also teaches where the item goes — the side panel's "Show
// archived" toggle. Unarchive is immediate (no dialog); the caller handles it.
// Returns true only if the row was archived.
Future<bool> confirmArchiveClient(
  BuildContext context,
  AppDatabase db,
  Client client,
) async {
  final ok = await confirmAction(
    context,
    title: 'Archive client?',
    message: '"${client.name}" and its projects will be hidden from the active '
        'list. Show or restore them anytime with "Show archived" at the bottom '
        'of the list.',
    confirmLabel: 'Archive',
  );
  if (!ok) return false;
  await db.archiveClient(client.id);
  return true;
}

Future<bool> confirmArchiveProject(
  BuildContext context,
  AppDatabase db,
  Project project,
) async {
  final ok = await confirmAction(
    context,
    title: 'Archive project?',
    message: '"${project.title}" will be hidden from the active list. Show or '
        'restore it anytime with "Show archived" at the bottom of the list.',
    confirmLabel: 'Archive',
  );
  if (!ok) return false;
  await db.archiveProject(project.id);
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
