import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/delta_keys.dart';
import 'package:timedart/data/sync/delta/supabase_init.dart';
import 'package:timedart/data/sync/delta/sync_queries.dart';

// Phase 5a delta-sync (#294) — anonymous auth + org resolution + adoption.
//
// Anonymous-first (decision locked 2026-07-23): the first sign-in mints a
// personal org-of-one via the `handle_new_user` trigger. Full email login is
// deferred. The session persists (supabase_flutter storage) and silent-refreshes
// across restarts, so this signs in once, not every launch.

class DeltaAuthService {
  DeltaAuthService(this._db, {SupabaseClient? client})
      : _client = client ?? supabase;

  final AppDatabase _db;
  final SupabaseClient _client;

  /// The current user id, or null if not signed in.
  String? get currentUserId => _client.auth.currentUser?.id;

  bool get isSignedIn => currentUserId != null;

  /// Ensure there's an anonymous session, returning the user id. A no-op (just
  /// returns the existing id) if a persisted session was restored on launch.
  Future<String> ensureSignedIn() async {
    final existing = currentUserId;
    if (existing != null) return existing;
    final res = await _client.auth.signInAnonymously();
    final id = res.user?.id;
    if (id == null) {
      throw StateError('anonymous sign-in returned no user');
    }
    return id;
  }

  /// Resolve this account's org_id, caching it in `app_settings`. Reads
  /// `memberships` (RLS restricts the result to the caller's own membership, so
  /// `limit 1` is the personal org). Returns the cached value without a network
  /// round-trip on subsequent calls.
  Future<String> resolveOrgId() async {
    final cached = await _db.syncSetting(kSyncOrgId);
    if (cached != null && cached.isNotEmpty) return cached;

    final rows = await _client.from('memberships').select('org_id').limit(1);
    if (rows.isEmpty) {
      // The handle_new_user trigger creates the membership on sign-up; an empty
      // result means the session isn't fully established yet.
      throw StateError('no membership row for the current user');
    }
    final orgId = rows.first['org_id'] as String;
    await _db.setSyncSetting(kSyncOrgId, orgId);
    return orgId;
  }

  /// Sign in (if needed), resolve the org, and adopt any offline-created local
  /// clients that carry no org_id — stamping them so they push on the next sync.
  /// Returns the org_id. This is the one-call first-sign-in bootstrap.
  Future<String> signInAndAdopt() async {
    await ensureSignedIn();
    final orgId = await resolveOrgId();
    await _db.adoptOrphanClients(orgId);
    return orgId;
  }
}
