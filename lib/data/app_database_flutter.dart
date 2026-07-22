import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'backup.dart';
import 'database.dart';
import 'legacy_db_migration.dart';
import 'sync/powersync_connection.dart';
import 'sync/sync_activation.dart';
import 'sync/sync_config.dart';
import 'sync/sync_seed.dart';

// ── The Flutter-coupled DB-open path (app-only) ────────────────────────────
// This file is the ONLY place that imports `drift_flutter` + `path_provider`
// (via [appDatabaseDirectory]). It is imported solely by the running app (see
// main.dart) so that [AppDatabase] itself — and everything the companion CLI
// imports through it — stays pure Dart and can be compiled with
// `dart compile exe` without pulling in a Flutter platform channel. The CLI's
// equivalent, path_provider-free open path lives in `cli/db_open.dart`; both
// resolve to the *same* on-disk `timedart/timedart.sqlite` file.

/// The app's `drift_flutter` query executor — unchanged from the executor that
/// used to live inline in `AppDatabase._open()`, so the GUI opens exactly the
/// same on-disk database in exactly the same location as before.
QueryExecutor openAppQueryExecutor() => driftDatabase(
  // The on-disk file is `timedart.sqlite`, in a plainly-named `timedart`
  // folder (see appDatabaseDirectory) rather than the bundle-id folder.
  // Installs from before this held `dev.craftox.timedart/time_tracker.sqlite`;
  // migrateLegacyDatabaseFile() (called at startup, before this opens) moves
  // it across so no data is orphaned.
  name: 'timedart',
  native: const DriftNativeOptions(databaseDirectory: appDatabaseDirectory),
  // Web demo: drift_flutter branches platforms internally, so this block is
  // ignored on native. Assets ship in web/ (version-matched to drift). No
  // COOP/COEP headers → storage falls back to IndexedDB (fine for a demo).
  web: DriftWebOptions(
    sqlite3Wasm: Uri.parse('sqlite3.wasm'),
    driftWorker: Uri.parse('drift_worker.js'),
  ),
);

/// Open the app's [AppDatabase] on the Flutter/drift_flutter executor.
AppDatabase openAppDatabase() => AppDatabase(openAppQueryExecutor());

/// The connection factory main.dart calls at startup. Two gates decide the
/// connection (PRD #189, Phase 4c/4d):
///   • the compile-time [syncEnabled] flag — const-false in every released
///     build, so the whole block below is dead-code-eliminated and no PowerSync
///     code runs. "Sync off == today" holds for every shipped binary;
///   • the runtime [SyncActivation] (a maintainer's on/off toggle, Phase 4d),
///     read from a small file before any database opens.
/// Only when BOTH say yes does the app open the PowerSync-backed connection;
/// otherwise it opens today's plain local `drift_flutter` database, byte-for-byte
/// unchanged. On the first launch after enabling, the plain-local rows are
/// seeded into the fresh synced store ([_seedSyncedFromLocal]).
/// Async because the PowerSync path initializes + connects; the local path just
/// wraps the synchronous open in a resolved Future.
Future<AppDatabase> openDatabaseForApp() async {
  if (syncEnabled) {
    final activation = await readSyncActivation();
    if (activation.enabled) {
      final synced = await openSyncedAppDatabase();
      if (activation.seedPending) {
        await _seedSyncedFromLocal(synced.db, orgId: activation.orgId);
        await writeSyncActivation(activation.copyWith(seedPending: false));
      }
      return synced.db;
    }
  }
  return openAppDatabase();
}

/// Copy the plain-local database's rows into the freshly-opened synced store,
/// stamping [orgId] on the synced content rows (PRD #189, Phase 4d). PowerSync
/// owns a separate file with no in-place conversion, so the seed reuses the
/// Phase-1 backup machinery: read the local snapshot, stamp `org_id`, restore
/// into the synced DB. The inserts land in PowerSync's views → they queue for
/// upload under this org, and templates/profiles/`app_settings` carry over too
/// (so onboarding does not replay on the fresh store). The local DB is opened
/// transiently and closed; it is a different file, so there is no lock contention
/// with the synced connection.
Future<void> _seedSyncedFromLocal(
  AppDatabase syncedDb, {
  required String orgId,
}) async {
  final local = openAppDatabase();
  try {
    final snapshot = stampOrgId(await readBackupSnapshot(local), orgId);
    await restoreBackup(
      syncedDb,
      Backup(
        formatVersion: backupFormatVersion,
        schemaVersion: syncedDb.schemaVersion,
        exportedAt: DateTime.now(),
        snapshot: snapshot,
      ),
    );
  } finally {
    await local.close();
  }
}
