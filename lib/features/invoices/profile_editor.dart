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
    this.initial,
  });
  final AppDatabase db;
  final VoidCallback onDone;
  final InvoiceProfile? initial;

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  // One controller per text field, keyed for the draft + companion.
  late final Map<String, TextEditingController> _c;
  late bool _isDefault;
  late final Future<InvoiceTheme?> _sampleTheme;

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
    _sampleTheme = widget.db.watchThemes().first.then((list) {
      for (final t in list) {
        if (t.isDefault) return t;
      }
      return list.isEmpty ? null : list.first;
    });
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
    // isDefault flows through setDefaultProfile so there's only ever one.
  );

  Future<void> _save() async {
    if (_t('name').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A profile name is required.')),
      );
      return;
    }
    try {
      final id = _isEdit
          ? widget.initial!.id
          : await widget.db.insertProfile(_companion());
      if (_isEdit) await widget.db.updateProfileById(id, _companion());
      if (_isDefault) await widget.db.setDefaultProfile(id);
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save profile: $e')));
      }
    }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        editorHeader(
          context: context,
          title: _isEdit ? 'Edit profile' : 'New profile',
          isEdit: _isEdit,
          onDelete: _delete,
          onCancel: widget.onDone,
          onSave: _save,
        ),
        const SizedBox(height: AppTokens.spaceMd),
        _form(),
        const SizedBox(height: AppTokens.spaceMd),
        Expanded(child: _preview()),
      ],
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _group('Business', [
          _field('name', 'Name', width: 200),
          _field('businessName', 'Business name'),
          _field('email', 'Email'),
          _field('phone', 'Phone', width: 160),
          _field('website', 'Website'),
          _field('address', 'Address', width: 320),
          _field('abn', 'ABN / company no.', width: 180),
        ]),
        const SizedBox(height: AppTokens.spaceSm),
        _group('Payment', [
          _field('payeeName', 'Payee name'),
          _field('bankName', 'Bank'),
          _field('bankBsb', 'BSB', width: 140),
          _field('bankAccount', 'Account', width: 180),
          _field('swift', 'SWIFT / BIC', width: 160),
          _field('paymentLink', 'Payment link', width: 320),
        ]),
        const SizedBox(height: AppTokens.spaceSm),
        _group('Currency & tax', [
          _field('currency', 'Currency', width: 120),
          _field('taxLabel', 'Tax label', width: 160),
          _field('taxRate', 'Tax %', width: 120, number: true),
          SizedBox(
            height: 48,
            child: brandingDefaultToggle(
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _group(String title, List<Widget> fields) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: AppTokens.space3xs),
      Wrap(
        spacing: AppTokens.spaceSm,
        runSpacing: AppTokens.spaceSm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: fields,
      ),
    ],
  );

  Widget _field(
    String key,
    String label, {
    double width = 240,
    bool number = false,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: _c[key],
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        decoration: fieldDecoration(label),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _preview() {
    return FutureBuilder<InvoiceTheme?>(
      future: _sampleTheme,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final theme = snap.data;
        if (theme == null) {
          return const Center(child: Text('Add a theme to preview.'));
        }
        final doc = sampleInvoiceDocument(
          profile: _draft(),
          issueDate: DateTime.now(),
        );
        return brandingPreviewFrame(
          child: invoicePreviewPage(doc: doc, theme: theme),
        );
      },
    );
  }
}
