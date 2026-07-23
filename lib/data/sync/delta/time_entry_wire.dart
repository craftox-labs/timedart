import 'package:drift/drift.dart';

import 'package:timedart/data/database.dart';

// Phase 5b delta-sync (#294) — the Postgres wire shape for a `time_entries`
// row.
//
// `public.time_entries` (see scratch/phase5-5a-backend.sql) uses snake_case
// columns, stores every DateTime as an epoch-**millisecond** bigint, and lets
// the server author `server_seq` via a trigger. This codec is the single
// translation seam between the app's drift `TimeEntry` (camelCase fields,
// `DateTime?`) and that wire map — pure, so it unit-tests without a database
// or network.
//
// Kept deliberately explicit (no reflection / toJson key-munging): the column
// list is the app↔backend contract for one table, so it should read literally.

/// Encode a local [TimeEntry] as the JSON map pushed to `public.time_entries`
/// (upsert payload). `server_seq` is **omitted** — it is server-authored; the
/// client never writes it. `org_id` is included (adoption stamps it locally
/// first); RLS `WITH CHECK` still enforces membership server-side.
Map<String, dynamic> timeEntryToWire(TimeEntry e) => {
  'id': e.id,
  'org_id': e.orgId,
  'project_id': e.projectId,
  'task_id': e.taskId,
  'description': e.description,
  'started_at': _toMs(e.startedAt),
  'ended_at': _toMs(e.endedAt),
  'seconds': e.seconds,
  'created_at': _toMs(e.createdAt),
  'updated_at': _toMs(e.updatedAt),
  'deleted_at': _toMs(e.deletedAt),
};

/// A remote `time_entries` row parsed from PostgREST JSON: the fields needed
/// to make a last-write-wins decision ([updatedAt]) and to apply the row
/// locally, plus the server-authored [serverSeq] the pull cursor advances on.
class RemoteTimeEntry {
  final String id;
  final String? orgId;
  final String projectId;
  final String? taskId;
  final String? description;
  final DateTime startedAt;
  final DateTime endedAt;
  final int seconds;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// Server-authored ordering key: the `server_seq` column, stamped by trigger
  /// from the shared `public.sync_seq` sequence. Absent only in tests /
  /// hand-built rows; every row PostgREST returns carries one.
  final int? serverSeq;

  const RemoteTimeEntry({
    required this.id,
    required this.orgId,
    required this.projectId,
    required this.taskId,
    required this.description,
    required this.startedAt,
    required this.endedAt,
    required this.seconds,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.serverSeq,
  });

  /// Decode a PostgREST JSON row (snake_case, epoch-ms ints) into a value.
  factory RemoteTimeEntry.fromWire(Map<String, dynamic> m) => RemoteTimeEntry(
    id: m['id'] as String,
    orgId: m['org_id'] as String?,
    projectId: m['project_id'] as String,
    taskId: m['task_id'] as String?,
    description: m['description'] as String?,
    startedAt: _fromMs(m['started_at'])!,
    endedAt: _fromMs(m['ended_at'])!,
    seconds: (m['seconds'] as num).toInt(),
    createdAt: _fromMs(m['created_at']),
    updatedAt: _fromMs(m['updated_at']),
    deletedAt: _fromMs(m['deleted_at']),
    serverSeq: (m['server_seq'] as num?)?.toInt(),
  );

  /// The drift companion for a local apply. Every column is an explicit [Value]
  /// (including nulls) so `insertOnConflictUpdate` overwrites the whole row —
  /// crucially, `updatedAt` is set to the **remote's** clock, never re-stamped
  /// to now, so the applied row is a fixed point (no push↔pull echo).
  TimeEntriesCompanion toCompanion() => TimeEntriesCompanion(
    id: Value(id),
    orgId: Value(orgId),
    projectId: Value(projectId),
    taskId: Value(taskId),
    description: Value(description),
    startedAt: Value(startedAt),
    endedAt: Value(endedAt),
    seconds: Value(seconds),
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt),
    deletedAt: Value(deletedAt),
  );
}

int? _toMs(DateTime? d) => d?.millisecondsSinceEpoch;

DateTime? _fromMs(Object? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());
