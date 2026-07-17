import 'dart:io';

import 'package:path_provider/path_provider.dart';

// Native implementation of the database-location logic. See
// legacy_db_migration.dart for the cross-platform entry points.

/// The directory the database lives in: a folder named plainly `timedart`
/// inside the platform's data root, e.g. `~/.local/share/timedart` (Linux) or
/// `~/Library/Application Support/timedart` (macOS) — rather than the
/// bundle-id-named `dev.craftox.timedart` that `getApplicationSupportDirectory`
/// returns by default. Chosen so the folder is obvious and easy to find (and to
/// remove when uninstalling). Returns `Future<Object>` to match drift_flutter's
/// `DriftNativeOptions.databaseDirectory` signature (deliberately io-free so it
/// compiles for the web build).
Future<Object> appDatabaseDirectory() async {
  final (_, newDir) = await _resolveDirectories();
  await newDir.create(recursive: true);
  return newDir;
}

/// One-time migration that moves the database from its pre-1.0 location — the
/// bundle-id folder, under the legacy file name `time_tracker.sqlite` — to the
/// new `timedart/timedart.sqlite`. Runs at startup, before the database opens.
/// Idempotent and non-destructive.
Future<void> migrateLegacyDatabaseFile() async {
  final (oldDir, newDir) = await _resolveDirectories();
  await newDir.create(recursive: true);
  await moveLegacyDatabaseFile(oldDir.path, newDir.path);
  await _removeEmptyLegacyFolders(from: oldDir, stopAt: newDir.parent);
}

/// The old (bundle-id) and new (`timedart`) directories. The new one is a
/// plainly-named `timedart` folder directly under the platform's data root.
/// `getApplicationSupportDirectory` nests the app one level under that root on
/// Linux/macOS (`…/dev.craftox.timedart`) but two levels on Windows
/// (`…\craftox\timedart`), so the root is reached by stepping up accordingly.
Future<(Directory oldDir, Directory newDir)> _resolveDirectories() async {
  final oldDir = await getApplicationSupportDirectory();
  final root = Platform.isWindows ? oldDir.parent.parent : oldDir.parent;
  final newDir = Directory('${root.path}${Platform.pathSeparator}timedart');
  return (oldDir, newDir);
}

/// Best-effort tidy-up after the move: delete the legacy folder and any empty
/// folders above it (e.g. the Windows `…\craftox` once `craftox\timedart` is
/// gone), walking up until the data [stopAt] root — which is never touched.
/// Never throws: a leftover empty folder is harmless, and startup must not fail
/// over cleanup.
Future<void> _removeEmptyLegacyFolders({
  required Directory from,
  required Directory stopAt,
}) async {
  var cursor = from;
  while (cursor.path != stopAt.path) {
    try {
      if (!await cursor.exists() || !await cursor.list().isEmpty) break;
      await cursor.delete();
    } catch (_) {
      break;
    }
    cursor = cursor.parent;
  }
}

/// The pure core, with both directories injected so it can be unit-tested
/// without the platform path-provider channel. Moves the main database file and
/// its SQLite `-wal`/`-shm` sidecars from `oldDir` to `newDir`, renaming to
/// `timedart.sqlite`. A file is moved only when its destination doesn't already
/// exist, so re-running (or a partial earlier run) never clobbers current data.
Future<void> moveLegacyDatabaseFile(String oldDir, String newDir) async {
  final sep = Platform.pathSeparator;
  await Directory(newDir).create(recursive: true);
  for (final legacyName in const ['time_tracker.sqlite', 'timedart.sqlite']) {
    for (final suffix in const ['', '-wal', '-shm']) {
      final src = File('$oldDir$sep$legacyName$suffix');
      final dest = File('$newDir${sep}timedart.sqlite$suffix');
      if (src.path != dest.path &&
          await src.exists() &&
          !await dest.exists()) {
        await src.rename(dest.path);
      }
    }
  }
}
