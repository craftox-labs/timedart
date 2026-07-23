import 'package:drift/drift.dart';

import 'package:timedart/data/database.dart';

// Phase 5b delta-sync (#294) — the Postgres wire shape for a `projects` row.
//
// `public.projects` (see scratch/phase5-5a-backend.sql) uses snake_case
// columns, stores every DateTime as an epoch-**millisecond** bigint, and lets
// the server author `server_seq` via a trigger. This codec is the single
// translation seam between the app's drift `Project` (camelCase fields,
// `DateTime?`) and that wire map — pure, so it unit-tests without a database
// or network.
//
// Kept deliberately explicit (no reflection / toJson key-munging): the column
// list is the app↔backend contract for one table, so it should read literally.

/// Encode a local [Project] as the JSON map pushed to `public.projects`
/// (upsert payload). `server_seq` is **omitted** — it is server-authored; the
/// client never writes it. `org_id` is included (adoption stamps it locally
/// first); RLS `WITH CHECK` still enforces membership server-side.
Map<String, dynamic> projectToWire(Project p) => {
  'id': p.id,
  'org_id': p.orgId,
  'client_id': p.clientId,
  'code': p.code,
  'title': p.title,
  'rate': p.rate,
  'status': p.status,
  'archived_at': _toMs(p.archivedAt),
  'created_at': _toMs(p.createdAt),
  'updated_at': _toMs(p.updatedAt),
  'deleted_at': _toMs(p.deletedAt),
};

/// A remote `projects` row parsed from PostgREST JSON: the fields needed to
/// make a last-write-wins decision ([updatedAt]) and to apply the row
/// locally, plus the server-authored [serverSeq] the pull cursor advances on.
class RemoteProject {
  final String id;
  final String? orgId;
  final String clientId;
  final String code;
  final String title;
  final double? rate;
  final String status;
  final DateTime? archivedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// Server-authored ordering key: the `server_seq` column, stamped by trigger
  /// from the shared `public.sync_seq` sequence. Absent only in tests /
  /// hand-built rows; every row PostgREST returns carries one.
  final int? serverSeq;

  const RemoteProject({
    required this.id,
    required this.orgId,
    required this.clientId,
    required this.code,
    required this.title,
    required this.rate,
    required this.status,
    required this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.serverSeq,
  });

  /// Decode a PostgREST JSON row (snake_case, epoch-ms ints) into a value.
  factory RemoteProject.fromWire(Map<String, dynamic> m) => RemoteProject(
    id: m['id'] as String,
    orgId: m['org_id'] as String?,
    clientId: m['client_id'] as String,
    code: m['code'] as String,
    title: m['title'] as String,
    rate: (m['rate'] as num?)?.toDouble(),
    status: m['status'] as String,
    archivedAt: _fromMs(m['archived_at']),
    createdAt: _fromMs(m['created_at'])!,
    updatedAt: _fromMs(m['updated_at']),
    deletedAt: _fromMs(m['deleted_at']),
    serverSeq: (m['server_seq'] as num?)?.toInt(),
  );

  /// The drift companion for a local apply. Every column is an explicit [Value]
  /// (including nulls) so `insertOnConflictUpdate` overwrites the whole row —
  /// crucially, `updatedAt` is set to the **remote's** clock, never re-stamped
  /// to now, so the applied row is a fixed point (no push↔pull echo).
  ProjectsCompanion toCompanion() => ProjectsCompanion(
    id: Value(id),
    orgId: Value(orgId),
    clientId: Value(clientId),
    code: Value(code),
    title: Value(title),
    rate: Value(rate),
    status: Value(status),
    archivedAt: Value(archivedAt),
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt),
    deletedAt: Value(deletedAt),
  );
}

int? _toMs(DateTime? d) => d?.millisecondsSinceEpoch;

DateTime? _fromMs(Object? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());
