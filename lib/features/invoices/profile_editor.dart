import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/invoices/editor_common.dart';
import 'package:time_tracker/features/invoices/invoice_document.dart';
import 'package:time_tracker/features/invoices/invoice_preview.dart';
import 'package:time_tracker/widgets/confirm_dialog.dart';

/// Content-pane editor for an invoice [InvoiceProfile] — business identity,
/// payment details, currency and optional tax — with a live A4 preview below the
/// form (dressed with the default theme). Creates when [initial] is null.
class ProfileEditor extends StatefulWidget {
  const ProfileEditor({
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
  final InvoiceProfile? initial;
  // Open straight into edit mode (the 'e' shortcut) instead of the read-only
  // view an existing profile otherwise opens to.
  final bool startEditing;

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  // One controller per text field, keyed for the draft + companion.
  late final Map<String, TextEditingController> _c;
  late bool _isDefault;
  // The template (visual style) this profile renders with; null → default.
  int? _templateId;
  // Available templates for the picker + preview, loaded once.
  List<InvoiceTemplate> _templates = const [];

  bool _dirty = false;
  // Reassigned after every successful save (the new baseline) — not `final`.
  late Map<String, String> _initialTexts;
  late bool _initialIsDefault;
  // Resolved once templates finish loading — see initState. Comparing against
  // the pre-resolution `null` would falsely flag the auto-picked default
  // template as a user edit.
  int? _initialTemplateId;

  // An existing profile opens read-only; a new one has nothing to view, so it
  // opens straight into editing.
  late bool _editing;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _c = {for (final f in _fields) f: TextEditingController()};
    if (p != null) {
      _c['name']!.text = p.name;
      _c['businessName']!.text = p.businessName;
      _c['email']!.text = p.email ?? '';
      _c['phone']!.text = p.phone ?? '';
      _c['website']!.text = p.website ?? '';
      _c['address']!.text = p.address ?? '';
      _c['abn']!.text = p.abn ?? '';
      _c['payeeName']!.text = p.payeeName ?? '';
      _c['bankName']!.text = p.bankName ?? '';
      _c['bankBsb']!.text = p.bankBsb ?? '';
      _c['bankAccount']!.text = p.bankAccount ?? '';
      _c['swift']!.text = p.swift ?? '';
      _c['paymentLink']!.text = p.paymentLink ?? '';
      _c['currency']!.text = p.currency;
      _c['taxLabel']!.text = p.taxLabel ?? '';
      _c['taxRate']!.text = p.taxRate?.toString() ?? '';
    } else {
      _c['currency']!.text = 'USD';
    }
    _isDefault = p?.isDefault ?? false;
    _templateId = p?.templateId;
    _initialTexts = {for (final f in _fields) f: _c[f]!.text};
    _initialIsDefault = _isDefault;
    _editing = !_isEdit || widget.startEditing;
    widget.onSaveHandleReady(_persist);
    // Load templates for the picker + preview. Default the selection to the
    // default template when the profile hasn't chosen one, so the picker always
    // reflects what will render.
    widget.db.watchTemplates().first.then((list) {
      if (!mounted) return;
      setState(() {
        _templates = list;
        _templateId ??= _defaultTemplate()?.id;
        // Resolved after any auto-pick, so the baseline reflects what's on
        // screen before the user has touched anything.
        _initialTemplateId = _templateId;
      });
    });
  }

  bool _computeDirty() {
    for (final f in _fields) {
      if (_c[f]!.text != _initialTexts[f]) return true;
    }
    if (_isDefault != _initialIsDefault) return true;
    if (_templateId != _initialTemplateId) return true;
    return false;
  }

  void _checkDirty() {
    final d = _computeDirty();
    if (d != _dirty) {
      _dirty = d;
      widget.onDirtyChanged(d);
    }
  }

  static const _fields = [
    'name',
    'businessName',
    'email',
    'phone',
    'website',
    'address',
    'abn',
    'payeeName',
    'bankName',
    'bankBsb',
    'bankAccount',
    'swift',
    'paymentLink',
    'currency',
    'taxLabel',
    'taxRate',
  ];

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _t(String k) => _c[k]!.text.trim();
  String? _n(String k) => _t(k).isEmpty ? null : _t(k);

  // The template the picker/preview resolve to: the chosen one, else the
  // default, else the first (null when none exist yet).
  InvoiceTemplate? _defaultTemplate() {
    for (final t in _templates) {
      if (t.isDefault) return t;
    }
    return _templates.isEmpty ? null : _templates.first;
  }

  InvoiceTemplate? _selectedTemplate() {
    for (final t in _templates) {
      if (t.id == _templateId) return t;
    }
    return _defaultTemplate();
  }

  InvoiceProfile _draft() => InvoiceProfile(
    id: widget.initial?.id ?? 0,
    name: _t('name').isEmpty ? 'Untitled' : _t('name'),
    businessName: _t('businessName'),
    email: _n('email'),
    phone: _n('phone'),
    website: _n('website'),
    address: _n('address'),
    abn: _n('abn'),
    payeeName: _n('payeeName'),
    bankName: _n('bankName'),
    bankBsb: _n('bankBsb'),
    bankAccount: _n('bankAccount'),
    swift: _n('swift'),
    paymentLink: _n('paymentLink'),
    currency: _t('currency').isEmpty ? 'USD' : _t('currency'),
    taxLabel: _n('taxLabel'),
    taxRate: double.tryParse(_t('taxRate')),
    isDefault: _isDefault,
    templateId: _templateId,
  );

  ProfilesCompanion _companion() => ProfilesCompanion(
    name: Value(_t('name')),
    businessName: Value(_t('businessName')),
    email: Value(_n('email')),
    phone: Value(_n('phone')),
    website: Value(_n('website')),
    address: Value(_n('address')),
    abn: Value(_n('abn')),
    payeeName: Value(_n('payeeName')),
    bankName: Value(_n('bankName')),
    bankBsb: Value(_n('bankBsb')),
    bankAccount: Value(_n('bankAccount')),
    swift: Value(_n('swift')),
    paymentLink: Value(_n('paymentLink')),
    currency: Value(_t('currency').isEmpty ? 'USD' : _t('currency')),
    taxLabel: Value(_n('taxLabel')),
    taxRate: Value(double.tryParse(_t('taxRate'))),
    templateId: Value(_templateId),
    // isDefault flows through setDefaultProfile so there's only ever one.
  );

  /// Validates and persists, returning whether it succeeded — used both by
  /// the editor's own Save action and by the shell's unsaved-changes dialog.
  Future<bool> _persist() async {
    if (_t('name').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A profile name is required.')),
      );
      return false;
    }
    try {
      final id = _isEdit
          ? widget.initial!.id
          : await widget.db.insertProfile(_companion());
      if (_isEdit) await widget.db.updateProfileById(id, _companion());
      if (_isDefault) await widget.db.setDefaultProfile(id);
      // The just-saved values become the new baseline — dirty clears without
      // needing widget.initial to change (this widget stays mounted).
      _initialTexts = {for (final f in _fields) f: _c[f]!.text};
      _initialIsDefault = _isDefault;
      _initialTemplateId = _templateId;
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save profile: $e')));
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
  // there's anything to lose). A new (unsaved) profile has nothing to view,
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
      for (final f in _fields) {
        _c[f]!.text = _initialTexts[f] ?? '';
      }
      _isDefault = _initialIsDefault;
      _templateId = _initialTemplateId;
      _editing = false;
    });
    _checkDirty();
  }

  Future<void> _delete() async {
    final p = widget.initial!;
    final ok = await confirmDelete(
      context,
      title: 'Delete profile?',
      message: '"${p.name}" will be removed.',
    );
    if (!ok) return;
    try {
      await widget.db.deleteProfile(p.id);
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) {
        await showInfoDialog(
          context,
          title: "Can't delete profile",
          message:
              'A template still uses this profile. Point those templates '
              'at another profile first.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Header stays pinned; the form and live preview scroll together as one
    // content pane, so a short viewport can still reach the whole preview.
    return EditorShell(
      title: _editing ? (_isEdit ? 'Edit profile' : 'New profile') : 'Profile',
      name: _isEdit ? _t('name') : null,
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
          child: _editing ? _form() : const SizedBox.shrink(),
        ),
        if (_editing) const SizedBox(height: AppTokens.spaceMd),
        _preview(),
      ],
    );
  }

  Widget _form() {
    return Column(
      spacing: AppTokens.spaceXl,
      children: [
        FieldGroup('Profile name / Template', [
          FieldRow([
            Field(_field('name', 'Name')),
            Field(
              EditorDropdown<int>(
                label: 'Template',
                value: _templateId,
                items: [
                  for (final t in _templates)
                    DropdownMenuItem(value: t.id, child: Text(t.name)),
                ],
                onChanged: (v) => setState(() {
                  _templateId = v;
                  _checkDirty();
                }),
              ),
            ),
          ]),
        ]),
        FieldGroup('Business', [
          FieldRow([
            Field(_field('businessName', 'Business name')),
            Field(_field('website', 'Website')),
          ]),
          // Equal thirds: Website lines up above ABN, Email/Phone span the width
          // that Address occupies below.
          FieldRow([
            Field(_field('email', 'Email')),
            Field(_field('phone', 'Phone')),
          ]),
          FieldRow([
            Field(_field('address', 'Address'), flex: 2),
            Field(_field('abn', 'ABN / company no.')),
          ]),
        ]),
        FieldGroup('Payment', [
          FieldRow([
            Field(_field('payeeName', 'Payee name')),
            Field(_field('bankName', 'Bank')),
          ]),
          FieldRow([
            Field(_field('bankBsb', 'BSB')),
            Field(_field('bankAccount', 'Account')),
            Field(_field('swift', 'SWIFT / BIC')),
          ]),
          FieldRow([Field(_field('paymentLink', 'Payment link'))]),
        ]),
        FieldGroup('Currency & tax', [
          FieldRow([
            Field(_field('currency', 'Currency')),
            Field(_field('taxLabel', 'Tax label')),
            Field(_field('taxRate', 'Tax %', number: true)),
            Field(
              flex: 0,
              brandingDefaultToggle(
                value: _isDefault,
                onChanged: (v) => setState(() {
                  _isDefault = v;
                  _checkDirty();
                }),
              ),
            ),
          ]),
        ]),
        const SizedBox(height: AppTokens.space4xs),
      ],
    );
  }

  Widget _field(String key, String label, {bool number = false}) =>
      EditorTextField(
        controller: _c[key]!,
        label: label,
        number: number,
        onChanged: (_) => setState(_checkDirty),
      );

  Widget _preview() {
    final template = _selectedTemplate();
    if (template == null) {
      return const SizedBox(
        height: 240,
        child: Center(child: Text('Add a template to preview.')),
      );
    }
    final doc = profilePreviewDocument(
      profile: _draft(),
      issueDate: DateTime.now(),
    );
    // scrollable: false — the editor's outer scroll owns vertical scrolling.
    return brandingPreviewFrame(
      child: invoicePreviewPage(
        doc: doc,
        template: template,
        scrollable: false,
      ),
    );
  }
}
