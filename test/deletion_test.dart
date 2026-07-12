import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';

// The delete interface is the test surface: deleteX throws DeleteBlockedException
// when LIVE dependents exist and succeeds otherwise. Deletes are soft (PRD #189,
// Phase 2b) — the row stays in the table with deletedAt set (a sync tombstone)
// but drops out of the filtered read/watch API.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> seedClient() => db.addClient(name: 'Acme', defaultRate: 100);

  // Raw row (bypasses the deletedAt filter) so tests can inspect the tombstone.
  Future<Client?> rawClient(int id) =>
      (db.select(db.clients)..where((c) => c.id.equals(id))).getSingleOrNull();
  Future<Project?> rawProject(int id) =>
      (db.select(db.projects)..where((p) => p.id.equals(id))).getSingleOrNull();

  test('deleteClient blocked while it has projects, then succeeds', () async {
    final clientId = await seedClient();
    final projectId = await db.addProject(
      clientId: clientId,
      code: 'P1',
      title: 'Site',
    );

    await expectLater(
      db.deleteClient(clientId),
      throwsA(isA<DeleteBlockedException>()),
    );
    expect(await db.watchClients().first, hasLength(1));

    // Remove the dependent, then the delete goes through.
    await db.deleteProject(projectId);
    await db.deleteClient(clientId);
    // Gone from the filtered API…
    expect(await db.watchClients().first, isEmpty);
    // …but the tombstone row survives with deletedAt set.
    final tomb = await rawClient(clientId);
    expect(tomb, isNotNull);
    expect(tomb!.deletedAt, isNotNull);
  });

  test('deleteProject blocked by tasks (no entries)', () async {
    final clientId = await seedClient();
    final projectId = await db.addProject(
      clientId: clientId,
      code: 'P1',
      title: 'Site',
    );
    await db.addTask(projectId: projectId, title: 'Design');

    await expectLater(
      db.deleteProject(projectId),
      throwsA(isA<DeleteBlockedException>()),
    );
    expect(await db.watchProjects().first, hasLength(1));
  });

  test('deleteProject blocked by time entries', () async {
    final clientId = await seedClient();
    final projectId = await db.addProject(
      clientId: clientId,
      code: 'P1',
      title: 'Site',
    );
    await db.addEntry(
      projectId: projectId,
      taskId: await db.addTask(projectId: projectId, title: 'Build'),
      startedAt: DateTime(2026),
      endedAt: DateTime(2026),
      seconds: 60,
    );
    await expectLater(
      db.deleteProject(projectId),
      throwsA(isA<DeleteBlockedException>()),
    );
  });

  test('deleteProject succeeds with no dependents (soft-delete)', () async {
    final clientId = await seedClient();
    final projectId = await db.addProject(
      clientId: clientId,
      code: 'P1',
      title: 'Empty',
    );
    await db.deleteProject(projectId);
    expect(await db.watchProjects().first, isEmpty);
    final tomb = await rawProject(projectId);
    expect(tomb!.deletedAt, isNotNull);
  });

  // The referential guard counts only LIVE children: a project whose tasks and
  // entries are all soft-deleted can itself be deleted.
  test('deleteProject unblocked once its children are soft-deleted', () async {
    final clientId = await seedClient();
    final projectId = await db.addProject(
      clientId: clientId,
      code: 'P1',
      title: 'Site',
    );
    final taskId = await db.addTask(projectId: projectId, title: 'Build');
    await db.addEntry(
      projectId: projectId,
      taskId: taskId,
      startedAt: DateTime(2026),
      endedAt: DateTime(2026),
      seconds: 60,
    );

    // Blocked while the task/entry are live.
    await expectLater(
      db.deleteProject(projectId),
      throwsA(isA<DeleteBlockedException>()),
    );

    // Soft-delete the children (entry first — deleteTask guards on live entries).
    for (final e in await db.watchEntriesForProject(projectId).first) {
      await db.deleteEntry(e.id);
    }
    await db.deleteTask(taskId);

    // Now the project deletes cleanly.
    await db.deleteProject(projectId);
    expect(await db.watchProjects().first, isEmpty);
  });

  test('soft-delete hides the entry but keeps a stamped tombstone', () async {
    final clientId = await seedClient();
    final projectId = await db.addProject(
      clientId: clientId,
      code: 'P1',
      title: 'Site',
    );
    final taskId = await db.addTask(projectId: projectId, title: 'Build');
    await db.addEntry(
      projectId: projectId,
      taskId: taskId,
      startedAt: DateTime(2026),
      endedAt: DateTime(2026),
      seconds: 60,
    );
    final entry = (await db.watchEntriesForProject(projectId).first).single;
    final before = entry.updatedAt;

    await db.deleteEntry(entry.id);

    // Absent from every filtered read path.
    expect(await db.watchEntriesForProject(projectId).first, isEmpty);
    expect(await db.watchEntriesForTask(taskId).first, isEmpty);

    // Raw row survives with deletedAt set and updatedAt bumped.
    final raw = await (db.select(
      db.timeEntries,
    )..where((t) => t.id.equals(entry.id))).getSingle();
    expect(raw.deletedAt, isNotNull);
    expect(raw.updatedAt, isNotNull);
    if (before != null) {
      expect(raw.updatedAt!.isBefore(before), isFalse);
    }
  });

  test('deleteTemplate/deleteProfile soft-delete but stay resolvable', () async {
    await db.ensureInvoiceDefaults();
    final template = (await db.watchTemplates().first).single;
    final profile = (await db.watchProfiles().first).single;

    await db.deleteTemplate(template.id);
    await db.deleteProfile(profile.id);

    // Hidden from the lists…
    expect(await db.watchTemplates().first, isEmpty);
    expect(await db.watchProfiles().first, isEmpty);
    // …but still resolvable by id for a past invoice pointing at them.
    expect((await db.templateById(template.id)).deletedAt, isNotNull);
    expect((await db.profileById(profile.id)).deletedAt, isNotNull);
  });

  test('the exception names the blocked entity', () async {
    final clientId = await seedClient();
    await db.addProject(clientId: clientId, code: 'P1', title: 'Site');
    try {
      await db.deleteClient(clientId);
      fail('expected DeleteBlockedException');
    } on DeleteBlockedException catch (e) {
      expect(e.entity, 'client');
    }
  });
}
