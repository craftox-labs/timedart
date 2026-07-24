import 'package:drift/drift.dart';

import 'package:timedart/data/database.dart';

// Delta-sync (#320) — the Postgres wire shape for an invoice `templates` row
// (visual style: colours + font). Mirrors the other wire codecs: snake_case
// columns, DateTimes as epoch-ms bigints, ARGB colours as bigints, bools as 0/1
// bigints (templates/profiles are the first synced tables with bool columns),
// and `server_seq` server-authored (omitted on push).

Map<String, dynamic> templateToWire(InvoiceTemplate t) => {
  'id': t.id,
  'org_id': t.orgId,
  'name': t.name,
  'color_background': t.colorBackground,
  'color_surface': t.colorSurface,
  'color_primary': t.colorPrimary,
  'color_text': t.colorText,
  'color_accent': t.colorAccent,
  'font_family': t.fontFamily,
  'is_default': t.isDefault ? 1 : 0,
  'created_at': _toMs(t.createdAt),
  'updated_at': _toMs(t.updatedAt),
  'deleted_at': _toMs(t.deletedAt),
};

class RemoteTemplate {
  final String id;
  final String? orgId;
  final String name;
  final int colorBackground;
  final int colorSurface;
  final int colorPrimary;
  final int colorText;
  final int colorAccent;
  final String fontFamily;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int? serverSeq;

  const RemoteTemplate({
    required this.id,
    required this.orgId,
    required this.name,
    required this.colorBackground,
    required this.colorSurface,
    required this.colorPrimary,
    required this.colorText,
    required this.colorAccent,
    required this.fontFamily,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.serverSeq,
  });

  factory RemoteTemplate.fromWire(Map<String, dynamic> m) => RemoteTemplate(
    id: m['id'] as String,
    orgId: m['org_id'] as String?,
    name: m['name'] as String,
    colorBackground: (m['color_background'] as num).toInt(),
    colorSurface: (m['color_surface'] as num).toInt(),
    colorPrimary: (m['color_primary'] as num).toInt(),
    colorText: (m['color_text'] as num).toInt(),
    colorAccent: (m['color_accent'] as num).toInt(),
    fontFamily: m['font_family'] as String,
    isDefault: _fromB(m['is_default']),
    createdAt: _fromMs(m['created_at']),
    updatedAt: _fromMs(m['updated_at']),
    deletedAt: _fromMs(m['deleted_at']),
    serverSeq: (m['server_seq'] as num?)?.toInt(),
  );

  TemplatesCompanion toCompanion() => TemplatesCompanion(
    id: Value(id),
    orgId: Value(orgId),
    name: Value(name),
    colorBackground: Value(colorBackground),
    colorSurface: Value(colorSurface),
    colorPrimary: Value(colorPrimary),
    colorText: Value(colorText),
    colorAccent: Value(colorAccent),
    fontFamily: Value(fontFamily),
    isDefault: Value(isDefault),
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt),
    deletedAt: Value(deletedAt),
  );
}

int? _toMs(DateTime? d) => d?.millisecondsSinceEpoch;

DateTime? _fromMs(Object? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());

bool _fromB(Object? v) => v != null && (v as num).toInt() != 0;
