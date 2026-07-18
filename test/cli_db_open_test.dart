import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:timedart/cli/db_open.dart';
import 'package:timedart/cli/exit_codes.dart';
import 'package:timedart/data/database.dart';

// Coverage for the CLI DB-open seam (issue #271): per-platform path resolution
// without path_provider, the schema-version guard (accepts a match, refuses a
// mismatch, never migrates), and the --db / TIMEDART_DB override.

/// Create a real on-disk timedart DB at the app's current schema (v16) by
/// opening [AppDatabase] over the file and forcing drift's onCreate to run.
Future<void> _seedSchema16(File file) async {
  final db = AppDatabase(NativeDatabase(file));
  await db.customStatement('SELECT 1'); // forces lazy open → createAll()
  await db.close();
}

void main() {
  group('defaultDataDirectory (path_provider-free)', () {
    test('Linux honours XDG_DATA_HOME', () {
      final dir = defaultDataDirectory(
        operatingSystem: 'linux',
        environment: {'XDG_DATA_HOME': '/home/u/.local/share'},
        home: '/home/u',
      );
      expect(dir, '/home/u/.local/share/timedart');
    });

    test('Linux falls back to ~/.local/share when XDG unset', () {
      final dir = defaultDataDirectory(
        operatingSystem: 'linux',
        environment: const {},
        home: '/home/u',
      );
      expect(dir, '/home/u/.local/share/timedart');
    });

    test('macOS uses Application Support', () {
      final dir = defaultDataDirectory(
        operatingSystem: 'macos',
        environment: const {},
        home: '/Users/u',
      );
      expect(dir, '/Users/u/Library/Application Support/timedart');
    });

    test('Windows uses %APPDATA%', () {
      final dir = defaultDataDirectory(
        operatingSystem: 'windows',
        environment: {'APPDATA': r'C:\Users\u\AppData\Roaming'},
        home: r'C:\Users\u',
      );
      expect(dir, r'C:\Users\u\AppData\Roaming\timedart');
    });

    test('missing home on Linux throws a clear error', () {
      expect(
        () => defaultDataDirectory(
          operatingSystem: 'linux',
          environment: const {},
          home: null,
        ),
        throwsA(isA<CliException>()),
      );
    });
  });

  group('resolveDbPath override precedence', () {
    const env = {
      'XDG_DATA_HOME': '/home/u/.local/share',
      'TIMEDART_DB': '/env/scratch.sqlite',
    };

    test('explicit --db wins over env and default', () {
      final p = resolveDbPath(
        override: '/explicit/my.sqlite',
        operatingSystem: 'linux',
        environment: env,
        home: '/home/u',
      );
      expect(p, '/explicit/my.sqlite');
    });

    test('TIMEDART_DB used when no --db', () {
      final p = resolveDbPath(
        operatingSystem: 'linux',
        environment: env,
        home: '/home/u',
      );
      expect(p, '/env/scratch.sqlite');
    });

    test('default per-platform file when neither set', () {
      final p = resolveDbPath(
        operatingSystem: 'linux',
        environment: {'XDG_DATA_HOME': '/home/u/.local/share'},
        home: '/home/u',
      );
      expect(p, '/home/u/.local/share/timedart/timedart.sqlite');
    });
  });

  group('openTimedartDb schema-version guard', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('timedart_cli_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('accepts a matching-version DB and applies WAL', () async {
      final file = File('${tmp.path}/timedart.sqlite');
      await _seedSchema16(file);

      final db = openTimedartDb(file.path);
      addTearDown(db.close);

      // A read through the shared data layer works.
      expect(await db.activeTimer(), isNull);
      // WAL was applied on open.
      final mode = await db.customSelect('PRAGMA journal_mode').getSingle();
      expect(
        (mode.data.values.first as String).toLowerCase(),
        'wal',
      );
      // busy_timeout was applied.
      final bt = await db.customSelect('PRAGMA busy_timeout').getSingle();
      expect(bt.data.values.first, greaterThan(0));
    });

    test('refuses a mismatched-version DB and never migrates', () async {
      final file = File('${tmp.path}/old.sqlite');
      // Hand-build a DB stamped at an older schema version.
      final raw = sqlite3.open(file.path);
      raw.execute('PRAGMA user_version = 15');
      raw.execute('CREATE TABLE marker (a INTEGER)');
      raw.close();

      expect(
        () => openTimedartDb(file.path),
        throwsA(
          isA<CliException>().having(
            (e) => e.exitCode,
            'exitCode',
            CliExit.schemaMismatch,
          ),
        ),
      );

      // The guard must NOT have touched the file: version + tables unchanged.
      final after = sqlite3.open(file.path);
      addTearDown(after.close);
      final v = after.select('PRAGMA user_version').first.columnAt(0);
      expect(v, 15, reason: 'CLI must never migrate');
      final tables = after
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r.columnAt(0))
          .toList();
      expect(tables, contains('marker'));
    });

    test('missing file fails with dbNotFound', () {
      expect(
        () => openTimedartDb('${tmp.path}/does-not-exist.sqlite'),
        throwsA(
          isA<CliException>().having(
            (e) => e.exitCode,
            'exitCode',
            CliExit.dbNotFound,
          ),
        ),
      );
    });
  });
}
