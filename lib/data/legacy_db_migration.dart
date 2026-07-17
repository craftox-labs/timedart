// Database location for the app, split by platform via conditional export so
// `dart:io` stays out of the web build. Exposes two symbols:
//
//   • appDatabaseDirectory()    — where the database lives: a plainly-named
//     `timedart` folder (not the bundle-id `dev.craftox.timedart`), so it's
//     easy to find and to remove when uninstalling (see docs/content/data.md).
//   • migrateLegacyDatabaseFile() — one-time move of the pre-1.0 database from
//     the bundle-id folder + legacy name (`time_tracker.sqlite`) to the new
//     `timedart/timedart.sqlite`, run at startup before the database opens.
//
// Native does the real work; web is a no-op (no file — drift uses IndexedDB).
export 'legacy_db_migration_noop.dart'
    if (dart.library.io) 'legacy_db_migration_io.dart';
