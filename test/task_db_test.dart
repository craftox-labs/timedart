import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';

// Exercises the task query/CRUD against a fresh in-memory DB (schema v2).
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('addEntry links to an existing task by (job, title)', () async {
    final jobId = await db.ensureDefaultJob();
    final taskId = await db.addTask(jobId: jobId, title: 'Design');

    await db.addEntry(
      jobId: jobId,
      task: 'Design',
      startedAt: DateTime(2026),
      endedAt: DateTime(2026),
      seconds: 60,
    );

    // No new task created — the entry reuses the existing 'Design'.
    final tasks = await db.select(db.tasks).get();
    expect(tasks.length, 1);
    final entries = await db.select(db.timeEntries).get();
    expect(entries.single.taskId, taskId);
  });

  test('deleteTask removes the task and cascades to its entries', () async {
    final jobId = await db.ensureDefaultJob();
    final taskId = await db.addTask(jobId: jobId, title: 'Build');
    await db.addEntry(
      jobId: jobId,
      task: 'Build',
      startedAt: DateTime(2026),
      endedAt: DateTime(2026),
      seconds: 120,
    );
    expect((await db.select(db.timeEntries).get()).length, 1);

    await db.deleteTask(taskId);

    expect(await db.select(db.tasks).get(), isEmpty);
    expect(await db.select(db.timeEntries).get(), isEmpty);
  });
}
