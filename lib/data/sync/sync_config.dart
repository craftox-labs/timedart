/// Build-time configuration for the optional sync layer (PRD #189, Phase 4).
///
/// Sync is gated behind a **compile-time** flag so released builds omit it
/// entirely and "sync off == today's behaviour" holds for every shipped binary
/// (the gate decision on #210). A maintainer builds a sync-enabled variant to
/// trial:
/// ```
/// flutter run -d linux \
///   --dart-define=ENABLE_SYNC=true \
///   --dart-define=POWERSYNC_URL=https://<id>.powersync.journeyapps.com \
///   --dart-define=POWERSYNC_TOKEN=<dashboard-dev-token>
/// ```
/// When [syncEnabled] is false (every released build), none of the PowerSync
/// code below is reached — the app opens the plain local SQLite database exactly
/// as before. There is no in-app toggle yet: that's Phase 4d, and it stays
/// wrapped in this same gate until Phase 5 delivers real auth.
library;

/// Whether the optional sync layer is compiled-in *and* selected at runtime.
/// `false` unless built with `--dart-define=ENABLE_SYNC=true`.
const bool syncEnabled = bool.fromEnvironment('ENABLE_SYNC');

/// The PowerSync Cloud instance URL (dashboard → project → "Edit instance").
/// Empty unless provided via `--dart-define=POWERSYNC_URL=...`.
const String powerSyncUrl = String.fromEnvironment('POWERSYNC_URL');

/// A PowerSync **Dev Token** (dashboard-minted). Trial-only: dev tokens expire
/// after ~12 hours and are not for production — real JWT/JWKS auth is Phase 5.
/// Empty unless provided via `--dart-define=POWERSYNC_TOKEN=...`.
const String powerSyncToken = String.fromEnvironment('POWERSYNC_TOKEN');

/// The Supabase Edge Function that applies uploaded CRUD to the source Postgres
/// (Phase 4b / #209), e.g. `https://<ref>.supabase.co/functions/v1/upload-data`.
/// The write path is disabled (uploads stay queued) when empty. See
/// `supabase/functions/upload-data/`.
/// Empty unless provided via `--dart-define=SUPABASE_FUNCTION_URL=...`.
const String supabaseFunctionUrl = String.fromEnvironment(
  'SUPABASE_FUNCTION_URL',
);
