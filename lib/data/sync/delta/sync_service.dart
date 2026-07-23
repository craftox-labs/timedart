import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/auth_service.dart';
import 'package:timedart/data/sync/delta/client_wire.dart';
import 'package:timedart/data/sync/delta/delta_keys.dart';
import 'package:timedart/data/sync/delta/merge.dart';
import 'package:timedart/data/sync/delta/project_wire.dart';
import 'package:timedart/data/sync/delta/supabase_init.dart';
import 'package:timedart/data/sync/delta/sync_queries.dart';
import 'package:timedart/data/sync/delta/sync_transport.dart';
import 'package:timedart/data/sync/delta/task_wire.dart';
import 'package:timedart/data/sync/delta/time_entry_wire.dart';

// Phase 5 delta-sync (#294) — the orchestrator. Phase 5b takes it from one table
// to all four content tables, and swaps the 5a `updatedAt` push watermark for a
// real dirty-tracker (the `sync_outbox`, read via DeltaSyncQueries).
//
// A pass is push-then-pull. Push set = the outbox ids per table (cleared on
// ack). Pull advances a per-table `server_seq` cursor (device-local
// `app_settings`). Pull+apply runs parent-first (clients → projects → tasks →
// time_entries) so the local DB's foreign keys hold as children are inserted
// (the backend itself has no FKs by design). Sync is gated on entitlement
// (`orgs.plan != 'free'`): a free org never touches the network.

/// The free (local-only) plan value in `orgs.plan`; anything else is entitled.
const String kFreePlan = 'free';

/// What one sync pass did — surfaced to the "Sync now" UI and logs. Counts are
/// aggregated across all four tables.
class SyncResult {
  /// Rows pushed to the server this pass.
  final int pushed;

  /// Rows received from the server this pass (before LWW).
  final int pulled;

  /// Rows that won LWW and were written locally.
  final int applied;

  /// Non-null when the pass did no work: why (e.g. `not entitled`).
  final String? skippedReason;

  /// True when the pass was skipped specifically because the org is on the free
  /// plan. A typed signal so the UI can show the paid-feature gate without
  /// matching on [skippedReason]'s prose (which is snackbar text, free to
  /// reword).
  final bool notEntitled;

  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.applied = 0,
    this.skippedReason,
    this.notEntitled = false,
  });

  const SyncResult.skipped(String reason)
      : pushed = 0,
        pulled = 0,
        applied = 0,
        skippedReason = reason,
        notEntitled = false;

  /// The pass was skipped because the org isn't on a paid plan (free =
  /// local-only). Carries both the human message and the typed [notEntitled].
  const SyncResult.notEntitled()
      : pushed = 0,
        pulled = 0,
        applied = 0,
        skippedReason = 'not entitled (org plan = free)',
        notEntitled = true;

  bool get didSync => skippedReason == null;

  @override
  String toString() => skippedReason != null
      ? 'SyncResult(skipped: $skippedReason)'
      : 'SyncResult(pushed: $pushed, pulled: $pulled, applied: $applied)';
}

class DeltaSyncService {
  DeltaSyncService(
    this._db, {
    SupabaseClient? client,
    SyncTransport? transport,
    DeltaAuthService? auth,
  })  : _client = client ?? supabase,
        _transport = transport ?? SyncTransport(client: client),
        _auth = auth ?? DeltaAuthService(_db, client: client) {
    // Constructing the service means sync is active for this session, so make
    // sure content-table writes enqueue into the outbox (idempotent — in a
    // delta build it's already on from startup; this also flips it on for tests).
    _db.enableSyncOutbox = true;
  }

  final AppDatabase _db;
  final SupabaseClient _client;
  final SyncTransport _transport;
  final DeltaAuthService _auth;

  /// The full pass: ensure a session + org (adopting orphan rows on first
  /// sign-in), gate on entitlement, then push and pull all four content tables.
  Future<SyncResult> syncAll() async {
    await _auth.signInAndAdopt();
    if (!await _isEntitled()) {
      return const SyncResult.notEntitled();
    }

    // Push (order is cosmetic — the server has no FKs). Each table's outbox is
    // the push set; cleared on ack.
    var pushed = 0;
    pushed += await _push(kTableClients, _wireClients);
    pushed += await _push(kTableProjects, _wireProjects);
    pushed += await _push(kTableTasks, _wireTasks);
    pushed += await _push(kTableTimeEntries, _wireTimeEntries);

    // Pull + apply parent-first so the local FK constraints hold on insert.
    var pulled = 0;
    var applied = 0;
    for (final entry in <(String, Future<bool> Function(Map<String, dynamic>))>[
      (kTableClients, _applyClient),
      (kTableProjects, _applyProject),
      (kTableTasks, _applyTask),
      (kTableTimeEntries, _applyTimeEntry),
    ]) {
      final (pulled: p, applied: a) = await _pull(entry.$1, entry.$2);
      pulled += p;
      applied += a;
    }

    return SyncResult(pushed: pushed, pulled: pulled, applied: applied);
  }

  /// Whether the account's org is on a paid plan. RLS scopes `orgs` to the
  /// caller's memberships, so `limit 1` is the personal org.
  Future<bool> _isEntitled() async {
    final rows = await _client.from('orgs').select('plan').limit(1);
    if (rows.isEmpty) return false;
    return rows.first['plan'] != kFreePlan;
  }

  // ── Push ────────────────────────────────────────────────────────────────
  // Read the table's outbox → fetch the current state of those rows (tombstones
  // included) → upsert → clear the outbox for exactly the ids read. Partial
  // failure throws before the clear, so nothing is lost — it re-pushes next pass.

  Future<int> _push(
    String table,
    Future<List<Map<String, dynamic>>> Function(List<String>) buildWire,
  ) async {
    // Snapshot the pass start BEFORE reading the outbox, so a concurrent edit
    // that re-queues one of these ids during the network round-trip (bumping its
    // queuedAt past the snapshot) is NOT cleared — it pushes next pass.
    final snapshot = DateTime.now();
    final ids = await _db.outboxRowIds(table);
    if (ids.isEmpty) return 0;
    final rows = await buildWire(ids);
    await _transport.pushRows(table, rows);
    await _db.clearOutbox(table, ids, queuedBefore: snapshot);
    return rows.length;
  }

  Future<List<Map<String, dynamic>>> _wireClients(List<String> ids) async =>
      [for (final c in await _db.clientsByIds(ids)) clientToWire(c)];

  Future<List<Map<String, dynamic>>> _wireProjects(List<String> ids) async =>
      [for (final p in await _db.projectsByIds(ids)) projectToWire(p)];

  Future<List<Map<String, dynamic>>> _wireTasks(List<String> ids) async =>
      [for (final t in await _db.tasksByIds(ids)) taskToWire(t)];

  Future<List<Map<String, dynamic>>> _wireTimeEntries(List<String> ids) async =>
      [for (final e in await _db.timeEntriesByIds(ids)) timeEntryToWire(e)];

  // ── Pull ────────────────────────────────────────────────────────────────
  // Rows past the cursor, applied under LWW, cursor advanced to the last
  // server_seq seen (whether applied or skipped — both are processed).

  Future<({int pulled, int applied})> _pull(
    String table,
    Future<bool> Function(Map<String, dynamic>) applyIfNewer,
  ) async {
    final cursor = await _readCursor(table);
    final rows = await _transport.pullSince(table, cursor);
    if (rows.isEmpty) return (pulled: 0, applied: 0);

    var applied = 0;
    var maxSeq = cursor;
    for (final raw in rows) {
      if (await applyIfNewer(raw)) applied++;
      final seq = (raw['server_seq'] as num?)?.toInt();
      if (seq != null && seq > maxSeq) maxSeq = seq;
    }
    if (maxSeq > cursor) {
      await _db.setSyncSetting(syncCursorKey(table), '$maxSeq');
    }
    return (pulled: rows.length, applied: applied);
  }

  // Per-table LWW-apply: decode → find local match (tombstones included) →
  // apply via the fromRemote path iff the remote clock wins. Returns whether it
  // applied (for the count).

  Future<bool> _applyClient(Map<String, dynamic> raw) async {
    final r = RemoteClient.fromWire(raw);
    final local = await _db.clientByIdIncludingDeleted(r.id);
    if (decideClientMergeFor(local, r) != MergeAction.apply) return false;
    await _db.applyRemoteClient(r);
    return true;
  }

  Future<bool> _applyProject(Map<String, dynamic> raw) async {
    final r = RemoteProject.fromWire(raw);
    final local = await _db.projectByIdIncludingDeleted(r.id);
    if (decideProjectMergeFor(local, r) != MergeAction.apply) return false;
    await _db.applyRemoteProject(r);
    return true;
  }

  Future<bool> _applyTask(Map<String, dynamic> raw) async {
    final r = RemoteTask.fromWire(raw);
    final local = await _db.taskByIdIncludingDeleted(r.id);
    if (decideTaskMergeFor(local, r) != MergeAction.apply) return false;
    await _db.applyRemoteTask(r);
    return true;
  }

  Future<bool> _applyTimeEntry(Map<String, dynamic> raw) async {
    final r = RemoteTimeEntry.fromWire(raw);
    final local = await _db.timeEntryByIdIncludingDeleted(r.id);
    if (decideTimeEntryMergeFor(local, r) != MergeAction.apply) return false;
    await _db.applyRemoteTimeEntry(r);
    return true;
  }

  Future<int> _readCursor(String table) async {
    final raw = await _db.syncSetting(syncCursorKey(table));
    return int.tryParse(raw ?? '') ?? 0;
  }
}
