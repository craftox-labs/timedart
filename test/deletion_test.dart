import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';

// The delete interface is the test surface: deleteX throws DeleteBlockedException
// when dependents exist and succeeds otherwise. Previously this rule was only
// reachable through the UI's blind catch (#182).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> seedClient() =>
      db.addClient(name: 'Acme', defaultRate: 100);

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
    expect((await db.select(db.clients).get()).length, 1);

    // Remove the dependent, then the delete goes through.
    await db.deleteProject(projectId);
    await db.deleteClient(clientId);
    expect(await db.select(db.clients).get(), isEmpty);
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
    expect((await db.select(db.projects).get()).length, 1);
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

  test('deleteProject succeeds with no dependents', () async {
    final clientId = await seedClient();
    final projectId = await db.addProject(
      clientId: clientId,
      code: 'P1',
      title: 'Empty',
    );
    await db.deleteProject(projectId);
    expect(await db.select(db.projects).get(), isEmpty);
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
