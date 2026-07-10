import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';

// Exercises the task query/CRUD against a fresh in-memory DB (schema v3).
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('addEntry attaches to the given task', () async {
    final projectId = await db.ensureDefaultProject();
    final taskId = await db.addTask(projectId: projectId, title: 'Design');

    await db.addEntry(
      projectId: projectId,
      taskId: taskId,
      description: 'first pass',
      startedAt: DateTime(2026),
      endedAt: DateTime(2026),
      seconds: 60,
    );

    final entries = await db.select(db.timeEntries).get();
    expect(entries.single.taskId, taskId);
    expect(entries.single.description, 'first pass');
  });

  test('deleteTask is blocked while the task has time entries', () async {
    final projectId = await db.ensureDefaultProject();
    final taskId = await db.addTask(projectId: projectId, title: 'Build');
    await db.addEntry(
      projectId: projectId,
      taskId: taskId,
      startedAt: DateTime(2026),
      endedAt: DateTime(2026),
      seconds: 120,
    );

    // FK restrict: can't drop a task that still has entries.
    await expectLater(db.deleteTask(taskId), throwsA(anything));
    expect((await db.select(db.tasks).get()).length, 1);
    expect((await db.select(db.timeEntries).get()).length, 1);
  });

  test('deleteTask removes a task with no entries', () async {
    final projectId = await db.ensureDefaultProject();
    final taskId = await db.addTask(projectId: projectId, title: 'Empty');

    await db.deleteTask(taskId);

    expect(await db.select(db.tasks).get(), isEmpty);
  });
}
