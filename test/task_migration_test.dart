import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:time_tracker/data/database.dart';

// Verifies the v1 → v2 migration: a schema-v1 database with free-text `task`
// strings upgrades to Tasks-as-entities without losing any tracked time.
void main() {
  test('v1→v2 folds distinct (job, task) into Tasks and repoints entries', () async {
    // Hand-build a schema-v1 database in memory (drift's generated v1 DDL, with
    // DateTimes stored as unix seconds and user_version = 1).
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
      INSERT INTO jobs (id, client_id, code, title) VALUES (2, 1, 'J2', 'Job Two');
      -- Two entries share (job 1, 'Design'); a third is a distinct task; a
      -- fourth reuses the same title 'Design' but under a different job.
      INSERT INTO time_entries (job_id, task, started_at, ended_at, seconds)
        VALUES (1, 'Design', 100, 200, 100),
               (1, 'Design', 300, 500, 200),
               (1, 'Build',  600, 700, 100),
               (2, 'Design', 800, 900, 100);
      PRAGMA user_version = 1;
    ''');

    // Opening AppDatabase over the seeded connection runs onUpgrade(1→2).
    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Distinct (job, title) pairs → three tasks: (1,Design) (1,Build) (2,Design).
    final tasks = await db.select(db.tasks).get();
    expect(tasks.length, 3);

    // Every entry is repointed and no tracked time changed.
    final entries = await db.select(db.timeEntries).get();
    expect(entries.length, 4);
    expect(entries.every((e) => e.taskId != null), isTrue);
    expect(entries.fold<int>(0, (s, e) => s + e.seconds), 500);

    // The two (job 1, 'Design') entries land on the SAME task; the same title
    // under job 2 is a DIFFERENT task.
    Task taskOf(int entryIndex) =>
        tasks.firstWhere((t) => t.id == entries[entryIndex].taskId);
    expect(taskOf(0).id, taskOf(1).id); // both job-1 Design
    expect(taskOf(0).title, 'Design');
    expect(taskOf(0).jobId, 1);
    expect(taskOf(3).jobId, 2); // job-2 Design
    expect(taskOf(0).id, isNot(taskOf(3).id));
  });
}
