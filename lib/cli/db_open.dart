import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../data/database.dart';
import 'exit_codes.dart';

// ── The CLI DB-open seam (pure Dart, the load-bearing module) ──────────────
// A single, Flutter-free module that resolves *where* the app's database lives
// and opens [AppDatabase] over it — the exact seam a future PowerSync-attached
// executor (sync era, PRD #189) or a headless sync-daemon mode drops into
// without touching any command code. It must NOT import path_provider (a
// Flutter platform channel unavailable under `dart compile exe`); the
// per-platform data root is derived here from environment variables instead,
// mirroring `data/legacy_db_migration_io.dart` so the CLI opens the *same*
// file the GUI does.

/// The database file name — identical to what the app uses.
const String kTimedartDbFileName = 'timedart.sqlite';

/// Resolve the per-platform default data directory that holds the app's
/// database, WITHOUT `path_provider`. Pure: platform + environment + home are
/// injected so every branch is unit-testable.
///
/// Mirrors the locations `data/legacy_db_migration_io.dart` resolves via
/// path_provider's `getApplicationSupportDirectory` (then stepping up to the
/// data root and appending a plainly-named `timedart` folder):
///   • Linux   → `$XDG_DATA_HOME/timedart`  (default `~/.local/share/timedart`)
///   • macOS   → `~/Library/Application Support/timedart`
///   • Windows → `%APPDATA%\timedart`
///
/// [operatingSystem] takes [Platform.operatingSystem] values
/// (`'linux'` | `'macos'` | `'windows'`).
String defaultDataDirectory({
  required String operatingSystem,
  required Map<String, String> environment,
  required String? home,
}) {
  switch (operatingSystem) {
    case 'windows':
      final appData = environment['APPDATA'];
      if (appData == null || appData.isEmpty) {
        throw const CliException(
          'Cannot resolve the database location: %APPDATA% is not set.',
          CliExit.failure,
        );
      }
      return '$appData\\timedart';
    case 'macos':
      _requireHome(home);
      return '$home/Library/Application Support/timedart';
    case 'linux':
      final xdg = environment['XDG_DATA_HOME'];
      final root = (xdg != null && xdg.isNotEmpty)
          ? xdg
          : '${_requireHome(home)}/.local/share';
      return '$root/timedart';
    default:
      // Fall back to the Linux/XDG convention for any other POSIX platform.
      final xdg = environment['XDG_DATA_HOME'];
      final root = (xdg != null && xdg.isNotEmpty)
          ? xdg
          : '${_requireHome(home)}/.local/share';
      return '$root/timedart';
  }
}

String _requireHome(String? home) {
  if (home == null || home.isEmpty) {
    throw const CliException(
      'Cannot resolve the database location: no home directory in the '
      'environment (set HOME, or pass --db / TIMEDART_DB).',
      CliExit.failure,
    );
  }
  return home;
}

/// The full path to the active database file, honouring an override.
///
/// Precedence: explicit [override] (the `--db` flag) → the `TIMEDART_DB`
/// environment variable → the per-platform default file. A directory override
/// resolves to `<dir>/timedart.sqlite`; a path that looks like a file is used
/// verbatim, so tests/CI/agents can point at a scratch DB.
String resolveDbPath({
  String? override,
  required String operatingSystem,
  required Map<String, String> environment,
  required String? home,
  String separator = '/',
}) {
  final explicit = (override != null && override.isNotEmpty)
      ? override
      : (environment['TIMEDART_DB']?.isNotEmpty ?? false)
      ? environment['TIMEDART_DB']
      : null;
  if (explicit != null) return explicit;
  final dir = defaultDataDirectory(
    operatingSystem: operatingSystem,
    environment: environment,
    home: home,
  );
  return '$dir$separator$kTimedartDbFileName';
}

/// Resolve the active DB path from the real process environment.
String resolveActiveDbPath({String? override}) => resolveDbPath(
  override: override,
  operatingSystem: Platform.operatingSystem,
  environment: Platform.environment,
  home: Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'],
  separator: Platform.pathSeparator,
);

/// Read the on-disk drift schema version (SQLite `user_version`) from a DB file
/// WITHOUT going through [AppDatabase] — so the guard can decide to refuse
/// before drift ever gets a chance to run a migration. Opens read-only.
int readOnDiskSchemaVersion(String path) {
  final db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
  try {
    final rows = db.select('PRAGMA user_version');
    return rows.first.columnAt(0) as int;
  } finally {
    db.close();
  }
}

/// Open the app's [AppDatabase] over the DB at [path] as a pure-Dart peer of the
/// GUI — the seam's core.
///
/// Behaviour:
///   • FAILS with [CliExit.dbNotFound] if no file exists at [path].
///   • Enforces the **schema-version guard**: the on-disk `user_version` must
///     equal [AppDatabase.latestSchemaVersion]; otherwise FAILS with
///     [CliExit.schemaMismatch]. The CLI is NEVER the migrator.
///   • Applies **WAL** journalling and a **`busy_timeout`** so the GUI and CLI
///     can safely share the file concurrently.
///   • Opens with a migration strategy that THROWS on any create/upgrade, a
///     belt-and-braces guarantee that no schema change can ever originate here.
///
/// [busyTimeout] is the SQLite busy-timeout applied on open.
AppDatabase openTimedartDb(
  String path, {
  Duration busyTimeout = const Duration(seconds: 5),
}) {
  final file = File(path);
  if (!file.existsSync()) {
    throw CliException(
      'No timedart database found at: $path\n'
      'Start timedart (the app) once to create it, or pass --db / set '
      'TIMEDART_DB to point at an existing database.',
      CliExit.dbNotFound,
    );
  }

  final onDisk = readOnDiskSchemaVersion(path);
  const expected = AppDatabase.latestSchemaVersion;
  if (onDisk != expected) {
    throw CliException(
      'Database schema version mismatch: the database at $path is at '
      'version $onDisk, but this timedart CLI speaks version $expected. '
      'Refusing to open it — the CLI never migrates your data. '
      'Use a timedart build that matches the database.',
      CliExit.schemaMismatch,
    );
  }

  final executor = NativeDatabase(
    file,
    setup: (raw) {
      // WAL + a busy timeout: the app may hold the file open, so both readers
      // and writers must wait on a lock rather than fail immediately.
      raw.execute('PRAGMA journal_mode = WAL');
      raw.execute('PRAGMA busy_timeout = ${busyTimeout.inMilliseconds}');
    },
  );
  return _NonMigratingAppDatabase(executor);
}

/// An [AppDatabase] whose migration strategy THROWS: the CLI is never the
/// migrator (the schema-version guard already refused a mismatch, so a matching
/// DB reaches drift with `from == to` and no migration is invoked — this is the
/// belt-and-braces guarantee that a schema change can never originate here).
class _NonMigratingAppDatabase extends AppDatabase {
  _NonMigratingAppDatabase(super.executor);

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => throw StateError(
      'timedart CLI must never create a database schema.',
    ),
    onUpgrade: (m, from, to) async => throw StateError(
      'timedart CLI must never migrate a database (v$from → v$to).',
    ),
    beforeOpen: (details) async {
      // Match the app: enforce foreign keys per connection.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
