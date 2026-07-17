// Web implementation. There is no local database file on web (drift stores web
// data in IndexedDB), so there is nothing to migrate, and the native directory
// provider is never invoked (drift_flutter uses its web options there).
// See legacy_db_migration.dart.

/// No-op on web — see [migrateLegacyDatabaseFile] in the native variant.
Future<void> migrateLegacyDatabaseFile() async {}

/// Never called on web (drift_flutter ignores `DriftNativeOptions` there); the
/// signature exists only so the conditional export type-checks.
Future<Object> appDatabaseDirectory() async =>
    throw UnsupportedError('appDatabaseDirectory is native-only');
