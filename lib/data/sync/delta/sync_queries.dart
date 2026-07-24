import 'package:drift/drift.dart';

import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/active_timer_wire.dart';
import 'package:timedart/data/sync/delta/client_wire.dart';
import 'package:timedart/data/sync/delta/delta_keys.dart';
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

  Future<List<ActiveTimer>> activeTimersByIds(Iterable<String> ids) {
    final list = ids.toList();
    if (list.isEmpty) return Future.value(const []);
    return (select(activeTimers)..where((t) => t.id.isIn(list))).get();
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

  Future<ActiveTimer?> activeTimerByIdIncludingDeleted(String id) =>
      (select(activeTimers)..where((t) => t.id.equals(id))).getSingleOrNull();

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

  Future<void> applyRemoteActiveTimer(RemoteActiveTimer remote) =>
      into(activeTimers).insertOnConflictUpdate(remote.toCompanion());

  // ── Adoption / re-home (sign-in) ─────────────────────────────────────────────
  // Claim local rows for [orgId]: stamp it onto every row that isn't already on
  // it — both rows with NO org (used the app locally before subscribing) AND
  // rows stamped to a DIFFERENT org (switched accounts, or used anon sync then
  // signed into a real account). Bumps `updatedAt` and enqueues each so the data
  // joins the signed-in account on the next push. This is the endgame contract:
  // whatever account you sign into, your local data becomes that account's data
  // and syncs — a local-only user who subscribes keeps their work, with zero
  // migration. Without the "different org" arm, cross-org rows push under an org
  // the account isn't a member of and RLS rejects the whole pass (42501).
  // Non-destructive — only `org_id`/`updatedAt` change. Reads the ids FIRST (so
  // they can be enqueued), then updates, then marks them dirty. Returns the
  // number of rows claimed. (Safe under the personal-org-of-one model: a device
  // holds one user's data. Revisit the "different org" arm if teams ever put
  // multiple orgs' rows in one local store.)

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

  Future<int> adoptOrphanActiveTimers(String orgId) => _adoptOrphans(
      activeTimers, activeTimers.id, activeTimers.orgId, orgId,
      (o, now) => ActiveTimersCompanion(orgId: Value(o), updatedAt: Value(now)));

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
        // Rows not already on this org: no org at all, or a different org.
        final notOnOrg = orgCol.isNull() | orgCol.equals(orgId).not();
        final ids = await (selectOnly(table)
              ..addColumns([idCol])
              ..where(notOnOrg))
            .map((r) => r.read(idCol)!)
            .get();
        if (ids.isEmpty) return 0;
        await (update(table)..where((_) => notOnOrg))
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

  /// Drop the identity-scoped sync state: the cached `org_id` and every table's
  /// pull cursor. Called on any account change (email sign-in, sign-out) — the
  /// next pass then re-resolves the org from `memberships` and re-pulls from
  /// seq 0. Without this a new account would inherit the previous org's cached
  /// id and its high-water cursor, so it would push under the wrong org and skip
  /// its own lower-seq rows. Leaves `kSyncEnabled` (a device opt-in, not
  /// identity) and local content rows (no wipe on sign-out) untouched.
  Future<void> clearSyncIdentityState() => transaction(() async {
        for (final key in [
          kSyncOrgId,
          syncCursorKey(kTableClients),
          syncCursorKey(kTableProjects),
          syncCursorKey(kTableTasks),
          syncCursorKey(kTableTimeEntries),
          syncCursorKey(kTableActiveTimers),
        ]) {
          await (delete(appSettings)..where((s) => s.key.equals(key))).go();
        }
      });
}
