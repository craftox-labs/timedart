import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/invoices/editor_common.dart';
import 'package:time_tracker/features/invoices/invoice_document.dart';
import 'package:time_tracker/features/invoices/invoice_preview.dart';
import 'package:time_tracker/features/invoices/invoice_region.dart';
import 'package:time_tracker/widgets/confirm_dialog.dart';

/// Content-pane editor for an invoice [InvoiceProfile] — business identity
/// (including the logo), payment details, currency and optional tax — with a
/// live A4 preview below the form (dressed with the default theme). Creates
/// when [initial] is null.
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
  // The sender's region — shapes tax label/title + buyer tax-ID label, and
  // (from slice #121) which bank fields the editor exposes.
  late InvoiceRegion _region;
  // Invoice-inclusion defaults: deliberately omit a block even when the data
  // exists. Overridable per invoice at export.
  late bool _showBank;
  late bool _showPaymentLink;
  late bool _showTax;
  // EU/UK B2B reverse charge (customer accounts for VAT).
  late bool _reverseCharge;
  // The business logo (PNG/JPG bytes) — identity, so it lives on the profile.
  Uint8List? _logo;
  String? _logoMime;
  // The template (visual style) this profile renders with; null → default.
  int? _templateId;
  // Available templates for the picker + preview, loaded once.
  List<InvoiceTemplate> _templates = const [];

  bool _dirty = false;
  // Reassigned after every successful save (the new baseline) — not `final`.
  late Map<String, String> _initialTexts;
  late bool _initialIsDefault;
  late InvoiceRegion _initialRegion;
  late bool _initialShowBank;
  late bool _initialShowPaymentLink;
  late bool _initialShowTax;
  late bool _initialReverseCharge;
  Uint8List? _initialLogo;
  String? _initialLogoMime;
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
      _c['iban']!.text = p.iban ?? '';
      _c['sortCode']!.text = p.sortCode ?? '';
      _c['routingNumber']!.text = p.routingNumber ?? '';
      _c['payid']!.text = p.payid ?? '';
      _c['institutionNumber']!.text = p.institutionNumber ?? '';
      _c['transitNumber']!.text = p.transitNumber ?? '';
      _c['paymentLink']!.text = p.paymentLink ?? '';
      _c['currency']!.text = p.currency;
      _c['taxLabel']!.text = p.taxLabel ?? '';
      _c['taxRate']!.text = p.taxRate?.toString() ?? '';
    }
    _isDefault = p?.isDefault ?? false;
    // Existing profile keeps its region; a new one defaults to AU (the app's
    // seeded heritage — GST/BSB), switchable in the picker.
    _region = p != null ? InvoiceRegion.fromName(p.region) : InvoiceRegion.au;
    // A new profile pre-fills the default region's currency (kept editable).
    if (p == null) _c['currency']!.text = _region.defaultCurrency ?? 'USD';
    _showBank = p?.showBank ?? true;
    _showPaymentLink = p?.showPaymentLink ?? true;
    _showTax = p?.showTax ?? true;
    _reverseCharge = p?.reverseCharge ?? false;
    _logo = p?.logo;
    _logoMime = p?.logoMime;
    _templateId = p?.templateId;
    _initialTexts = {for (final f in _fields) f: _c[f]!.text};
    _initialIsDefault = _isDefault;
    _initialRegion = _region;
    _initialShowBank = _showBank;
    _initialShowPaymentLink = _showPaymentLink;
    _initialShowTax = _showTax;
    _initialReverseCharge = _reverseCharge;
    _initialLogo = _logo;
    _initialLogoMime = _logoMime;
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
    if (_region != _initialRegion) return true;
    if (_showBank != _initialShowBank) return true;
    if (_showPaymentLink != _initialShowPaymentLink) return true;
    if (_showTax != _initialShowTax) return true;
    if (_reverseCharge != _initialReverseCharge) return true;
    if (_templateId != _initialTemplateId) return true;
    if (!listEquals(_logo, _initialLogo)) return true;
    if (_logoMime != _initialLogoMime) return true;
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
    'iban',
    'sortCode',
    'routingNumber',
    'payid',
    'institutionNumber',
    'transitNumber',
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
    logo: _logo,
    logoMime: _logoMime,
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
    region: _region.name,
    iban: _n('iban'),
    sortCode: _n('sortCode'),
    routingNumber: _n('routingNumber'),
    payid: _n('payid'),
    institutionNumber: _n('institutionNumber'),
    transitNumber: _n('transitNumber'),
    showBank: _showBank,
    showPaymentLink: _showPaymentLink,
    showTax: _showTax,
    reverseCharge: _reverseCharge,
    // Rate/Time column toggles are a follow-up (#128) — carry stored values.
    showRateColumn: widget.initial?.showRateColumn ?? true,
    showTimeColumn: widget.initial?.showTimeColumn ?? true,
  );

  ProfilesCompanion _companion() => ProfilesCompanion(
    name: Value(_t('name')),
    businessName: Value(_t('businessName')),
    logo: Value(_logo),
    logoMime: Value(_logoMime),
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
    region: Value(_region.name),
    iban: Value(_n('iban')),
    sortCode: Value(_n('sortCode')),
    routingNumber: Value(_n('routingNumber')),
    payid: Value(_n('payid')),
    institutionNumber: Value(_n('institutionNumber')),
    transitNumber: Value(_n('transitNumber')),
    showBank: Value(_showBank),
    showPaymentLink: Value(_showPaymentLink),
    showTax: Value(_showTax),
    reverseCharge: Value(_reverseCharge),
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
      _initialRegion = _region;
      _initialShowBank = _showBank;
      _initialShowPaymentLink = _showPaymentLink;
      _initialShowTax = _showTax;
      _initialReverseCharge = _reverseCharge;
      _initialTemplateId = _templateId;
      _initialLogo = _logo;
      _initialLogoMime = _logoMime;
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
      _region = _initialRegion;
      _showBank = _initialShowBank;
      _showPaymentLink = _initialShowPaymentLink;
      _showTax = _initialShowTax;
      _reverseCharge = _initialReverseCharge;
      _templateId = _initialTemplateId;
      _logo = _initialLogo;
      _logoMime = _initialLogoMime;
      _editing = false;
    });
    _checkDirty();
  }

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
        // Split headers: "Profile name" sits above its Name + Default cluster,
        // "Template" above its Template picker + Logo cluster. Stacks below the
        // breakpoint so neither cluster is crushed into a narrow half on mobile.
        FieldRow(stackBelow: 680, [
          Field(
            titledField(
              context,
              'Profile name',
              Row(
                children: [
                  Expanded(child: _field('name', 'Name')),
                  const SizedBox(width: AppTokens.spaceSm),
                  brandingDefaultToggle(
                    value: _isDefault,
                    onChanged: (v) => setState(() {
                      _isDefault = v;
                      _checkDirty();
                    }),
                  ),
                ],
              ),
            ),
          ),
          Field(
            titledField(
              context,
              'Template',
              Row(
                children: [
                  Expanded(
                    child: EditorDropdown<int>(
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
                  const SizedBox(width: AppTokens.spaceSm),
                  _LogoField(
                    logo: _logo,
                    onPick: _pickLogo,
                    onRemove: _logo == null
                        ? null
                        : () => setState(() {
                            _logo = null;
                            _logoMime = null;
                            _checkDirty();
                          }),
                  ),
                ],
              ),
            ),
          ),
        ]),
        FieldGroup('Business', [
          FieldRow([
            Field(_field('businessName', 'Business name')),
            Field(_field('website', 'Website')),
          ]),
          // Business name / Website and Email / Phone are even halves; the row
          // below splits Address (two-thirds) over ABN (one-third).
          FieldRow([
            Field(_field('email', 'Email')),
            Field(_field('phone', 'Phone')),
          ]),
          FieldRow([
            Field(_field('address', 'Address'), flex: 2),
            Field(_field('abn', 'ABN / company no.')),
          ]),
        ]),
        // Region picker + show-on-invoice toggles. Custom layout (not FieldRow):
        // wide → region takes the flex, toggles pack tight on the right; narrow
        // → stack, with the toggles in a Wrap (bounded width) so they reflow onto
        // a second line instead of overflowing a narrow pane.
        LayoutBuilder(
          builder: (context, c) {
            final region = titledField(
              context,
              'Region',
              EditorDropdown<InvoiceRegion>(
                label: 'Region',
                value: _region,
                items: [
                  for (final r in InvoiceRegion.values)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  final previous = _region;
                  setState(() {
                    _region = v;
                    // Keep an auto-filled tax label in sync as the region
                    // changes, but never clobber one the user typed. A label
                    // counts as auto-filled when it's empty or still exactly the
                    // previous region's default (US/Other clear it to blank).
                    final current = _c['taxLabel']!.text.trim();
                    if (current.isEmpty ||
                        current == previous.defaultTaxLabel) {
                      _c['taxLabel']!.text = v.defaultTaxLabel ?? '';
                    }
                    // Same for currency: fill the region's default unless the
                    // user typed their own. Never blank it (currency is
                    // required), so a region with no default leaves it as-is.
                    final currency = _c['currency']!.text.trim();
                    if (v.defaultCurrency != null &&
                        (currency.isEmpty ||
                            currency == previous.defaultCurrency)) {
                      _c['currency']!.text = v.defaultCurrency!;
                    }
                    // Reverse charge is EU/UK-only — drop it if we leave.
                    if (!v.supportsReverseCharge) _reverseCharge = false;
                    _checkDirty();
                  });
                },
              ),
            );
            final toggles = titledField(
              context,
              'Show on invoice',
              Wrap(
                spacing: AppTokens.spaceLg,
                runSpacing: AppTokens.spaceSm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _toggle('Bank details', _showBank, (v) => _showBank = v),
                  _toggle(
                    'Payment link',
                    _showPaymentLink,
                    (v) => _showPaymentLink = v,
                  ),
                  _toggle('Tax', _showTax, (v) => _showTax = v),
                ],
              ),
            );
            if (c.maxWidth >= 840) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: region),
                  const SizedBox(width: AppTokens.spaceLg),
                  toggles,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                region,
                const SizedBox(height: AppTokens.spaceMd),
                toggles,
              ],
            );
          },
        ),
        if (_showBank == true)
          FieldGroup('Bank payment', [
            FieldRow([
              Field(_field('payeeName', 'Payee name')),
              Field(_field('bankName', 'Bank')),
            ]),
            // Region drives which bank identifiers appear, so a UK profile isn't
            // asked for a BSB nor an AU one for an IBAN.
            FieldRow([
              for (final f in _region.bankFields)
                Field(
                  _field(_bankKey(f), f.editorLabel, validator: f.validate),
                ),
            ]),
          ]),
        if (_showPaymentLink == true)
          FieldGroup('Payment link', [
            FieldRow([Field(_field('paymentLink', 'Payment link'))]),
          ]),

        if (_showTax == true)
          FieldGroup('Currency & tax', [
            FieldRow([
              Field(_field('currency', 'Currency')),
              Field(_field('taxLabel', 'Tax label')),
              Field(_field('taxRate', 'Tax %', number: true)),
            ]),
            // Reverse charge — EU/UK B2B only. Suppresses the VAT amount and
            // prints the fixed "Reverse charge" statement.
            if (_region.supportsReverseCharge)
              FieldRow([
                Field(
                  flex: 0,
                  _toggle(
                    'Reverse charge (B2B)',
                    _reverseCharge,
                    (v) => _reverseCharge = v,
                  ),
                ),
              ]),
          ]),
        const SizedBox(height: AppTokens.space4xs),
      ],
    );
  }

  Widget _field(
    String key,
    String label, {
    bool number = false,
    String? Function(String)? validator,
  }) => EditorTextField(
    controller: _c[key]!,
    label: label,
    number: number,
    // Non-blocking format hint, recomputed each keystroke (onChanged rebuilds).
    errorText: validator?.call(_c[key]!.text),
    onChanged: (_) => setState(_checkDirty),
  );

  // A compact labelled switch for an invoice-inclusion default.
  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) =>
      labelledSwitch(
        label: label,
        value: value,
        onChanged: (v) => setState(() {
          onChanged(v);
          _checkDirty();
        }),
      );

  // Maps a region [BankField] to its text-controller key.
  String _bankKey(BankField f) => switch (f) {
    BankField.bsb => 'bankBsb',
    BankField.account => 'bankAccount',
    BankField.payid => 'payid',
    BankField.sortCode => 'sortCode',
    BankField.iban => 'iban',
    BankField.routing => 'routingNumber',
    BankField.institution => 'institutionNumber',
    BankField.transit => 'transitNumber',
    BankField.bic => 'swift',
  };

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

// --- Logo picker: thumbnail (or placeholder) + Choose / Remove. The logo is
// business identity, so it lives on the profile (was on the template editor). ---
class _LogoField extends StatelessWidget {
  const _LogoField({required this.logo, required this.onPick, this.onRemove});
  final Uint8List? logo;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    // Compact and inline: a small thumbnail + Choose (+ Remove when set).
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
