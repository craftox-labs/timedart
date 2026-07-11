import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:timedart/data/database.dart';

// End-to-end migration guard: seed the oldest shipped schema (v1) with real
// data and open AppDatabase, which runs EVERY onUpgrade branch (from=1 satisfies
// from<2 … from<10). This is the test that catches the crash-on-bump class — an
// unguarded DDL step that throws once schemaVersion advances — and proves the
// full 1→N ladder leaves a self-consistent DB with the user's time intact.
//
// When schemaVersion is bumped, add a matching assertion here (and a per-step
// data test) before release.
void main() {
  test('v1 → current: full ladder migrates cleanly and preserves data', () async {
    final raw = sqlite3.openInMemory();
    raw.execute('''
      CREATE TABLE clients (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL, email TEXT, address TEXT, abn TEXT,
        default_rate REAL, archived_at INTEGER);
      CREATE TABLE jobs (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        client_id INTEGER NOT NULL REFERENCES clients (id), code TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL, rate REAL, status TEXT NOT NULL DEFAULT 'active',
        created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')));
      CREATE TABLE time_entries (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        job_id INTEGER NOT NULL REFERENCES jobs (id), task TEXT NOT NULL,
        started_at INTEGER NOT NULL, ended_at INTEGER NOT NULL, seconds INTEGER NOT NULL);
      INSERT INTO clients (id, name) VALUES (1, 'Acme');
      INSERT INTO jobs (id, client_id, code, title) VALUES (1, 1, 'J1', 'Job One');
      INSERT INTO time_entries (job_id, task, started_at, ended_at, seconds)
        VALUES (1, 'Design', 100, 200, 100),
               (1, 'Build',  600, 700, 100),
               (1, 'Design', 300, 500, 200);
      PRAGMA user_version = 1;
    ''');

    // Opening over the seeded connection runs onUpgrade(1 → schemaVersion).
    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Drift opens lazily — the migration runs on first query, not construction.
    await db.customSelect('SELECT 1').get();

    // 1. The ladder actually ran to the head revision.
    final version = raw.select('PRAGMA user_version').first.values.first;
    expect(version, db.schemaVersion, reason: 'migrated to head schema');

    // 2. The resulting DB is structurally sound — every declared table exists
    //    and is queryable (a botched rebuild/rename would throw here), and no
    //    FK or integrity invariant is violated.
    for (final table in db.allTables) {
      await db.customSelect('SELECT * FROM ${table.actualTableName} LIMIT 1').get();
    }
    expect(raw.select('PRAGMA foreign_key_check').isEmpty, isTrue,
        reason: 'no dangling foreign keys after migration');
    expect(raw.select('PRAGMA integrity_check').first.values.first, 'ok');

    // 3. The user's tracked time survived the whole journey (v1 free-text tasks
    //    → Tasks-as-entities → renames → rebuilds). 100+100+200 = 400s.
    final entries = await db.select(db.timeEntries).get();
    expect(entries.length, 3);
    expect(entries.every((e) => e.taskId != null), isTrue);
    expect(entries.fold<int>(0, (s, e) => s + e.seconds), 400);
  });
}
