import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:timedart/data/sync/delta/delta_config.dart';

// Phase 5a delta-sync (#294) — one-time Supabase client init.

/// Initialise the global Supabase client from the build-time config. Call once
/// in `main()` BEFORE `runApp`, and only when [deltaSyncConfigured] — a released
/// build (no keys) skips it entirely and is byte-for-byte the plain-local app.
///
/// `supabase_flutter` persists the auth session to local storage and silently
/// refreshes it, so an anonymous session survives restarts with no 12-hour wall
/// (unlike the PowerSync dev-token trial).
Future<void> initSupabase() async {
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
}

/// The initialised client. Only valid after [initSupabase]; guard call sites on
/// [deltaSyncConfigured].
SupabaseClient get supabase => Supabase.instance.client;
