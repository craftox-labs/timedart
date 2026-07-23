/// Build-time configuration for the Phase 5 **delta-sync** layer (#294).
///
/// Delta-sync (hand-rolled timestamp-delta over Supabase Auth + Postgres + RLS)
/// is the app's sync layer. It is compile-gated so released builds omit it
/// entirely — "sync off == today's behaviour" holds for every shipped binary. A
/// maintainer trials it with:
/// ```
/// flutter run -d linux \
///   --dart-define=ENABLE_DELTA_SYNC=true \
///   --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=<publishable/anon key>
/// ```
/// The anon/publishable key is **public by design** (RLS is the security
/// boundary) — safe to embed. The `service_role` key must NEVER appear here.
library;

/// Whether the delta-sync layer is compiled-in *and* selected at runtime.
/// `false` unless built with `--dart-define=ENABLE_DELTA_SYNC=true`.
const bool deltaSyncEnabled = bool.fromEnvironment('ENABLE_DELTA_SYNC');

/// The Supabase project URL, e.g. `https://<ref>.supabase.co`.
/// Empty unless provided via `--dart-define=SUPABASE_URL=...`.
const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

/// The Supabase anon / publishable key (public — RLS enforces access).
/// Empty unless provided via `--dart-define=SUPABASE_ANON_KEY=...`.
const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// True only when the layer is gated on AND both endpoints are configured — the
/// single predicate the app checks before doing anything Supabase-related.
bool get deltaSyncConfigured =>
    deltaSyncEnabled && supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
