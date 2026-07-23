import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:timedart/data/sync/delta/supabase_init.dart';

// Phase 5a delta-sync (#294) — the network seam. A thin wrapper over PostgREST:
// push = upsert (keyed by primary key `id`), pull = select rows past a cursor,
// server-ordered. RLS scopes both to the caller's org; `server_seq` is stamped
// server-side by trigger and returned on the way back.

class SyncTransport {
  SyncTransport({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  /// Upsert [rows] into [table], keyed by primary key `id` (idempotent — a
  /// re-push of the same row is a no-op server-side). Tombstones ride through as
  /// ordinary upserts (their `deleted_at` is just another column). No-op for an
  /// empty batch. RLS `WITH CHECK` rejects rows outside the caller's org.
  Future<void> pushRows(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _client.from(table).upsert(rows);
  }

  /// Pull rows from [table] with `server_seq` strictly greater than [cursor],
  /// ordered by `server_seq` ascending (so applying them in order and advancing
  /// the cursor to the last seen is exactly resumable). RLS auto-scopes to the
  /// caller's org.
  Future<List<Map<String, dynamic>>> pullSince(String table, int cursor) async {
    final rows = await _client
        .from(table)
        .select()
        .gt('server_seq', cursor)
        .order('server_seq', ascending: true);
    return rows;
  }
}
