import 'package:flutter/material.dart';
import 'package:time_tracker/constants/tokens.dart';

/// Shared bits for the branding content-pane editors (theme/profile/template):
/// a uniform dense field decoration and the title + Delete/Cancel/Save header.

InputDecoration fieldDecoration(
  String label, {
  String? prefixText,
  Widget? prefixIcon,
  bool dropdown = false,
}) => InputDecoration(
  labelText: label,
  isDense: true,
  prefixText: prefixText,
  prefixIcon: prefixIcon,
  prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
  // Dropdowns get extra right padding so the chevron isn't jammed against the
  // border.
  contentPadding: EdgeInsets.fromLTRB(
    AppTokens.spaceSm,
    AppTokens.spaceSm,
    dropdown ? AppTokens.spaceMd : AppTokens.spaceSm,
    AppTokens.spaceSm,
  ),
);

/// The compact "Default" toggle shared by the branding editors — a small switch
/// beside its label.
Widget brandingDefaultToggle({
  required bool value,
  required ValueChanged<bool> onChanged,
}) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    const Text('Default'),
    const SizedBox(width: AppTokens.space2xs),
    Transform.scale(
      scale: 0.8,
      child: Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  ],
);

/// Title on the left, actions on the right — mirrors the theme editor header so
/// every branding editor opens the same way.
Widget editorHeader({
  required BuildContext context,
  required String title,
  required bool isEdit,
  required VoidCallback onDelete,
  required VoidCallback onCancel,
  required VoidCallback onSave,
}) {
  return Row(
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const Spacer(),
      if (isEdit)
        TextButton.icon(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, size: AppTokens.iconSm),
          label: const Text('Delete'),
        ),
      const SizedBox(width: AppTokens.spaceSm),
      OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
      const SizedBox(width: AppTokens.spaceSm),
      FilledButton(onPressed: onSave, child: const Text('Save')),
    ],
  );
}
