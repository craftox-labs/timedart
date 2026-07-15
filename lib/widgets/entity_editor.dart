import 'package:flutter/material.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/features/deletions.dart';
import 'package:timedart/widgets/sheet_grab_handle.dart';

/// The shared modal chrome for the entity CRUD editors (client / project / task
/// / entry). The presenter and scaffold live here once; each form supplies only
/// its fields and its submit/cancel/delete logic — the modal counterpart to the
/// content-pane [EditorSession].

/// Presents an entity editor adaptively: a centred modal [Dialog] on wide
/// windows, a bottom sheet (lifted clear of the keyboard) on narrow ones.
/// Returns whatever the form pops the route with — e.g. the project editor pops
/// a freshly-created project's id, so [T] is `int?` there and `void` elsewhere.
Future<T?> showEntityEditor<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final wide = MediaQuery.sizeOf(context).width >= AppTokens.breakpointMd;
  if (wide) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceXl),
            child: builder(ctx),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true, // so it can grow above the keyboard
    builder: (ctx) => Padding(
      // Lift the sheet clear of the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetGrabHandle(),
          // The handle supplies the top gap; content keeps the sides + bottom.
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceLg,
                0,
                AppTokens.spaceLg,
                AppTokens.spaceLg,
              ),
              child: builder(ctx),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The scaffold every entity form builds: a [title] over the form's [fields],
/// then the Delete / Cancel / Save action row, all in a scroll view — plus the
/// `d`-to-delete hotkey in edit mode. The form owns its submit/cancel/delete
/// logic (validation, DB write, error snackbar, popping the route); this only
/// lays out the shared chrome and calls back.
///
/// Pass the field widgets in [fields] with their own inter-field spacing — the
/// scaffold adds the gaps above the fields and below them, not between.
class EntityForm extends StatelessWidget {
  const EntityForm({
    super.key,
    required this.title,
    required this.isEdit,
    required this.submitLabel,
    required this.onSubmit,
    required this.onCancel,
    required this.fields,
    this.onDelete,
  });

  final String title; // "New client" / "Edit client"
  final bool isEdit;
  final String submitLabel; // "Add" / "Save"
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  // The per-form field widgets, already spaced between one another.
  final List<Widget> fields;
  // Delete + the `d` hotkey appear only when editing and this is wired.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final showDelete = isEdit && onDelete != null;
    final body = SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppTokens.spaceXl),
          ...fields,
          const SizedBox(height: AppTokens.spaceXl),
          Row(
            children: [
              if (showDelete)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  color: Theme.of(context).colorScheme.primary,
                  tooltip: 'Delete',
                ),
              const Spacer(),
              OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
              const SizedBox(width: AppTokens.spaceSm),
              FilledButton(onPressed: onSubmit, child: Text(submitLabel)),
            ],
          ),
        ],
      ),
    );
    // In edit mode, `d` triggers Delete (a focused field eats it while typing).
    return showDelete
        ? DeleteHotkey(onDelete: onDelete!, child: body)
        : body;
  }
}
