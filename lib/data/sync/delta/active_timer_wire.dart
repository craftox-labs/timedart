import 'package:drift/drift.dart';

import 'package:timedart/data/database.dart';

// Delta-sync (#300) — the Postgres wire shape for an `active_timers` row (the
// live running timer). Mirrors the other wire codecs (time_entry_wire etc.):
// `public.active_timers` uses snake_case columns, stores every DateTime as an
// epoch-**millisecond** bigint, and lets the server author `server_seq`.
//
// The timer row is written only at state transitions (start/pause/resume/note),
// never per second — elapsed is derived locally from `running_since` — so
// ordinary row-level LWW carries it correctly. Two devices timing different work
// produce two distinct `id`s → two coexisting rows; only the SAME timer touched
// on both devices resolves by LWW.

/// Encode a local [ActiveTimer] as the JSON map pushed to `public.active_timers`
/// (upsert payload). `server_seq` is omitted (server-authored). `org_id` is
/// included (adoption stamps it locally first); RLS `WITH CHECK` enforces
/// membership server-side.
Map<String, dynamic> activeTimerToWire(ActiveTimer t) => {
  'id': t.id,
  'org_id': t.orgId,
  'project_id': t.projectId,
  'task_id': t.taskId,
  'description': t.description,
  'started_at': _toMs(t.startedAt),
  'accumulated_seconds': t.accumulatedSeconds,
  'running_since': _toMs(t.runningSince),
  'created_at': _toMs(t.createdAt),
  'updated_at': _toMs(t.updatedAt),
  'deleted_at': _toMs(t.deletedAt),
};

/// A remote `active_timers` row parsed from PostgREST JSON: the fields needed to
/// make the LWW decision ([updatedAt]) and to apply the row locally, plus the
/// server-authored [serverSeq] the pull cursor advances on.
class RemoteActiveTimer {
  final String id;
  final String? orgId;
  final String? projectId;
  final String? taskId;
  final String? description;
  final DateTime? startedAt;
  final int accumulatedSeconds;
  final DateTime? runningSince;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int? serverSeq;

  const RemoteActiveTimer({
    required this.id,
    required this.orgId,
    required this.projectId,
    required this.taskId,
    required this.description,
    required this.startedAt,
    required this.accumulatedSeconds,
    required this.runningSince,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.serverSeq,
  });

  factory RemoteActiveTimer.fromWire(Map<String, dynamic> m) =>
      RemoteActiveTimer(
        id: m['id'] as String,
        orgId: m['org_id'] as String?,
        projectId: m['project_id'] as String?,
        taskId: m['task_id'] as String?,
        description: m['description'] as String?,
        startedAt: _fromMs(m['started_at']),
        accumulatedSeconds: (m['accumulated_seconds'] as num?)?.toInt() ?? 0,
        runningSince: _fromMs(m['running_since']),
        createdAt: _fromMs(m['created_at']),
        updatedAt: _fromMs(m['updated_at']),
        deletedAt: _fromMs(m['deleted_at']),
        serverSeq: (m['server_seq'] as num?)?.toInt(),
      );

  /// The drift companion for a local apply. Every column is an explicit [Value]
  /// (including nulls) so `insertOnConflictUpdate` overwrites the whole row, and
  /// `updatedAt` is the remote's clock (never re-stamped) so the applied row is a
  /// fixed point (no push↔pull echo).
  ActiveTimersCompanion toCompanion() => ActiveTimersCompanion(
    id: Value(id),
    orgId: Value(orgId),
    projectId: Value(projectId),
    taskId: Value(taskId),
    description: Value(description),
    startedAt: Value(startedAt),
    accumulatedSeconds: Value(accumulatedSeconds),
    runningSince: Value(runningSince),
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt),
    deletedAt: Value(deletedAt),
  );
}

int? _toMs(DateTime? d) => d?.millisecondsSinceEpoch;

DateTime? _fromMs(Object? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());
