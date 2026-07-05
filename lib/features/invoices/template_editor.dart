import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/invoices/editor_common.dart';
import 'package:time_tracker/features/invoices/invoice_document.dart';
import 'package:time_tracker/features/invoices/invoice_preview.dart';
import 'package:time_tracker/widgets/confirm_dialog.dart';

/// Content-pane editor for an invoice [InvoiceTemplate] — a named pairing of a
/// theme + a profile, one marked default — with a live A4 preview of that
/// pairing below the form. Creates when [initial] is null.
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
  late final TextEditingController _name;
  int? _themeId;
  int? _profileId;
  late bool _isDefault;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    _name = TextEditingController(text: t?.name ?? '');
    _themeId = t?.themeId;
    _profileId = t?.profileId;
    _isDefault = t?.isDefault ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      _snack('A template name is required.');
      return;
    }
    if (_themeId == null || _profileId == null) {
      _snack('Pick a theme and a profile.');
      return;
    }
    try {
      final companion = TemplatesCompanion(
        name: Value(_name.text.trim()),
        themeId: Value(_themeId!),
        profileId: Value(_profileId!),
      );
      final id = _isEdit
          ? widget.initial!.id
          : await widget.db.insertTemplate(companion);
      if (_isEdit) await widget.db.updateTemplateById(id, companion);
      if (_isDefault) await widget.db.setDefaultTemplate(id);
      if (mounted) widget.onDone();
    } catch (e) {
      _snack('Could not save template: $e');
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
    } catch (e) {
      _snack('Could not delete template: $e');
    }
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<InvoiceTheme>>(
      stream: widget.db.watchThemes(),
      builder: (context, themeSnap) {
        return StreamBuilder<List<InvoiceProfile>>(
          stream: widget.db.watchProfiles(),
          builder: (context, profileSnap) {
            final themes = themeSnap.data;
            final profiles = profileSnap.data;
            if (themes == null || profiles == null) {
              return const Center(child: CircularProgressIndicator());
            }
            // Default the pickers to the default (or first) row once loaded.
            _themeId ??= _defaultId(themes);
            _profileId ??= _defaultId(profiles);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                editorHeader(
                  context: context,
                  title: _isEdit ? 'Edit template' : 'New template',
                  isEdit: _isEdit,
                  onDelete: _delete,
                  onCancel: widget.onDone,
                  onSave: _save,
                ),
                const SizedBox(height: AppTokens.spaceMd),
                _form(themes, profiles),
                const SizedBox(height: AppTokens.spaceMd),
                Expanded(child: _preview(themes, profiles)),
              ],
            );
          },
        );
      },
    );
  }

  int? _defaultId(List<dynamic> rows) {
    if (rows.isEmpty) return null;
    for (final r in rows) {
      if (r.isDefault as bool) return r.id as int;
    }
    return rows.first.id as int;
  }

  Widget _form(List<InvoiceTheme> themes, List<InvoiceProfile> profiles) {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            controller: _name,
            decoration: fieldDecoration('Name'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<int>(
            initialValue: _themeId,
            isDense: true,
            decoration: fieldDecoration('Theme', dropdown: true),
            items: [
              for (final t in themes)
                DropdownMenuItem(value: t.id, child: Text(t.name)),
            ],
            onChanged: (v) => setState(() => _themeId = v),
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<int>(
            initialValue: _profileId,
            isDense: true,
            decoration: fieldDecoration('Profile', dropdown: true),
            items: [
              for (final p in profiles)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: (v) => setState(() => _profileId = v),
          ),
        ),
        SizedBox(
          height: 48,
          child: brandingDefaultToggle(
            value: _isDefault,
            onChanged: (v) => setState(() => _isDefault = v),
          ),
        ),
      ],
    );
  }

  Widget _preview(List<InvoiceTheme> themes, List<InvoiceProfile> profiles) {
    final theme = _byId(themes, _themeId);
    final profile = _byId(profiles, _profileId);
    if (theme == null || profile == null) {
      return const Center(child: Text('Add a theme and a profile to preview.'));
    }
    final doc = sampleInvoiceDocument(
      profile: profile,
      issueDate: DateTime.now(),
    );
    return brandingPreviewFrame(
      child: invoicePreviewPage(doc: doc, theme: theme),
    );
  }

  T? _byId<T>(List<T> rows, int? id) {
    if (id == null) return null;
    for (final r in rows) {
      if ((r as dynamic).id == id) return r;
    }
    return null;
  }
}
