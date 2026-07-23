import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/auth_service.dart';
import 'package:timedart/data/sync/delta/client_wire.dart';
import 'package:timedart/data/sync/delta/delta_keys.dart';
import 'package:timedart/data/sync/delta/merge.dart';
import 'package:timedart/data/sync/delta/supabase_init.dart';
import 'package:timedart/data/sync/delta/sync_queries.dart';
import 'package:timedart/data/sync/delta/sync_transport.dart';

// Phase 5a delta-sync (#294) — the orchestrator. One table (`clients`) end to
// end: push dirty rows (watermark) → pull rows past the cursor → apply LWW.
//
// Ordering is push-then-pull. Cursor and watermark are device-local
// (`app_settings`) so each device tracks its own progress. Sync is gated on
// entitlement (`orgs.plan != 'free'`): a free org never touches the network.

/// What one sync pass did — surfaced to the "Sync now" UI and logs.
class SyncResult {
  /// Rows pushed to the server this pass.
  final int pushed;

  /// Rows received from the server this pass (before LWW).
  final int pulled;

  /// Rows that won LWW and were written locally.
  final int applied;

  /// Non-null when the pass did no work: why (e.g. `not entitled`).
  final String? skippedReason;

  const SyncResult({
    this.pushed = 0,
    this.pulled = 0,
    this.applied = 0,
    this.skippedReason,
  });

  const SyncResult.skipped(String reason)
      : pushed = 0,
        pulled = 0,
        applied = 0,
        skippedReason = reason;

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
        _auth = auth ?? DeltaAuthService(_db, client: client);

  final AppDatabase _db;
  final SupabaseClient _client;
  final SyncTransport _transport;
  final DeltaAuthService _auth;

  /// The full pass: ensure a session + org (adopting orphan rows on first
  /// sign-in), gate on entitlement, then sync each table. 5a = `clients` only.
  Future<SyncResult> syncAll() async {
    await _auth.signInAndAdopt();
    if (!await _isEntitled()) {
      return const SyncResult.skipped('not entitled (org plan = free)');
    }
    return _syncClients();
  }

  /// Whether the account's org is on a paid plan. RLS scopes `orgs` to the
  /// caller's memberships, so `limit 1` is the personal org.
  Future<bool> _isEntitled() async {
    final rows = await _client.from('orgs').select('plan').limit(1);
    if (rows.isEmpty) return false;
    return rows.first['plan'] != 'free';
  }

  Future<SyncResult> _syncClients() async {
    final pushed = await _pushClients();
    final (:pulled, :applied) = await _pullClients();
    return SyncResult(pushed: pushed, pulled: pulled, applied: applied);
  }

  /// Push dirty clients (updatedAt past the watermark), then advance the
  /// watermark to the newest row pushed. Tombstones ride through as upserts.
  Future<int> _pushClients() async {
    final since = await _readWatermark();
    final dirty = await _db.clientsToPush(since);
    if (dirty.isEmpty) return 0;

    await _transport.pushRows('clients', [
      for (final c in dirty) clientToWire(c),
    ]);

    // Advance the watermark to the max updatedAt actually pushed (not now()),
    // so a row edited during the pass still lands next round.
    var maxMs = since?.millisecondsSinceEpoch ?? 0;
    for (final c in dirty) {
      final ms = c.updatedAt?.millisecondsSinceEpoch ?? 0;
      if (ms > maxMs) maxMs = ms;
    }
    await _db.setSyncSetting(kSyncLastPushedClients, '$maxMs');
    return dirty.length;
  }

  /// Pull clients past the cursor and apply each under LWW, then advance the
  /// cursor to the last server_seq seen (whether applied or skipped — both are
  /// processed).
  Future<({int pulled, int applied})> _pullClients() async {
    final cursor = await _readCursor();
    final rows = await _transport.pullSince('clients', cursor);
    if (rows.isEmpty) return (pulled: 0, applied: 0);

    var applied = 0;
    var maxSeq = cursor;
    for (final raw in rows) {
      final remote = RemoteClient.fromWire(raw);
      final local = await _db.clientByIdIncludingDeleted(remote.id);
      if (decideClientMergeFor(local, remote) == MergeAction.apply) {
        await _db.applyRemoteClient(remote);
        applied++;
      }
      final seq = remote.serverSeq;
      if (seq != null && seq > maxSeq) maxSeq = seq;
    }
    if (maxSeq > cursor) {
      await _db.setSyncSetting(kSyncCursorClients, '$maxSeq');
    }
    return (pulled: rows.length, applied: applied);
  }

  Future<DateTime?> _readWatermark() async {
    final raw = await _db.syncSetting(kSyncLastPushedClients);
    final ms = int.tryParse(raw ?? '');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<int> _readCursor() async {
    final raw = await _db.syncSetting(kSyncCursorClients);
    return int.tryParse(raw ?? '') ?? 0;
  }
}
