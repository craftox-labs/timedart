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

    final profile =
        await (db.select(db.profiles)..where((p) => p.id.equals(1))).getSingle();
    expect(profile.templateId, 2, reason: 'paired theme 2 → templateId 2');
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

    final profile =
        await (db.select(db.profiles)..where((p) => p.id.equals(1))).getSingle();
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

    final client =
        await (db.select(db.clients)..where((c) => c.id.equals(1))).getSingle();
    expect(client.updatedAt, isNotNull);
    expect(client.createdAt, isNotNull);
    final entry = await (db.select(
      db.timeEntries,
    )..where((e) => e.id.equals(1))).getSingle();
    expect(entry.updatedAt, isNotNull);
    expect(entry.createdAt, isNotNull);
    // A subsequent update re-stamps updatedAt (choke-point behaviour).
    await db.updateClient(id: 1, name: 'Acme 2', defaultRate: 50);
    final after =
        await (db.select(db.clients)..where((c) => c.id.equals(1))).getSingle();
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

    final client =
        await (db.select(db.clients)..where((c) => c.id.equals(1))).getSingle();
    expect(client.deletedAt, isNull);
    // Visible through the filtered read paths (which now exclude tombstones).
    expect(await db.watchClients().first, hasLength(1));
    expect(await db.watchProjects().first, hasLength(1));
    expect(await db.watchEntriesForProject(1).first, hasLength(1));

    // And a soft-delete then hides it while keeping the row.
    await db.deleteEntry(1);
    expect(await db.watchEntriesForProject(1).first, isEmpty);
    final raw = await (db.select(
      db.timeEntries,
    )..where((t) => t.id.equals(1))).getSingle();
    expect(raw.deletedAt, isNotNull);
  });
}
