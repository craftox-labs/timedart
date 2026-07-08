import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/invoices/editor_common.dart';
import 'package:time_tracker/features/invoices/invoice_document.dart';
import 'package:time_tracker/features/invoices/invoice_preview.dart';
import 'package:time_tracker/widgets/confirm_dialog.dart';

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
    required this.onDirtyChanged,
    required this.onSaveHandleReady,
    this.initial,
    this.startEditing = false,
  });
  final AppDatabase db;
  final VoidCallback onDone;
  final ValueChanged<bool> onDirtyChanged;
  final ValueChanged<Future<bool> Function()> onSaveHandleReady;
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
    text: 0xFFE8F5E0,
    accent: 0xFF2E6C0F,
  );

  // The fonts the template picker offers. Single source of truth: the dropdown
  // items are built from this list, and a loaded template's stored family is
  // validated against it (a value the picker can't show would trip
  // DropdownButton's one-matching-item assertion). Legacy rows written before
  // a font change fall back to the first entry and self-heal on next save.
  static const _fontFamilies = ['Mona'];

  late final TextEditingController _name;
  late int _bg, _surface, _primary, _text, _accent;
  late String _fontFamily;
  late bool _isDefault;

  // The last-saved (or, for a new template, starting-blank) values. Dirty is
  // diffed against these rather than [widget.initial] directly, because a
  // successful save while viewing-then-editing an existing template moves the
  // baseline forward without the shell re-mounting this widget.
  late String _baseName;
  late int _baseBg, _baseSurface, _basePrimary, _baseText, _baseAccent;
  late String _baseFontFamily;
  late bool _baseIsDefault;

  late final Future<InvoiceProfile?> _sampleProfile;

  bool _dirty = false;
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
    _baseName = _name.text.trim();
    _baseBg = _bg;
    _baseSurface = _surface;
    _basePrimary = _primary;
    _baseText = _text;
    _baseAccent = _accent;
    _baseFontFamily = _fontFamily;
    _baseIsDefault = _isDefault;
    _editing = !_isEdit || widget.startEditing;
    // A profile is needed only to dress the sample invoice; the default (or
    // first) is representative enough for a look preview.
    _sampleProfile = widget.db.watchProfiles().first.then((list) {
      for (final p in list) {
        if (p.isDefault) return p;
      }
      return list.isEmpty ? null : list.first;
    });
    widget.onSaveHandleReady(_persist);
  }

  // Real diff against the baseline, not a touched-flag: reverting a field
  // back to where it started clears dirty again.
  bool _computeDirty() {
    if (_name.text.trim() != _baseName) return true;
    if (_bg != _baseBg) return true;
    if (_surface != _baseSurface) return true;
    if (_primary != _basePrimary) return true;
    if (_text != _baseText) return true;
    if (_accent != _baseAccent) return true;
    if (_fontFamily != _baseFontFamily) return true;
    if (_isDefault != _baseIsDefault) return true;
    return false;
  }

  void _checkDirty() {
    final d = _computeDirty();
    if (d != _dirty) {
      _dirty = d;
      widget.onDirtyChanged(d);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  InvoiceTemplate _draft() => InvoiceTemplate(
    id: widget.initial?.id ?? 0,
    name: _name.text.trim().isEmpty ? 'Untitled' : _name.text.trim(),
    colorBackground: _bg,
    colorSurface: _surface,
    colorPrimary: _primary,
    colorText: _text,
    colorAccent: _accent,
    fontFamily: _fontFamily,
    isDefault: _isDefault,
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
      int id;
      if (_isEdit) {
        id = widget.initial!.id;
        await widget.db.updateTemplateById(id, _companion());
      } else {
        id = await widget.db.insertTemplate(_companion());
      }
      // Apply the default flag through the transaction that clears the others.
      if (_isDefault) await widget.db.setDefaultTemplate(id);
      // The just-saved values become the new baseline — dirty clears without
      // needing widget.initial to change (this widget stays mounted).
      _baseName = _name.text.trim();
      _baseBg = _bg;
      _baseSurface = _surface;
      _basePrimary = _primary;
      _baseText = _text;
      _baseAccent = _accent;
      _baseFontFamily = _fontFamily;
      _baseIsDefault = _isDefault;
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
    if (!await _persist() || !mounted) return;
    if (_isEdit) {
      setState(() => _editing = false);
      _checkDirty();
    } else {
      widget.onDone();
    }
  }

  // Discards in-progress edits and returns to viewing (warning first if
  // there's anything to lose). A new (unsaved) template has nothing to view,
  // so a discard leaves the screen as before.
  Future<void> _cancel() async {
    if (_dirty) {
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
    setState(() {
      _name.text = _baseName;
      _bg = _baseBg;
      _surface = _baseSurface;
      _primary = _basePrimary;
      _text = _baseText;
      _accent = _baseAccent;
      _fontFamily = _baseFontFamily;
      _isDefault = _baseIsDefault;
      _editing = false;
    });
    _checkDirty();
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
      title: _editing ? (_isEdit ? 'Edit template' : 'New template') : 'Template',
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

  // Shared decoration so every text/dropdown input is the same height.
  Widget _settings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top row spans the same 5 tracks as the colours below: Name and Font
        // take one each over Background·Surface, and the Default toggle fills the
        // trailing three (right-aligned) over Primary·Text·Accent. (The logo
        // control used to sit here; it now lives on the profile editor.)
        FieldRow(
          stackBelow: _gridStackBelow,
          [
            Field(
              EditorTextField(
                controller: _name,
                label: 'Name',
                persistentLabel: true,
                onChanged: (_) => setState(_checkDirty),
              ),
            ),
            Field(
              EditorDropdown<String>(
                label: 'Font',
                value: _fontFamily,
                items: [
                  for (final f in _fontFamilies)
                    DropdownMenuItem(value: f, child: Text(f)),
                ],
                onChanged: (v) => setState(() {
                  _fontFamily = v ?? _fontFamily;
                  _checkDirty();
                }),
              ),
            ),
            Field(
              flex: 3,
              Align(
                alignment: Alignment.centerRight,
                child: brandingDefaultToggle(
                  value: _isDefault,
                  onChanged: (v) => setState(() {
                    _isDefault = v;
                    _checkDirty();
                  }),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceSm),
        FieldRow(
          stackBelow: _gridStackBelow,
          [
            Field(_colorField('Background', _bg, (v) => _bg = v)),
            Field(_colorField('Surface', _surface, (v) => _surface = v)),
            Field(_colorField('Primary', _primary, (v) => _primary = v)),
            Field(_colorField('Text', _text, (v) => _text = v)),
            Field(_colorField('Accent', _accent, (v) => _accent = v)),
          ],
        ),
      ],
    );
  }

  Widget _colorField(String label, int value, void Function(int) set) =>
      _ColorField(
        value: value,
        decoration: fieldDecoration(
          label,
          prefixText: '#',
          prefixIcon: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceXs),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Color(value),
                borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                border: Border.all(color: AppTokens.colorBorder),
              ),
            ),
          ),
        ),
        onChanged: (v) => setState(() {
          set(v);
          _checkDirty();
        }),
      );

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
          return const SizedBox(
            height: 240,
            child: Center(child: Text('Add a profile to preview.')),
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
