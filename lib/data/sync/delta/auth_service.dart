import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/delta_exceptions.dart';
import 'package:timedart/data/sync/delta/delta_keys.dart';
import 'package:timedart/data/sync/delta/supabase_init.dart';
import 'package:timedart/data/sync/delta/sync_queries.dart';

// Phase 5 delta-sync (#294) — account auth + org resolution + adoption.
//
// ACCOUNT-REQUIRED (decision 2026-07-23, superseding the earlier anon-first
// call): sync is an account-based, paid feature, so this never signs in
// anonymously. No session → sync skips (needs sign-in); it never mints an anon
// identity or stamps a throwaway anon org onto local rows. That anon stamping
// was a latent footgun — it forced cross-org re-homes and left orphaned server
// rows — so it's gone. A signed-in account's session persists (supabase_flutter
// storage) and silent-refreshes across restarts.
//
// Auth slice 1 (#310) adds email sign-in + sign-out. Two email methods, two
// horizons:
//   • Password (signUp/signInWithPassword): the path used NOW for personal
//     testing. With Supabase "Confirm email" OFF it sends NO email — a direct
//     API call, no SMTP, no deep-link plumbing, identical on Linux and Android.
//   • OTP code (sendEmailOtp/verifyEmailOtp): the passwordless path for the
//     eventual PUBLIC launch. Dormant until SMTP is configured (deferred).
//
// Signing into a different account replaces the session; identity state is
// cleared on every account change so the org/cursor cache stays honest, and
// resolveOrgAndAdopt then claims all local rows for the signed-in account. To
// carry data onto a shared account across devices, sign into the same account
// (or Export/Import).

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

  /// Whether there's a real, account-backed session (signed in AND not
  /// anonymous). Sync requires this: without it, no org is resolved, no rows
  /// are stamped, nothing is pushed. A leftover anonymous session from an older
  /// build reads as false here, so it's ignored until the user signs in.
  bool get isAccountSignedIn => isSignedIn && !isAnonymous;

  /// Create an email/password account and sign into it. With Supabase "Confirm
  /// email" OFF this returns a ready session with no email sent. Replaces any
  /// prior (anon) session rather than linking onto it, so the identity cache is
  /// dropped. Returns the user id.
  Future<String> signUpWithPassword({
    required String email,
    required String password,
  }) async {
    final res = await _client.auth.signUp(email: email, password: password);
    // gotrue returns a user but a NULL session when email confirmation is
    // required — the account exists but isn't signed in, and there's no
    // in-app way to confirm (no deep-link handling). Treat that as a failure
    // rather than reporting a false "signed in" and clearing the cache.
    if (res.session == null || res.user == null) {
      throw const DeltaSyncException(
        'account created but not signed in — email confirmation is required '
        '(disable "Confirm email" for password sign-in)',
      );
    }
    await _db.clearSyncIdentityState();
    return res.user!.id;
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
  /// re-resolves cleanly. After sign-out there is no session, so sync skips
  /// (needs sign-in) until the user signs into an account again — it never falls
  /// back to an anonymous session.
  Future<void> signOut() async {
    // gotrue clears the local session before the network revoke, so once we're
    // here we're signed out locally regardless of the revoke's outcome. Swallow
    // a network failure (offline) so the UI reports success, and clear the
    // identity cache unconditionally so it can never outlive the session.
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Local session already gone; the server token expires on its own.
    } finally {
      await _db.clearSyncIdentityState();
    }
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

  /// Resolve the account's org and claim local rows for it — across all four
  /// content tables — so pre-existing local data joins the account and pushes
  /// on the next sync. Assumes an account session ([isAccountSignedIn]); the
  /// caller (syncAll) checks that first and skips otherwise. Returns the org_id.
  /// This is the mechanism by which a user who worked locally before subscribing
  /// keeps their data, with no manual migration.
  Future<String> resolveOrgAndAdopt() async {
    final orgId = await resolveOrgId();
    await _db.adoptOrphanClients(orgId);
    await _db.adoptOrphanProjects(orgId);
    await _db.adoptOrphanTasks(orgId);
    await _db.adoptOrphanTimeEntries(orgId);
    return orgId;
  }
}
