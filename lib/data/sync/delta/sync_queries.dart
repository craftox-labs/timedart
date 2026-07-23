import 'package:drift/drift.dart';

import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/client_wire.dart';
import 'package:timedart/data/sync/delta/project_wire.dart';
import 'package:timedart/data/sync/delta/task_wire.dart';
import 'package:timedart/data/sync/delta/time_entry_wire.dart';

// Phase 5 delta-sync (#294) — the database seam for sync, kept OUT of the giant
// database.dart as an extension so all delta code stays under
// lib/data/sync/delta/. These are the DB operations sync needs that the normal
// CRUD surface doesn't expose, now spanning all four content tables (5b):
//
//   • outboxRowIds / clearOutbox — the dirty-tracker read/ack. The push set is
//                       the ids queued in `sync_outbox` for a table (marked at
//                       the write choke-point via AppDatabase.markDirtyForSync);
//                       cleared on push-ack. Replaces 5a's `updatedAt` watermark.
//   • {clients,projects,tasks,timeEntries}ByIds — fetch the CURRENT state (incl.
//                       tombstones) of the queued rows to build the push payload.
//   • xByIdIncludingDeleted — the local match for a pulled id, tombstones
//                       included, for the LWW comparison.
//   • applyRemoteX — the `fromRemote` write path: upsert a pulled row WITHOUT
//                       re-stamping `updatedAt` (echo-free) AND without enqueuing
//                       into the outbox (the structural echo guard). The normal
//                       CRUD always bumps updatedAt + enqueues.
//   • adoptOrphanX — stamp org_id on offline-created rows at first sign-in,
//                       bumping updatedAt and enqueuing them so they push.

extension DeltaSyncQueries on AppDatabase {
  // ── Outbox (dirty-tracker) ─────────────────────────────────────────────────

  /// The row ids queued for [table] in the outbox — the push set for this table.
  Future<List<String>> outboxRowIds(String table) => (selectOnly(syncOutbox)
        ..addColumns([syncOutbox.rowId])
        ..where(syncOutbox.targetTable.equals(table)))
      .map((r) => r.read(syncOutbox.rowId)!)
      .get();

  /// Clear the outbox entries for [table]/[ids] after a successful push. Partial
  /// failure just leaves the rest queued for the next pass.
  ///
  /// [queuedBefore] guards a TOCTOU race: `_push` reads the ids, then awaits the
  /// network, and a *concurrent local edit* during that await re-enqueues one of
  /// those ids (bumping its `queuedAt`) — its new state hasn't been pushed. By
  /// clearing only rows whose `queuedAt` is strictly before the pass's snapshot,
  /// such a re-queued row survives the clear and pushes next pass, instead of
  /// being silently dropped. Omit it to clear unconditionally (tests).
  Future<void> clearOutbox(
    String table,
    Iterable<String> ids, {
    DateTime? queuedBefore,
  }) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (delete(syncOutbox)
          ..where((o) {
            final base = o.targetTable.equals(table) & o.rowId.isIn(list);
            return queuedBefore == null
                ? base
                : base & o.queuedAt.isSmallerThanValue(queuedBefore);
          }))
        .go();
  }

  // ── Push reads: current state of queued rows (tombstones included) ──────────

  Future<List<Client>> clientsByIds(Iterable<String> ids) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value(const []);
    return (select(clients)..where((c) => c.id.isIn(list))).get();
  }

  Future<List<Project>> projectsByIds(Iterable<String> ids) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value(const []);
    return (select(projects)..where((p) => p.id.isIn(list))).get();
  }

  Future<List<Task>> tasksByIds(Iterable<String> ids) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value(const []);
    return (select(tasks)..where((t) => t.id.isIn(list))).get();
  }

  Future<List<TimeEntry>> timeEntriesByIds(Iterable<String> ids) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value(const []);
    return (select(timeEntries)..where((e) => e.id.isIn(list))).get();
  }

  // ── Pull: local match for LWW (tombstones NOT filtered) ─────────────────────
  // Unlike the app's getters these do NOT filter `deletedAt IS NULL` — LWW must
  // compare against a locally-deleted row too, so a remote un-delete (or a
  // staler remote delete) resolves correctly.

  Future<Client?> clientByIdIncludingDeleted(String id) =>
      (select(clients)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<Project?> projectByIdIncludingDeleted(String id) =>
      (select(projects)..where((p) => p.id.equals(id))).getSingleOrNull();

  Future<Task?> taskByIdIncludingDeleted(String id) =>
      (select(tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<TimeEntry?> timeEntryByIdIncludingDeleted(String id) =>
      (select(timeEntries)..where((e) => e.id.equals(id))).getSingleOrNull();

  // ── Apply (fromRemote): full-row upsert keyed by `id`, remote clock verbatim ─
  // Idempotent (upsert by PK) and echo-free (equal `updatedAt` round-trips to a
  // LWW no-op). Crucially these do NOT enqueue into the outbox — that is the
  // structural echo guard. Callers gate on decide*MergeFor first; these write.

  Future<void> applyRemoteClient(RemoteClient remote) =>
      into(clients).insertOnConflictUpdate(remote.toCompanion());

  Future<void> applyRemoteProject(RemoteProject remote) =>
      into(projects).insertOnConflictUpdate(remote.toCompanion());

  Future<void> applyRemoteTask(RemoteTask remote) =>
      into(tasks).insertOnConflictUpdate(remote.toCompanion());

  Future<void> applyRemoteTimeEntry(RemoteTimeEntry remote) =>
      into(timeEntries).insertOnConflictUpdate(remote.toCompanion());

  // ── Adoption (first sign-in) ────────────────────────────────────────────────
  // Stamp [orgId] onto every local row that has none, bumping `updatedAt` and
  // enqueuing it so offline-created data joins the account on the next push.
  // Reads the null-org ids FIRST (so they can be enqueued), then updates, then
  // marks them dirty. Non-destructive — only `org_id`/`updatedAt` change.
  // Returns the number of rows adopted.

  Future<int> adoptOrphanClients(String orgId) => _adoptOrphans(
      clients, clients.id, clients.orgId, orgId,
      (o, now) => ClientsCompanion(orgId: Value(o), updatedAt: Value(now)));

  Future<int> adoptOrphanProjects(String orgId) => _adoptOrphans(
      projects, projects.id, projects.orgId, orgId,
      (o, now) => ProjectsCompanion(orgId: Value(o), updatedAt: Value(now)));

  Future<int> adoptOrphanTasks(String orgId) => _adoptOrphans(
      tasks, tasks.id, tasks.orgId, orgId,
      (o, now) => TasksCompanion(orgId: Value(o), updatedAt: Value(now)));

  Future<int> adoptOrphanTimeEntries(String orgId) => _adoptOrphans(
      timeEntries, timeEntries.id, timeEntries.orgId, orgId,
      (o, now) => TimeEntriesCompanion(orgId: Value(o), updatedAt: Value(now)));

  /// Shared adoption body. [companionFor] builds the table's companion from the
  /// (orgId, now) pair — the one per-table bit the generic can't express.
  Future<int> _adoptOrphans<T extends Table, R>(
    TableInfo<T, R> table,
    GeneratedColumn<String> idCol,
    GeneratedColumn<String> orgCol,
    String orgId,
    Insertable<R> Function(String orgId, DateTime now) companionFor,
  ) =>
      transaction(() async {
        final ids = await (selectOnly(table)
              ..addColumns([idCol])
              ..where(orgCol.isNull()))
            .map((r) => r.read(idCol)!)
            .get();
        if (ids.isEmpty) return 0;
        await (update(table)..where((_) => orgCol.isNull()))
            .write(companionFor(orgId, DateTime.now()));
        await markDirtyForSync(table.actualTableName, ids);
        return ids.length;
      });

  // ── Sync-local key/value (device-local `app_settings`, never synced) ──
  // Own accessors rather than database.dart's private _getSetting/_setSetting,
  // so the whole delta layer stays in lib/data/sync/delta/.

  /// Read a `sync.`-namespaced setting, or null if unset.
  Future<String?> syncSetting(String key) async =>
      (await (select(appSettings)..where((s) => s.key.equals(key)))
              .getSingleOrNull())
          ?.value;

  /// Upsert a `sync.`-namespaced setting.
  Future<void> setSyncSetting(String key, String value) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(
          key: Value(key),
          value: Value(value),
          updatedAt: Value(DateTime.now()),
        ),
      );
}
