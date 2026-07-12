import 'package:flutter/material.dart';

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
      content: Text(message),
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
      content: Text(message),
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
        content: const Text(
          'You have unsaved changes. Save before leaving, or discard them?',
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
    content: Text(message),
    actions: [
      FilledButton(
        autofocus: true, // Enter dismisses
        onPressed: () => Navigator.pop(ctx),
        child: const Text('OK'),
      ),
    ],
  ),
);
