import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';

// Coverage for the first-run example data seed (PRD #133): it populates a small
// worked example into an empty database, exactly once, and never into a
// database that already holds data.

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> clientCount() async => (await db.select(db.clients).get()).length;
  Future<int> projectCount() async =>
      (await db.select(db.projects).get()).length;

  test('seeds one client, two projects, five tasks, eight entries', () async {
    await db.seedFirstRunExampleData();

    expect(await clientCount(), 1);
    expect(await projectCount(), 2);
    expect((await db.select(db.tasks).get()).length, 5);
    expect((await db.select(db.timeEntries).get()).length, 8);
  });

  test('is one-shot — a second call adds nothing', () async {
    await db.seedFirstRunExampleData();
    await db.seedFirstRunExampleData();

    expect(await clientCount(), 1);
    expect(await projectCount(), 2);
  });

  test('does not seed into a database that already has data', () async {
    // Mimic an existing install upgrading: it already has a client.
    await db.addClient(name: 'Real Client', defaultRate: 120);

    await db.seedFirstRunExampleData();

    expect(await clientCount(), 1); // no example client added
    expect(await projectCount(), 0);
    // The flag is still set, so it won't re-check on every launch.
    await db.seedFirstRunExampleData();
    expect(await clientCount(), 1);
  });

  test('firstProjectId is null on an empty DB, the example project after seed',
      () async {
    expect(await db.firstProjectId(), isNull);

    await db.seedFirstRunExampleData();

    final id = await db.firstProjectId();
    expect(id, isNotNull);
    final project = await db.getProject(id!);
    expect(project.title, 'Example Project'); // sorts before "Example Project 2"
  });
}
