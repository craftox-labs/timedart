import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';

// Exercises the task query/CRUD against a fresh in-memory DB (schema v3).
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  // A project to attach tasks/entries to (no default project is seeded).
  Future<String> aProject() async {
    final clientId = await db.addClient(name: 'Client', defaultRate: 50);
    return db.addProject(clientId: clientId, code: 'P1', title: 'Project');
  }

  test('addEntry attaches to the given task', () async {
    final projectId = await aProject();
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
    final projectId = await aProject();
    final taskId = await db.addTask(projectId: projectId, title: 'Build');
    await db.addEntry(
      projectId: projectId,
      taskId: taskId,
      startedAt: DateTime(2026),
      endedAt: DateTime(2026),
      seconds: 120,
    );

    // Blocked: can't drop a task that still has entries.
    await expectLater(
      db.deleteTask(taskId),
      throwsA(isA<DeleteBlockedException>()),
    );
    expect((await db.select(db.tasks).get()).length, 1);
    expect((await db.select(db.timeEntries).get()).length, 1);
  });

  test('deleteTask soft-deletes a task with no entries', () async {
    final projectId = await aProject();
    final taskId = await db.addTask(projectId: projectId, title: 'Empty');

    await db.deleteTask(taskId);

    // Gone from the filtered API, but the tombstone row survives (sync 2b).
    expect(await db.watchTasksForProject(projectId).first, isEmpty);
    final raw = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(taskId))).getSingle();
    expect(raw.deletedAt, isNotNull);
  });
}
