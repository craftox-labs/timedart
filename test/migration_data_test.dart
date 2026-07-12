import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';

import 'generated/schema.dart';

// Data-preservation tests for the two migration steps that *move* data between
// tables (structure is covered by migration_schema_test.dart; these assert the
// values land correctly). Each seeds a real historical DB via the verifier's
// rawDatabase, then opens AppDatabase (migrating to head) and reads back through
// the current API.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  // v5→v6 folds the Theme+Profile *pairing* table into profiles.templateId:
  // profile 1 was paired (via the pairing row) with theme 2, so after the fold
  // its templateId must point at 2 (the theme, renamed to a template at v6).
  test('v5→v6: profile.templateId is backfilled from the old pairing', () async {
    final schema = await verifier.schemaAt(5);
    schema.rawDatabase.execute('''
      INSERT INTO themes (id, name, color_background, color_surface,
        color_primary, color_text, color_accent)
        VALUES (1, 'Blue', 1, 2, 3, 4, 5), (2, 'Red', 10, 20, 30, 40, 50);
      INSERT INTO profiles (id, name) VALUES (1, 'Acme');
      INSERT INTO templates (id, name, theme_id, profile_id)
        VALUES (1, 'Acme pairing', 2, 1);
    ''');

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    // The ladder runs on to the v13 re-key, so ids are uuids now — identify the
    // paired template by its name ('Red' = old theme 2) rather than id 2.
    final profile = (await db.select(db.profiles).get()).single;
    final red = (await db.select(
      db.templates,
    ).get()).firstWhere((t) => t.name == 'Red');
    expect(profile.templateId, red.id, reason: 'paired theme "Red" → its id');
  });

  // v7→v8 moves the logo from the template (visual style) to the profile
  // (business identity), backfilling each profile from its linked template.
  test('v7→v8: profile inherits its template logo', () async {
    final schema = await verifier.schemaAt(7);
    schema.rawDatabase.execute('''
      INSERT INTO templates (id, name, logo, logo_mime, color_background,
        color_surface, color_primary, color_text, color_accent, is_default)
        VALUES (1, 'Brand', x'0102030405', 'image/png', 1, 2, 3, 4, 5, 1);
      INSERT INTO profiles (id, name, template_id) VALUES (1, 'Acme', 1);
    ''');

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    final profile = (await db.select(db.profiles).get()).single;
    expect(profile.logo, isNotNull);
    expect(profile.logo!.toList(), [1, 2, 3, 4, 5]);
    expect(profile.logoMime, 'image/png');
  });

  // v10→v11 adds row-audit timestamps and backfills existing rows to the
  // migration time, so no pre-existing row is left with a null updatedAt.
  test('v10→v11: existing rows get backfilled timestamps', () async {
    final schema = await verifier.schemaAt(10);
    schema.rawDatabase.execute('''
      INSERT INTO clients (id, name, default_rate) VALUES (1, 'Acme', 50);
      INSERT INTO projects (id, client_id, code, title)
        VALUES (1, 1, 'P1', 'Work');
      INSERT INTO tasks (id, project_id, title) VALUES (1, 1, 'Build');
      INSERT INTO time_entries (id, project_id, task_id, started_at, ended_at,
        seconds) VALUES (1, 1, 1, 0, 3600, 3600);
    ''');

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    final client = (await db.select(db.clients).get()).single;
    expect(client.updatedAt, isNotNull);
    expect(client.createdAt, isNotNull);
    final entry = (await db.select(db.timeEntries).get()).single;
    expect(entry.updatedAt, isNotNull);
    expect(entry.createdAt, isNotNull);
    // A subsequent update re-stamps updatedAt (choke-point behaviour).
    await db.updateClient(id: client.id, name: 'Acme 2', defaultRate: 50);
    final after = await (db.select(
      db.clients,
    )..where((c) => c.id.equals(client.id))).getSingle();
    expect(after.updatedAt, isNotNull);
  });

  // v11→v12 adds the soft-delete tombstone column. Existing rows must survive
  // with deletedAt NULL (live) and stay visible through the filtered API.
  test('v11→v12: existing rows survive as live (deletedAt null)', () async {
    final schema = await verifier.schemaAt(11);
    schema.rawDatabase.execute('''
      INSERT INTO clients (id, name, default_rate) VALUES (1, 'Acme', 50);
      INSERT INTO projects (id, client_id, code, title)
        VALUES (1, 1, 'P1', 'Work');
      INSERT INTO tasks (id, project_id, title) VALUES (1, 1, 'Build');
      INSERT INTO time_entries (id, project_id, task_id, started_at, ended_at,
        seconds) VALUES (1, 1, 1, 0, 3600, 3600);
    ''');

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    final client = (await db.select(db.clients).get()).single;
    expect(client.deletedAt, isNull);
    final project = (await db.select(db.projects).get()).single;
    final entry = (await db.select(db.timeEntries).get()).single;
    // Visible through the filtered read paths (which now exclude tombstones).
    expect(await db.watchClients().first, hasLength(1));
    expect(await db.watchProjects().first, hasLength(1));
    expect(await db.watchEntriesForProject(project.id).first, hasLength(1));

    // And a soft-delete then hides it while keeping the row.
    await db.deleteEntry(entry.id);
    expect(await db.watchEntriesForProject(project.id).first, isEmpty);
    final raw = (await db.select(db.timeEntries).get()).single;
    expect(raw.deletedAt, isNotNull);
  });

  // v12→v13 re-keys every int PK/FK to a text UUIDv7 in place. The whole graph
  // must survive with its relationships intact, ids must become uuids, and
  // orphans (children whose FK parent is gone — the live DB carries some SQLite
  // never caught, see #196) must be dropped so the re-map can't hit a null FK.
  test('v12→v13: re-keys to uuids, preserves the graph, drops orphans', () async {
    final schema = await verifier.schemaAt(12);
    schema.rawDatabase.execute('''
      INSERT INTO clients (id, name, default_rate) VALUES (1, 'Acme', 50);
      INSERT INTO projects (id, client_id, code, title)
        VALUES (1, 1, 'P1', 'Work');
      INSERT INTO tasks (id, project_id, title) VALUES (1, 1, 'Build');
      INSERT INTO time_entries (id, project_id, task_id, started_at, ended_at,
        seconds) VALUES (1, 1, 1, 0, 3600, 3600);
      -- Orphans: a task + entry pointing at a project (99) that doesn't exist.
      INSERT INTO tasks (id, project_id, title) VALUES (2, 99, 'Orphan');
      INSERT INTO time_entries (id, project_id, task_id, started_at, ended_at,
        seconds) VALUES (2, 99, 2, 0, 60, 60);
    ''');

    final db = AppDatabase(schema.newConnection());
    addTearDown(db.close);

    // The orphan task + entry were dropped; the valid graph survived.
    final client = (await db.select(db.clients).get()).single;
    final project = (await db.select(db.projects).get()).single;
    final task = (await db.select(db.tasks).get()).single;
    final entry = (await db.select(db.timeEntries).get()).single;
    expect(client.name, 'Acme');
    expect(task.title, 'Build');
    expect(entry.seconds, 3600);

    // Every id is a re-keyed uuid (not the leftover ints), and the FKs still
    // resolve to the right rows.
    expect(int.tryParse(client.id), isNull, reason: 're-keyed to a uuid');
    expect(int.tryParse(project.id), isNull);
    expect(project.clientId, client.id);
    expect(task.projectId, project.id);
    expect(entry.projectId, project.id);
    expect(entry.taskId, task.id);
  });
}
