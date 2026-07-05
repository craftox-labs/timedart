import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/invoices/editor_common.dart';
import 'package:time_tracker/features/invoices/invoice_document.dart';
import 'package:time_tracker/features/invoices/invoice_preview.dart';
import 'package:time_tracker/widgets/confirm_dialog.dart';

/// Content-pane editor for an invoice [InvoiceTemplate] — colours, logo, font —
/// as a compact settings block above a full-width live [InvoicePreview] (the
/// controls run horizontally so the preview gets the height). Creates when
/// [initial] is null, otherwise edits. Mirrors [InvoiceView]'s shape: a State
/// that talks to the db and calls [onDone] to return to the previous pane.
class TemplateEditor extends StatefulWidget {
  const TemplateEditor({
    super.key,
    required this.db,
    required this.onDone,
    this.initial,
  });
  final AppDatabase db;
  final VoidCallback onDone;
  final InvoiceTemplate? initial;

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

  late final TextEditingController _name;
  late int _bg, _surface, _primary, _text, _accent;
  Uint8List? _logo;
  String? _logoMime;
  late String _fontFamily;
  late bool _isDefault;

  late final Future<InvoiceProfile?> _sampleProfile;

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
    _logo = t?.logo;
    _logoMime = t?.logoMime;
    _fontFamily = t?.fontFamily ?? 'Urbanist';
    _isDefault = t?.isDefault ?? false;
    // A profile is needed only to dress the sample invoice; the default (or
    // first) is representative enough for a look preview.
    _sampleProfile = widget.db.watchProfiles().first.then((list) {
      for (final p in list) {
        if (p.isDefault) return p;
      }
      return list.isEmpty ? null : list.first;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  InvoiceTemplate _draft() => InvoiceTemplate(
    id: widget.initial?.id ?? 0,
    name: _name.text.trim().isEmpty ? 'Untitled' : _name.text.trim(),
    logo: _logo,
    logoMime: _logoMime,
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
    logo: Value(_logo),
    logoMime: Value(_logoMime),
    colorBackground: Value(_bg),
    colorSurface: Value(_surface),
    colorPrimary: Value(_primary),
    colorText: Value(_text),
    colorAccent: Value(_accent),
    fontFamily: Value(_fontFamily),
    // isDefault is driven through setDefaultTemplate (a transaction), not here,
    // so we never end up with two defaults.
  );

  Future<void> _pickLogo() async {
    const group = XTypeGroup(
      label: 'Image',
      extensions: ['png', 'jpg', 'jpeg'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    setState(() {
      _logo = bytes;
      _logoMime = name.endsWith('.png') ? 'image/png' : 'image/jpeg';
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A template name is required.')),
      );
      return;
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
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save template: $e')));
      }
    }
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
      title: _isEdit ? 'Edit template' : 'New template',
      name: _isEdit ? _name.text : null,
      isEdit: _isEdit,
      onDelete: _delete,
      onCancel: widget.onDone,
      onSave: _save,
      children: [
        _settings(),
        const SizedBox(height: AppTokens.spaceMd),
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
        // take one each, the (wider) Logo control two, the Default toggle the
        // trailing one — so Name·Font·Logo·Default sit over Background·Surface·
        // (Primary+Text)·Accent.
        FieldRow(
          stackBelow: _gridStackBelow,
          [
            Field(
              EditorTextField(
                controller: _name,
                label: 'Name',
                persistentLabel: true,
                onChanged: (_) => setState(() {}),
              ),
            ),
            Field(
              EditorDropdown<String>(
                label: 'Font',
                value: _fontFamily,
                items: const [
                  DropdownMenuItem(value: 'Urbanist', child: Text('Urbanist')),
                ],
                onChanged: (v) =>
                    setState(() => _fontFamily = v ?? _fontFamily),
              ),
            ),
            Field(
              flex: 2,
              _LogoField(
                logo: _logo,
                onPick: _pickLogo,
                onRemove: _logo == null
                    ? null
                    : () => setState(() {
                        _logo = null;
                        _logoMime = null;
                      }),
              ),
            ),
            Field(
              Align(
                alignment: Alignment.centerRight,
                child: brandingDefaultToggle(
                  value: _isDefault,
                  onChanged: (v) => setState(() => _isDefault = v),
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
        onChanged: (v) => setState(() => set(v)),
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

// --- Logo picker: thumbnail (or placeholder) + Choose / Remove. ---
class _LogoField extends StatelessWidget {
  const _LogoField({required this.logo, required this.onPick, this.onRemove});
  final Uint8List? logo;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // Compact and inline so it sits in the top settings row without adding
    // height: a small thumbnail + Choose (+ Remove when a logo is set).
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          // Matches the dense input height so the pill lines up with the fields.
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
            border: Border.all(color: AppTokens.colorBorder),
          ),
          child: logo == null
              ? Icon(
                  Icons.image_outlined,
                  size: AppTokens.iconSm,
                  color: t.colorScheme.onSurfaceVariant,
                )
              : Padding(
                  padding: const EdgeInsets.all(AppTokens.space3xs),
                  child: Image.memory(logo!, fit: BoxFit.contain),
                ),
        ),
        const SizedBox(width: AppTokens.spaceXs),
        TextButton(onPressed: onPick, child: const Text('Logo…')),
        if (onRemove != null)
          IconButton(
            icon: const Icon(Icons.close, size: AppTokens.iconSm),
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove logo',
            onPressed: onRemove,
          ),
      ],
    );
  }
}
