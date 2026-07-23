import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/delta_exceptions.dart';
import 'package:timedart/data/sync/delta/delta_keys.dart';
import 'package:timedart/data/sync/delta/supabase_init.dart';
import 'package:timedart/data/sync/delta/sync_queries.dart';

// Phase 5a delta-sync (#294) — anonymous auth + org resolution + adoption.
//
// Anonymous-first (decision locked 2026-07-23): the first sign-in mints a
// personal org-of-one via the `handle_new_user` trigger. The session persists
// (supabase_flutter storage) and silent-refreshes across restarts, so this
// signs in once, not every launch.
//
// Auth slice 1 (#310) adds email sign-in + sign-out on top of the anon base, so
// a maintainer can prove a recoverable, server-backed identity and — signing in
// with the SAME account on two devices — a real shared org (the 2-device goal).
//
// Two email methods, for two horizons:
//   • Password (signUp/signInWithPassword): the path used NOW for personal
//     testing. With Supabase "Confirm email" turned OFF it sends NO email, so it
//     needs no SMTP and no deep-link plumbing — a direct API call that works
//     identically on Linux and Android. The email is just an identifier.
//   • OTP code (sendEmailOtp/verifyEmailOtp): the passwordless path for the
//     eventual PUBLIC launch. Dormant until SMTP is configured (deferred).
//
// Anon stays the default. NB email sign-in here starts a FRESH email session
// (its own personal org) — it does NOT link onto the live anon user; that
// zero-migration upgrade is slice 2 (#311). So identity state is cleared on
// every account change to keep the org/cursor cache honest. To move existing
// local data onto a shared account for now, use Export/Import.

class DeltaAuthService {
  DeltaAuthService(this._db, {SupabaseClient? client})
      : _client = client ?? supabase;

  final AppDatabase _db;
  final SupabaseClient _client;

  /// The current user id, or null if not signed in.
  String? get currentUserId => _client.auth.currentUser?.id;

  bool get isSignedIn => currentUserId != null;

  /// The signed-in user's email, or null for an anonymous / signed-out session.
  /// Supabase reports an anonymous user's email as an EMPTY STRING (not null),
  /// so normalise: anonymous or empty → null. Callers use `email != null` to
  /// mean "signed in with a real email account", and an empty string would
  /// otherwise wrongly read as one (hiding the sign-in form on an anon session).
  String? get currentUserEmail {
    final user = _client.auth.currentUser;
    if (user == null || user.isAnonymous) return null;
    final email = user.email;
    return (email == null || email.isEmpty) ? null : email;
  }

  /// Whether the current session is an anonymous one (vs an email account).
  /// False when signed out (no user) or signed in with email.
  bool get isAnonymous => _client.auth.currentUser?.isAnonymous ?? false;

  /// Create an email/password account and sign into it. With Supabase "Confirm
  /// email" OFF this returns a ready session with no email sent. Replaces any
  /// prior (anon) session rather than linking onto it, so the identity cache is
  /// dropped. Returns the user id.
  Future<String> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    final res = await _client.auth.signUp(email: email, password: password);
    final id = res.user?.id;
    if (id == null) {
      throw const DeltaSyncException('sign-up returned no user');
    }
    await _db.clearSyncIdentityState();
    return id;
  }

  /// Sign into an existing email/password account. The second device signs in
  /// with the SAME credentials as the first → same user → same org → shared
  /// sync. Clears the identity cache (account change). Returns the user id.
  Future<String> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final res = await _client.auth
        .signInWithPassword(email: email, password: password);
    final id = res.user?.id;
    if (id == null) {
      throw const DeltaSyncException('sign-in returned no user');
    }
    await _db.clearSyncIdentityState();
    return id;
  }

  /// Send a one-time passwordless sign-in code to [email]. Creates the user if
  /// they don't exist yet. The code arrives by email; the caller then passes it
  /// to [verifyEmailOtp]. (Supabase also emails a magic link off the same call;
  /// we ignore it and use the OTP token — no deep-link handling needed.)
  Future<void> sendEmailOtp(String email) =>
      _client.auth.signInWithOtp(email: email, shouldCreateUser: true);

  /// Verify the emailed [token] for [email], establishing an email session.
  /// This replaces any prior (anon) session rather than linking onto it, so the
  /// identity cache is dropped — the next sync pass re-resolves the email
  /// account's own org. Returns the user id.
  Future<String> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    final res = await _client.auth.verifyOTP(
      email: email,
      token: token,
      type: OtpType.email,
    );
    final id = res.user?.id;
    if (id == null) {
      throw const DeltaSyncException('email verification returned no user');
    }
    await _db.clearSyncIdentityState();
    return id;
  }

  /// Sign out of the Supabase session. Does NOT wipe local data (local stays the
  /// source of truth) — only the identity cache is dropped so a later sign-in
  /// re-resolves cleanly. The next enabled sync trigger will mint a fresh anon
  /// session per [ensureSignedIn], the same anon-first default as a first launch.
  Future<void> signOut() async {
    await _client.auth.signOut();
    await _db.clearSyncIdentityState();
  }

  /// Ensure there's an anonymous session, returning the user id. A no-op (just
  /// returns the existing id) if a persisted session was restored on launch.
  Future<String> ensureSignedIn() async {
    final existing = currentUserId;
    if (existing != null) return existing;
    final res = await _client.auth.signInAnonymously();
    final id = res.user?.id;
    if (id == null) {
      throw const DeltaSyncException('anonymous sign-in returned no user');
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
      throw const DeltaSyncException('no membership row for the current user');
    }
    final orgId = rows.first['org_id'] as String;
    await _db.setSyncSetting(kSyncOrgId, orgId);
    return orgId;
  }

  /// Sign in (if needed), resolve the org, and adopt any offline-created local
  /// rows that carry no org_id — across all four content tables — stamping them
  /// so they push on the next sync. Returns the org_id. This is the one-call
  /// first-sign-in bootstrap and the mechanism by which pre-existing local data
  /// seeds the outbox for its initial push.
  Future<String> signInAndAdopt() async {
    await ensureSignedIn();
    final orgId = await resolveOrgId();
    await _db.adoptOrphanClients(orgId);
    await _db.adoptOrphanProjects(orgId);
    await _db.adoptOrphanTasks(orgId);
    await _db.adoptOrphanTimeEntries(orgId);
    return orgId;
  }
}
