import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/invoices/editor_common.dart';
import 'package:timedart/features/invoices/editor_session.dart';
import 'package:timedart/features/invoices/invoice_document.dart';
import 'package:timedart/features/invoices/invoice_preview.dart';
import 'package:timedart/widgets/color_picker.dart';
import 'package:timedart/widgets/confirm_dialog.dart';

/// Content-pane editor for an invoice [InvoiceTemplate] — colours and font (the
/// logo lives on the profile now) — as a compact settings block above a
/// full-width live [InvoicePreview] (the
/// controls run horizontally so the preview gets the height). Creates when
/// [initial] is null, otherwise edits. Mirrors [InvoiceView]'s shape: a State
/// that talks to the db and calls [onDone] to return to the previous pane.
class TemplateEditor extends StatefulWidget {
  const TemplateEditor({
    super.key,
    required this.db,
    required this.onDone,
    required this.onSessionReady,
    this.initial,
    this.startEditing = false,
  });
  final AppDatabase db;
  final VoidCallback onDone;
  // Hands the shell this editor's EditorSession, so its unsaved-changes guard
  // reads one lifecycle object (dirty + save) rather than loose callbacks.
  final ValueChanged<EditorSession> onSessionReady;
  final InvoiceTemplate? initial;
  // Open straight into edit mode (the 'e' shortcut) instead of the read-only
  // view an existing template otherwise opens to.
  final bool startEditing;

  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<TemplateEditor> {
  // Seed defaults for a new template mirror the timedart look (neutral surface).
  static const _defaults = (
    bg: 0xFF11140E,
    surface: 0xFF23241F,
    primary: 0xFF69E228,
    text: AppTokens.colorOffWhiteArgb, // logo off-white
    accent: 0xFF2E6C0F,
  );

  // The fonts the template picker offers. Single source of truth: the dropdown
  // items are built from this list, and a loaded template's stored family is
  // validated against it (a value the picker can't show would trip
  // DropdownButton's one-matching-item assertion). Legacy rows written before
  // a font change fall back to the first entry and self-heal on next save.
  static const _fontFamilies = ['Outfit'];

  late final TextEditingController _name;
  late int _bg, _surface, _primary, _text;
  // Retained (loaded + saved unchanged) but no longer user-editable or drawn on
  // the invoice — kept so the column round-trips and a colour can be re-added
  // later without a migration or data loss.
  late int _accent;
  late String _fontFamily;
  late bool _isDefault;

  // The dirty/save/rebaseline lifecycle. Dirty is a real diff of the current
  // snapshot against the baseline (last-saved, or starting values) — reverting
  // a field to where it started clears dirty again. A successful save while
  // viewing-then-editing an existing template moves the baseline forward
  // without the shell re-mounting this widget.
  late final EditorSession<_TemplateSnapshot> _session;

  late final Future<InvoiceProfile?> _sampleProfile;

  // An existing template opens read-only; a new one has nothing to view, so
  // it opens straight into editing.
  late bool _editing;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _name = TextEditingController(text: t?.name ?? '');
    _bg = t?.colorBackground ?? _defaults.bg;
    _surface = t?.colorSurface ?? _defaults.surface;
    _primary = t?.colorPrimary ?? _defaults.primary;
    _text = t?.colorText ?? _defaults.text;
    _accent = t?.colorAccent ?? _defaults.accent;
    _fontFamily = _fontFamilies.contains(t?.fontFamily)
        ? t!.fontFamily
        : _fontFamilies.first;
    _isDefault = t?.isDefault ?? false;
    _editing = !_isEdit || widget.startEditing;
    _session = EditorSession(snapshot: _snapshot, persist: _persist);
    widget.onSessionReady(_session);
    // A profile is needed only to dress the sample invoice; the default (or
    // first) is representative enough for a look preview.
    _sampleProfile = widget.db.watchProfiles().first.then((list) {
      for (final p in list) {
        if (p.isDefault) return p;
      }
      return list.isEmpty ? null : list.first;
    });
  }

  // The edited state as one comparable value — the field-by-field diff lives in
  // _TemplateSnapshot's `==`, not in a hand-rolled _computeDirty.
  _TemplateSnapshot _snapshot() => _TemplateSnapshot(
    name: _name.text.trim(),
    bg: _bg,
    surface: _surface,
    primary: _primary,
    text: _text,
    accent: _accent,
    fontFamily: _fontFamily,
    isDefault: _isDefault,
  );

  @override
  void dispose() {
    _name.dispose();
    _session.dispose();
    super.dispose();
  }

  InvoiceTemplate _draft() => InvoiceTemplate(
    id: widget.initial?.id ?? '',
    name: _name.text.trim().isEmpty ? 'Untitled' : _name.text.trim(),
    colorBackground: _bg,
    colorSurface: _surface,
    colorPrimary: _primary,
    colorText: _text,
    colorAccent: _accent,
    fontFamily: _fontFamily,
    isDefault: _isDefault,
    // Transient preview object (never persisted); timestamps are placeholders.
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  TemplatesCompanion _companion() => TemplatesCompanion(
    name: Value(_name.text.trim()),
    colorBackground: Value(_bg),
    colorSurface: Value(_surface),
    colorPrimary: Value(_primary),
    colorText: Value(_text),
    colorAccent: Value(_accent),
    fontFamily: Value(_fontFamily),
    // isDefault is driven through setDefaultTemplate (a transaction), not here,
    // so we never end up with two defaults.
  );

  /// Validates and persists, returning whether it succeeded — used both by
  /// the editor's own Save action and by the shell's unsaved-changes dialog.
  Future<bool> _persist() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A template name is required.')),
      );
      return false;
    }
    try {
      String id;
      if (_isEdit) {
        id = widget.initial!.id;
        await widget.db.updateTemplateById(id, _companion());
      } else {
        id = await widget.db.insertTemplate(_companion());
      }
      // Apply the default flag through the transaction that clears the others.
      if (_isDefault) await widget.db.setDefaultTemplate(id);
      // The session rebaselines on success, so dirty clears without needing
      // widget.initial to change (this widget stays mounted).
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save template: $e')));
      }
      return false;
    }
  }

  Future<void> _save() async {
    if (!await _session.save() || !mounted) return;
    if (_isEdit) {
      setState(() => _editing = false);
    } else {
      widget.onDone();
    }
  }

  // Discards in-progress edits and returns to viewing (warning first if
  // there's anything to lose). A new (unsaved) template has nothing to view,
  // so a discard leaves the screen as before.
  Future<void> _cancel() async {
    if (_session.isDirty) {
      final action = await confirmUnsavedChanges(context);
      if (action == null) return; // stay editing
      if (action == UnsavedChangesAction.save) {
        await _save();
        return;
      }
      // discard: fall through to the revert below
    }
    if (!mounted) return;
    if (!_isEdit) {
      widget.onDone();
      return;
    }
    final b = _session.baseline;
    setState(() {
      _name.text = b.name;
      _bg = b.bg;
      _surface = b.surface;
      _primary = b.primary;
      _text = b.text;
      _accent = b.accent;
      _fontFamily = b.fontFamily;
      _isDefault = b.isDefault;
      _editing = false;
    });
    _session.recompute();
  }

  Future<void> _delete() async {
    final t = widget.initial!;
    final ok = await confirmDelete(
      context,
      title: 'Delete template?',
      message: '"${t.name}" will be removed.',
    );
    if (!ok) return;
    try {
      await widget.db.deleteTemplate(t.id);
      if (mounted) widget.onDone();
    } catch (_) {
      // FK restrict: a profile still references this template.
      if (mounted) {
        await showInfoDialog(
          context,
          title: "Can't delete template",
          message:
              'A profile still uses this template. Point those profiles at '
              'another template first.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Header pinned; settings block over a full-width live preview, the two
    // scrolling together as one content pane.
    return EditorShell(
      title: _editing
          ? (_isEdit ? 'Edit template' : 'New template')
          : 'Template',
      name: _isEdit ? _name.text : null,
      isEdit: _isEdit,
      editing: _editing,
      onEdit: () => setState(() => _editing = true),
      onDelete: _delete,
      onCancel: _cancel,
      onSave: _save,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _editing ? _settings() : const SizedBox.shrink(),
        ),
        if (_editing) const SizedBox(height: AppTokens.spaceMd),
        _preview(),
      ],
    );
  }

  // A shared breakpoint so both settings rows collapse to a stacked column
  // together — keeping Name over Background, Font over Surface aligned above it.
  static const double _gridStackBelow = AppTokens.breakpointMd;

  Widget _nameField() => EditorTextField(
    controller: _name,
    label: 'Name',
    persistentLabel: true,
    onChanged: (_) => setState(_session.recompute),
  );

  Widget _fontField() => EditorDropdown<String>(
    label: 'Font',
    value: _fontFamily,
    items: [
      for (final f in _fontFamilies)
        DropdownMenuItem(value: f, child: Text(f)),
    ],
    onChanged: (v) => setState(() {
      _fontFamily = v ?? _fontFamily;
      _session.recompute();
    }),
  );

  Widget _defaultToggle() => brandingDefaultToggle(
    value: _isDefault,
    onChanged: (v) => setState(() {
      _isDefault = v;
      _session.recompute();
    }),
  );

  Widget _settings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name spans two tracks (over Background + Surface), Font takes one
        // (over Primary), and the Default toggle the last (over Text),
        // right-aligned — so the row's four tracks line up with the colours.
        FieldRow(stackBelow: _gridStackBelow, [
          Field(flex: 2, _nameField()),
          Field(_fontField()),
          Field(Align(alignment: Alignment.centerRight, child: _defaultToggle())),
        ]),
        const SizedBox(height: AppTokens.spaceSm),
        _colorRow(),
      ],
    );
  }

  // The four editable colours.
  Widget _colorRow() {
    final fields = [
      _colorField('Background', _bg, (v) => _bg = v),
      _colorField('Surface', _surface, (v) => _surface = v),
      _colorField('Primary', _primary, (v) => _primary = v),
      _colorField('Text', _text, (v) => _text = v),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        // Wide: four quarter-columns via a FieldRow, so the tracks line up
        // exactly with the Name/Font row above (same full-width-÷-flex maths).
        if (c.maxWidth >= _gridStackBelow) {
          return FieldRow([for (final f in fields) Field(f)]);
        }
        // Narrow: a forced 2×2 grid rather than a tall single stack — a plain
        // FieldRow would drop to one column below its two-column floor, but the
        // compact hex fields read fine two-up down to phone width.
        final rows = <Widget>[];
        for (var i = 0; i < fields.length; i += 2) {
          if (i > 0) rows.add(const SizedBox(height: AppTokens.spaceSm));
          final chunk = fields.sublist(i, i + 2);
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < chunk.length; j++) ...[
                  if (j > 0) const SizedBox(width: AppTokens.spaceSm),
                  Expanded(child: chunk[j]),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  Widget _colorField(String label, int value, void Function(int) set) {
    void apply(int v) => setState(() {
      set(v);
      _session.recompute();
    });
    return _ColorField(
      value: value,
      decoration: fieldDecoration(
        context,
        label,
        prefixText: '#',
        // Tapping the swatch opens the visual picker; the hex field stays for
        // anyone who'd rather type a code. Either path syncs the other. The
        // whole 48×48 leading square is the tap target (a bare swatch is far
        // below the min touch size) — the visible swatch is centred within it.
        prefixIcon: Tooltip(
          message: 'Pick colour',
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            onTap: () async {
              final picked = await showColorPicker(
                context,
                initial: value,
                label: label,
              );
              if (picked != null) apply(picked);
            },
            child: SizedBox(
              width: AppTokens.minTouchTarget,
              height: AppTokens.minTouchTarget,
              child: Center(
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Color(value),
                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                    border: Border.all(color: AppTokens.colorBorder),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      onChanged: apply,
    );
  }

  Widget _preview() {
    return FutureBuilder<InvoiceProfile?>(
      future: _sampleProfile,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final profile = snap.data;
        if (profile == null) {
          return SizedBox(
            height: 240,
            child: Center(
              child: Text(
                'Add a profile to preview.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }
        final doc = sampleInvoiceDocument(
          profile: profile,
          issueDate: DateTime.now(),
        );
        // A bordered frame holding an A4 page preview. scrollable: false — the
        // editor's outer scroll owns vertical scrolling.
        return brandingPreviewFrame(
          child: invoicePreviewPage(
            doc: doc,
            template: _draft(),
            scrollable: false,
          ),
        );
      },
    );
  }
}

// The template editor's dirty baseline — every edited field with an explicit
// `==`, so the EditorSession diff is a single value comparison.
@immutable
class _TemplateSnapshot {
  const _TemplateSnapshot({
    required this.name,
    required this.bg,
    required this.surface,
    required this.primary,
    required this.text,
    required this.accent,
    required this.fontFamily,
    required this.isDefault,
  });
  final String name;
  final int bg, surface, primary, text, accent;
  final String fontFamily;
  final bool isDefault;

  @override
  bool operator ==(Object other) =>
      other is _TemplateSnapshot &&
      other.name == name &&
      other.bg == bg &&
      other.surface == surface &&
      other.primary == primary &&
      other.text == text &&
      other.accent == accent &&
      other.fontFamily == fontFamily &&
      other.isDefault == isDefault;

  @override
  int get hashCode => Object.hash(
    name,
    bg,
    surface,
    primary,
    text,
    accent,
    fontFamily,
    isDefault,
  );
}

// --- A #RRGGBB hex input (swatch supplied via [decoration] as a prefix). Opaque
// colours (alpha forced FF). ---
class _ColorField extends StatefulWidget {
  const _ColorField({
    required this.value,
    required this.decoration,
    required this.onChanged,
  });
  final int value; // ARGB
  final InputDecoration decoration;
  final ValueChanged<int> onChanged;

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  late final TextEditingController _hex;

  static String _toHex(int argb) =>
      (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  @override
  void initState() {
    super.initState();
    _hex = TextEditingController(text: _toHex(widget.value));
  }

  @override
  void didUpdateWidget(_ColorField old) {
    super.didUpdateWidget(old);
    // Reflect external changes without stomping mid-edit.
    if (widget.value != old.value &&
        _toHex(widget.value) != _hex.text.toUpperCase()) {
      _hex.text = _toHex(widget.value);
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _apply(String raw) {
    var s = raw.trim().replaceAll('#', '');
    if (s.length == 6) {
      final v = int.tryParse(s, radix: 16);
      if (v != null) widget.onChanged(0xFF000000 | v);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Width-agnostic — the parent grid flexes each field to fill its column.
    return TextField(
      controller: _hex,
      decoration: widget.decoration,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
        LengthLimitingTextInputFormatter(6),
      ],
      onChanged: _apply,
    );
  }
}
