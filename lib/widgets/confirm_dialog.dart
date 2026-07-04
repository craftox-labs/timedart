import 'package:flutter/material.dart';

/// A yes/no delete confirmation. Returns true only if the user confirms.
/// Shared by the job and client forms so the dialog reads identically.
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
