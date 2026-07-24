import 'package:flutter/material.dart';

/// Shared content wrapper for the modal dialogs: caps width (so a long message
/// wraps into a readable column instead of stretching the modal, matching the
/// entity-editor dialog) and forces the body to [onSurface] — the dialog theme
/// greens the title but leaves the body inheriting that tint. Shared by the
/// confirmation dialogs here and the sync dialogs in the shell so every
/// AlertDialog reads the same: green heading, off-white body.
Widget dialogContent(
  BuildContext ctx,
  Widget child, {
  double maxWidth = 420,
}) => ConstrainedBox(
  constraints: BoxConstraints(maxWidth: maxWidth),
  child: DefaultTextStyle.merge(
    style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
    child: child,
  ),
);

/// A yes/no delete confirmation. Returns true only if the user confirms.
/// Shared by the project and client forms so the dialog reads identically.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: dialogContent(ctx, Text(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          autofocus: true, // Enter confirms
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// A generic yes/no confirmation with a caller-supplied confirm label. Returns
/// true only if the user confirms. Use for destructive actions other than a
/// plain delete (e.g. "Replace" on a data import).
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: dialogContent(ctx, Text(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          autofocus: true, // Enter confirms
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Action chosen from [confirmUnsavedChanges]. `null` (dismissed, or the
/// explicit Cancel button) means "stay put, keep editing".
enum UnsavedChangesAction { save, discard }

/// Warns that leaving now would lose edits, offering save-then-leave,
/// discard-and-leave, or staying to keep editing.
Future<UnsavedChangesAction?> confirmUnsavedChanges(BuildContext context) =>
    showDialog<UnsavedChangesAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: dialogContent(
          ctx,
          const Text(
            'You have unsaved changes. Save before leaving, or discard them?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, UnsavedChangesAction.discard),
            child: const Text('Discard'),
          ),
          FilledButton(
            autofocus: true, // Enter saves
            onPressed: () => Navigator.pop(ctx, UnsavedChangesAction.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );

/// A single-button information dialog — used to surface errors that a SnackBar
/// would hide behind an open modal (e.g. a blocked delete).
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
}) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text(title),
    content: dialogContent(ctx, Text(message)),
    actions: [
      FilledButton(
        autofocus: true, // Enter dismisses
        onPressed: () => Navigator.pop(ctx),
        child: const Text('OK'),
      ),
    ],
  ),
);
