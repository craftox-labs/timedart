import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/active_timer_wire.dart';
import 'package:timedart/data/sync/delta/auth_service.dart';
import 'package:timedart/data/sync/delta/client_wire.dart';
import 'package:timedart/data/sync/delta/delta_keys.dart';
import 'package:timedart/data/sync/delta/logo_storage.dart';
import 'package:timedart/data/sync/delta/merge.dart';
import 'package:timedart/data/sync/delta/profile_wire.dart';
import 'package:timedart/data/sync/delta/project_wire.dart';
import 'package:timedart/data/sync/delta/supabase_init.dart';
import 'package:timedart/data/sync/delta/sync_queries.dart';
import 'package:timedart/data/sync/delta/sync_transport.dart';
import 'package:timedart/data/sync/delta/task_wire.dart';
import 'package:timedart/data/sync/delta/template_wire.dart';
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

  /// True when the pass was skipped because there's no account session (never
  /// falls back to anonymous). Typed so the UI can prompt sign-in.
  final bool needsSignIn;

  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.applied = 0,
    this.skippedReason,
    this.notEntitled = false,
    this.needsSignIn = false,
  });

  const SyncResult.skipped(String reason)
      : pushed = 0,
        pulled = 0,
        applied = 0,
        skippedReason = reason,
        notEntitled = false,
        needsSignIn = false;

  /// The pass was skipped because no account is signed in — sync requires one.
  const SyncResult.notSignedIn()
      : pushed = 0,
        pulled = 0,
        applied = 0,
        skippedReason = 'not signed in',
        notEntitled = false,
        needsSignIn = true;

  /// The pass was skipped because the org isn't on a paid plan (free =
  /// local-only). Carries both the human message and the typed [notEntitled].
  const SyncResult.notEntitled()
      : pushed = 0,
        pulled = 0,
        applied = 0,
        skippedReason = 'not entitled (org plan = free)',
        notEntitled = true,
        needsSignIn = false;

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
    LogoStorage? logos,
  })  : _client = client ?? supabase,
        _transport = transport ?? SyncTransport(client: client),
        _auth = auth ?? DeltaAuthService(_db, client: client),
        _logos = logos ?? LogoStorage(client: client) {
    // Constructing the service means sync is active for this session, so make
    // sure content-table writes enqueue into the outbox (idempotent — in a
    // delta build it's already on from startup; this also flips it on for tests).
    _db.enableSyncOutbox = true;
  }

  final AppDatabase _db;
  final SupabaseClient _client;
  final SyncTransport _transport;
  final DeltaAuthService _auth;
  final LogoStorage _logos;

  /// The full pass: require an account session, resolve the org + claim local
  /// rows for it, gate on entitlement, then push and pull all four content
  /// tables. Never signs in anonymously — no account, no sync.
  Future<SyncResult> syncAll() async {
    if (!_auth.isAccountSignedIn) {
      return const SyncResult.notSignedIn();
    }
    // Gate on entitlement BEFORE adoption. Adoption re-stamps local rows'
    // org_id + updatedAt and enqueues them; doing that for a free (unentitled)
    // account would dirty local timestamps and grow the outbox for data that
    // will never push. A free account resolves its org for the plan check but
    // otherwise leaves local state untouched.
    if (!await _isEntitled()) {
      return const SyncResult.notEntitled();
    }
    await _auth.resolveOrgAndAdopt();

    // Push (order is cosmetic — the server has no FKs). Each table's outbox is
    // the push set; cleared on ack.
    var pushed = 0;
    pushed += await _push(kTableClients, _wireClients);
    pushed += await _push(kTableProjects, _wireProjects);
    pushed += await _push(kTableTasks, _wireTasks);
    pushed += await _push(kTableTimeEntries, _wireTimeEntries);
    pushed += await _push(kTableTemplates, _wireTemplates);
    pushed += await _push(kTableProfiles, _wireProfiles);
    pushed += await _push(kTableActiveTimers, _wireActiveTimers);

    // Pull + apply parent-first so the local FK constraints hold on insert.
    var pulled = 0;
    var applied = 0;
    for (final entry in <(String, Future<bool> Function(Map<String, dynamic>))>[
      (kTableClients, _applyClient),
      (kTableProjects, _applyProject),
      (kTableTasks, _applyTask),
      (kTableTimeEntries, _applyTimeEntry),
      // templates before profiles: a profile's templateId FK-references one.
      (kTableTemplates, _applyTemplate),
      (kTableProfiles, _applyProfile),
      // Applied LAST: active_timers FK-references projects/tasks locally, so its
      // parents must be inserted first this pass (the backend has no FKs).
      (kTableActiveTimers, _applyActiveTimer),
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

  Future<List<Map<String, dynamic>>> _wireActiveTimers(List<String> ids) async =>
      [for (final t in await _db.activeTimersByIds(ids)) activeTimerToWire(t)];

  Future<List<Map<String, dynamic>>> _wireTemplates(List<String> ids) async =>
      [for (final t in await _db.templatesByIds(ids)) templateToWire(t)];

  // Profiles carry a logo BLOB that can't ride a text row. For each queued
  // profile with local logo bytes, upload them to Storage (idempotent, keyed by
  // a content hash), persist the resulting object path locally WITHOUT bumping
  // the clock or re-enqueuing (setLocalLogoPath), and put the path on the wire
  // row so the OTHER device can fetch-on-miss. A profile with no logo pushes
  // logo_path = null. If the org isn't resolved yet (shouldn't happen post-
  // adoption) the logo upload is skipped defensively; the row still pushes.
  Future<List<Map<String, dynamic>>> _wireProfiles(List<String> ids) async {
    final rows = <Map<String, dynamic>>[];
    for (final p in await _db.profilesByIds(ids)) {
      final bytes = p.logo;
      final orgId = p.orgId;
      if (bytes != null && bytes.isNotEmpty && orgId != null) {
        final path = logoObjectPath(orgId, p.id, bytes, p.logoMime);
        if (p.logoPath != path) {
          try {
            await _logos.upload(path, bytes, p.logoMime);
            await _db.setLocalLogoPath(p.id, path);
          } catch (_) {
            // Storage failed (e.g. the `logos` bucket isn't created yet, or a
            // transient error). Do NOT let it wedge the whole pass — keep this
            // profile queued (re-enqueue so it survives the outbox clear, which
            // only drops rows queued BEFORE the pass snapshot) and skip pushing
            // it this pass; other tables + the pull still run, and the logo
            // uploads on a later pass. Without this, a user with a logo and no
            // bucket would deadlock ALL sync (adoption enqueues every profile).
            await _db.markDirtyForSync(kTableProfiles, [p.id]);
            continue;
          }
        }
        rows.add({...profileToWire(p), 'logo_path': path});
      } else {
        // No local logo → force logo_path/logo_mime null on the wire AND clear
        // any stale local path. Otherwise a REMOVAL never propagates: the row
        // would keep advertising the old Storage object and other devices would
        // re-download it (resurrecting the deleted logo). logoPath is sync-
        // internal (no UI writes it), so the push path owns keeping it correct.
        if (p.logoPath != null) await _db.setLocalLogoPath(p.id, null);
        rows.add({...profileToWire(p), 'logo_path': null, 'logo_mime': null});
      }
    }
    return rows;
  }

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

  Future<bool> _applyActiveTimer(Map<String, dynamic> raw) async {
    final r = RemoteActiveTimer.fromWire(raw);
    final local = await _db.activeTimerByIdIncludingDeleted(r.id);
    if (decideActiveTimerMergeFor(local, r) != MergeAction.apply) return false;
    await _db.applyRemoteActiveTimer(r);
    return true;
  }

  Future<bool> _applyTemplate(Map<String, dynamic> raw) async {
    final r = RemoteTemplate.fromWire(raw);
    final local = await _db.templateByIdIncludingDeleted(r.id);
    if (decideTemplateMergeFor(local, r) != MergeAction.apply) return false;
    await _db.applyRemoteTemplate(r);
    return true;
  }

  Future<bool> _applyProfile(Map<String, dynamic> raw) async {
    final r = RemoteProfile.fromWire(raw);
    final local = await _db.profileByIdIncludingDeleted(r.id);
    if (decideProfileMergeFor(local, r) != MergeAction.apply) return false;
    await _db.applyRemoteProfile(r);
    await _reconcileLogo(r);
    return true;
  }

  /// Bring the local logo BLOB in line with a just-applied remote profile:
  /// fetch-on-miss when the row points at a Storage object we don't already hold
  /// (bytes absent, or their content hash doesn't match the remote path), and
  /// clear it when the remote has no logo. Never enqueues / re-clocks (the logo
  /// helpers are raw writes). A Storage failure is swallowed to a rethrow-free
  /// no-op so a transient logo miss doesn't wedge the whole pass — the next pass
  /// retries (the path is still on the row).
  Future<void> _reconcileLogo(RemoteProfile r) async {
    final orgId = r.orgId;
    final local = await _db.profileByIdIncludingDeleted(r.id);
    if (r.logoPath == null) {
      if (local?.logo != null) await _db.clearLocalLogo(r.id);
      return;
    }
    final localBytes = local?.logo;
    final alreadyHave = localBytes != null &&
        localBytes.isNotEmpty &&
        orgId != null &&
        logoObjectPath(orgId, r.id, localBytes, local!.logoMime) == r.logoPath;
    if (alreadyHave) return;
    try {
      final bytes = await _logos.download(r.logoPath!);
      await _db.setLocalLogoBytes(r.id, bytes, r.logoMime);
    } catch (_) {
      // Leave logoPath on the row; a later pass retries the download.
    }
  }

  Future<int> _readCursor(String table) async {
    final raw = await _db.syncSetting(syncCursorKey(table));
    return int.tryParse(raw ?? '') ?? 0;
  }
}
