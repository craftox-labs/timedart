import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/widgets/dropdown_field.dart';

/// Shared bits for the branding content-pane editors (theme/profile/template):
/// a uniform dense field decoration and the title + Delete/Cancel/Save header.

/// The decoration shared by every branding input. Symmetric padding — selects
/// get their trailing gap from [kDropdownChevron], not from here.
///
/// Deliberately NOT isDense: with an OutlineInputBorder, isDense drops the
/// headroom the floating label needs, clipping the label's top on fields with
/// no prefix (a prefix-less Name/Font/Theme). The explicit contentPadding keeps
/// the field compact without that clipping.
InputDecoration fieldDecoration(
  String? label, {
  String? hint,
  String? prefixText,
  Widget? prefixIcon,
  String? errorText,
}) => InputDecoration(
  labelText: label,
  hintText: hint,
  errorText: errorText,
  prefixText: prefixText,
  prefixIcon: prefixIcon,
  prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
  contentPadding: const EdgeInsets.all(AppTokens.spaceSm),
);

/// A dense text field for the branding editor forms. By default the field name
/// reads as a placeholder at rest, rises to a floating label while focused, and
/// drops away once filled — so a filled form shows values, not a wall of labels
/// (used in the profile editor). Set [persistentLabel] to keep a always-visible
/// floating label instead, matching neighbouring selects (theme/template, where
/// a lone label-less input beside labelled dropdowns looks off).
/// Wrap it in a [FieldRow] rather than sizing it directly.
class EditorTextField extends StatefulWidget {
  const EditorTextField({
    super.key,
    required this.controller,
    required this.label,
    this.number = false,
    this.persistentLabel = false,
    this.errorText,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final bool number;
  final bool persistentLabel;
  // A non-blocking format hint shown under the field (e.g. a malformed IBAN).
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  State<EditorTextField> createState() => _EditorTextFieldState();
}

class _EditorTextFieldState extends State<EditorTextField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_sync);
  }

  @override
  void dispose() {
    _focus.removeListener(_sync);
    _focus.dispose();
    super.dispose();
  }

  void _sync() => setState(() {});

  TextInputType? get _keyboard => widget.number
      ? const TextInputType.numberWithOptions(decimal: true)
      : null;

  @override
  Widget build(BuildContext context) {
    // Always-on label (consistent with selects): let Material float it normally.
    if (widget.persistentLabel) {
      return TextField(
        controller: widget.controller,
        keyboardType: _keyboard,
        decoration: fieldDecoration(widget.label, errorText: widget.errorText),
        onChanged: widget.onChanged,
      );
    }
    // Placeholder at rest → floating label on focus → nothing once filled.
    final focused = _focus.hasFocus;
    final empty = widget.controller.text.isEmpty;
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      keyboardType: _keyboard,
      decoration: fieldDecoration(
        focused ? widget.label : null,
        hint: !focused && empty ? widget.label : null,
        errorText: widget.errorText,
      ),
      onChanged: (v) {
        widget.onChanged?.call(v);
        // Rebuild so the label/placeholder tracks the empty→filled transition.
        setState(() {});
      },
    );
  }
}

/// A dense select matching [EditorTextField] — consistent height, decoration,
/// and the shared [kDropdownChevron]. Fills its [FieldRow] cell.
class EditorDropdown<T> extends StatelessWidget {
  const EditorDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
    initialValue: value,
    // No widget-level isDense: it compresses the button enough to clip the
    // floating label. The decoration's isDense keeps the field height in line.
    isExpanded: true,
    icon: kDropdownChevron,
    decoration: fieldDecoration(label),
    items: items,
    onChanged: onChanged,
  );
}

/// One cell in a [FieldRow]. [flex] weights how much of the row width the child
/// takes on wide layouts; a flex of 0 keeps the child at its intrinsic width
/// (for toggles and other non-field controls).
class Field {
  const Field(this.child, {this.flex = 1});
  final Widget child;
  final int flex;
}

/// A row of form controls that reflows in three tiers: all cells side by side
/// (honouring each [Field.flex]) when there's room, two columns on mid-size
/// panes, then a full-width stacked column only once truly narrow. The single
/// reflow primitive for every branding editor form.
///
/// Pass [stackBelow] to override the tiers with a single breakpoint — above it
/// the row is full-width, below it stacks straight to one column (no two-up).
/// Used for aligned grids (e.g. the theme editor) that must collapse together.
class FieldRow extends StatelessWidget {
  const FieldRow(this.fields, {super.key, this.stackBelow});
  final List<Field> fields;
  final double? stackBelow;

  // Min width for a cell in the full row; and the floor for staying two-up.
  static const double _minCell = 190;
  static const double _twoColMin = 400;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = _columns(c.maxWidth);
        if (cols >= fields.length) return _visualRow(fields);
        // Chunk into rows of `cols`; a short trailing chunk fills its width.
        final rows = <Widget>[];
        for (var i = 0; i < fields.length; i += cols) {
          final end = i + cols < fields.length ? i + cols : fields.length;
          if (i > 0) rows.add(const SizedBox(height: AppTokens.spaceMd));
          rows.add(_visualRow(fields.sublist(i, end)));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  int _columns(double width) {
    final n = fields.length;
    if (stackBelow != null) return width >= stackBelow! ? n : 1;
    if (width >= _minCell * n) return n; // everything fits side by side
    if (n >= 2 && width >= _twoColMin) return 2; // two-up on mid-size panes
    return 1; // stacked
  }

  // Gaps live as a left inset *inside* each non-first cell rather than as
  // reserved SizedBoxes, so Expanded divides the full row width. This keeps
  // flex boundaries identical across rows with different field counts — a
  // flex:2 cell then spans exactly two flex:1 tracks plus the gap between them,
  // so e.g. "Website" lines up over "ABN".
  Widget _visualRow(List<Field> cells) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [for (var i = 0; i < cells.length; i++) _cell(cells[i], i == 0)],
  );

  Widget _cell(Field f, bool first) {
    final child = first
        ? f.child
        : Padding(
            padding: const EdgeInsets.only(left: AppTokens.spaceSm),
            child: f.child,
          );
    return f.flex > 0 ? Expanded(flex: f.flex, child: child) : child;
  }
}

/// A titled group of [FieldRow]s — the section unit of a branding editor form
/// (e.g. "Business", "Payment"). Rows are evenly spaced; groups are spaced by
/// the caller.
class FieldGroup extends StatelessWidget {
  const FieldGroup(this.title, this.rows, {super.key});
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: AppTokens.spaceMd),
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const SizedBox(height: AppTokens.spaceMd),
        rows[i],
      ],
    ],
  );
}

/// The app's compact switch — a shrunk [Switch] used for every inline toggle in
/// the editors (invoice-inclusion defaults, the "Default" flag). Small and
/// tap-target-tight so it reads as a control beside a label without dominating
/// the row. Single source of switch sizing so they stay uniform app-wide.
Widget appSwitch({
  required bool value,
  required ValueChanged<bool> onChanged,
}) => Transform.scale(
  scale: 0.7,
  child: Switch(
    value: value,
    onChanged: onChanged,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  ),
);

/// A label with the shared [appSwitch] beside it — the inline toggle used
/// throughout the branding editors.
Widget labelledSwitch({
  required String label,
  required bool value,
  required ValueChanged<bool> onChanged,
}) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(label),
    const SizedBox(width: AppTokens.space2xs),
    appSwitch(value: value, onChanged: onChanged),
  ],
);

/// The compact "Default" toggle shared by the branding editors.
Widget brandingDefaultToggle({
  required bool value,
  required ValueChanged<bool> onChanged,
}) => labelledSwitch(label: 'Default', value: value, onChanged: onChanged);

/// A column whose group title sits directly above its single [child] control
/// cluster. Drop two of these into a [FieldRow] to place independently-titled
/// clusters side by side, each header aligned over its own controls — the
/// split-header layout (e.g. "Profile name" | "Template").
Widget titledField(BuildContext context, String title, Widget child) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(title, style: Theme.of(context).textTheme.bodyMedium),
    const SizedBox(height: AppTokens.spaceMd),
    child,
  ],
);

/// Title on the left, actions on the right — mirrors the theme editor header so
/// every branding editor opens the same way. When [name] is set (the entity
/// being edited) it's appended after the action label in the brand colour, so
/// it's clear *what* you're editing (e.g. "Edit template : Acme Retainer").
Widget editorHeader({
  required BuildContext context,
  required String title,
  required bool isEdit,
  required VoidCallback onDelete,
  required VoidCallback onCancel,
  required VoidCallback onSave,
  String? name,
  // When false, the entity is being viewed rather than edited: the form is
  // hidden (see EditorShell) and the only action is entering edit mode.
  bool editing = true,
  VoidCallback? onEdit,
}) {
  final theme = Theme.of(context);
  final hasName = name != null && name.trim().isNotEmpty;
  final titleWidget = Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title, style: theme.textTheme.titleLarge),
      if (hasName)
        Flexible(
          child: Text(
            ' : ${name.trim()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
    ],
  );
  final actions = <Widget>[
    if (!editing)
      FilledButton(onPressed: onEdit, child: const Text('Edit'))
    else ...[
      if (isEdit)
        TextButton.icon(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, size: AppTokens.iconSm),
          label: const Text('Delete'),
        ),
      OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
      FilledButton(onPressed: onSave, child: const Text('Save')),
    ],
  ];
  return LayoutBuilder(
    builder: (context, c) {
      // Narrow: title on its own line with the actions beneath, right-aligned
      // and free to wrap, so the header never overflows on a phone-width pane.
      if (c.maxWidth < 480) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            titleWidget,
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceXs,
              children: actions,
            ),
          ],
        );
      }
      // Title takes the slack (ellipsising a long name) and pushes actions right.
      return Row(
        children: [
          Expanded(child: titleWidget),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: AppTokens.spaceSm),
            actions[i],
          ],
        ],
      );
    },
  );
}

/// The shared skeleton for a branding content-pane editor: a pinned
/// [editorHeader] over a scrolling body (form + live preview), wired for
/// keyboard use — Ctrl/Cmd+S saves, Esc blurs a focused field then cancels.
/// Every editor returns one of these so they open, scroll, and key alike.
class EditorShell extends StatefulWidget {
  const EditorShell({
    super.key,
    required this.title,
    required this.isEdit,
    required this.onDelete,
    required this.onCancel,
    required this.onSave,
    required this.children,
    this.name,
    this.editing = true,
    this.onEdit,
  });

  final String title;
  final String? name;
  final bool isEdit;
  final VoidCallback onDelete;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  // See editorHeader — false shows a read-only view with a single Edit action
  // instead of Delete/Cancel/Save, and suspends the save/cancel keybindings.
  final bool editing;
  final VoidCallback? onEdit;

  /// Body content below the header — typically the form then the preview.
  final List<Widget> children;

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> {
  final _root = FocusNode(debugLabel: 'EditorShell');

  @override
  void dispose() {
    _root.dispose();
    super.dispose();
  }

  bool get _editingText {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _escape() {
    // First Esc drops out of a field; a second (nothing editing) cancels — so a
    // stray Esc mid-edit never discards the form. Mirrors the tracker's Esc.
    if (_editingText) {
      FocusManager.instance.primaryFocus?.unfocus();
      _root.requestFocus();
    } else {
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      child: Focus(
        focusNode: _root,
        // Only steal focus when there's a form to type into — grabbing it in
        // view mode would yank keyboard focus away from the panel every time
        // a row is opened, breaking its j/k navigation.
        autofocus: widget.editing,
        skipTraversal: true,
        child: CallbackShortcuts(
          bindings: {
            if (widget.editing) ...{
              const SingleActivator(LogicalKeyboardKey.escape): _escape,
              const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  widget.onSave,
              const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
                  widget.onSave,
            } else if (widget.onEdit != null)
              const SingleActivator(LogicalKeyboardKey.keyE): widget.onEdit!,
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Matches the scroll body's right inset below (see its comment)
              // so the header's actions align with the form/preview's right
              // edge instead of overhanging past it.
              Padding(
                padding: const EdgeInsets.only(right: AppTokens.spaceMd),
                child: editorHeader(
                  context: context,
                  title: widget.title,
                  name: widget.name,
                  isEdit: widget.isEdit,
                  onDelete: widget.onDelete,
                  onCancel: widget.onCancel,
                  onSave: widget.onSave,
                  editing: widget.editing,
                  onEdit: widget.onEdit,
                ),
              ),
              Expanded(
                // Top inset lives inside the scroll (rather than a SizedBox
                // above it) so the first row's floating label — which paints
                // above the field box on an OutlineInputBorder — has room and
                // isn't clipped by the scroll viewport's top edge. Right inset
                // clears the desktop scrollbar off the fields'/preview's border.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    top: AppTokens.spaceMd,
                    right: AppTokens.spaceMd,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
