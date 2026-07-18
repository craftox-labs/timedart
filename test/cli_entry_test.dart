import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/cli/cli.dart';
import 'package:timedart/cli/exit_codes.dart';
import 'package:timedart/cli/list_query.dart';
import 'package:timedart/data/database.dart';

// CLI slice for issue #284: time-entry CRUD (list/edit/delete entries) — the
// biggest remaining parity gap once #280 covered the client/project/task
// graph. Follows cli_crud_test.dart's pattern: drive `runTimedartCli` and
// assert on the exit code + resulting DB state (JSON *shapes* are pinned in
// cli_json_contract_test.dart).

class _Seed {
  final File file;
  final String clientId;
  final String projectA; // ACME / Acme Website
  final String projectB; // GLOB / Globex Site
  final String taskDesign; // under A
  final String taskBuild; // under B
  _Seed(
    this.file,
    this.clientId,
    this.projectA,
    this.projectB,
    this.taskDesign,
    this.taskBuild,
  );
}

Future<_Seed> _seed(Directory tmp) async {
  final file = File('${tmp.path}/timedart.sqlite');
  final db = AppDatabase(NativeDatabase(file));
  final c = await db.addClient(name: 'Acme Co', defaultRate: 100);
  final a = await db.addProject(clientId: c, code: 'ACME', title: 'Acme Website');
  final b = await db.addProject(clientId: c, code: 'GLOB', title: 'Globex Site');
  final design = await db.addTask(projectId: a, title: 'Design');
  final build = await db.addTask(projectId: b, title: 'Build');
  await db.close();
  return _Seed(file, c, a, b, design, build);
}

AppDatabase _open(File file) => AppDatabase(NativeDatabase(file));

Future<String> _addEntry(
  File file, {
  required String projectId,
  required String taskId,
  String? description,
  required DateTime startedAt,
  required int seconds,
}) async {
  final db = _open(file);
  final endedAt = startedAt.add(Duration(seconds: seconds));
  await db.addEntry(
    projectId: projectId,
    taskId: taskId,
    description: description,
    startedAt: startedAt,
    endedAt: endedAt,
    seconds: seconds,
  );
  final row = (await (db.select(db.timeEntries)
        ..where((e) => e.taskId.equals(taskId) & e.startedAt.equals(startedAt)))
      .get()).single;
  await db.close();
  return row.id;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('timedart_cli_entry_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('list entries', () {
    test('most-recent-first, live only', () async {
      final s = await _seed(tmp);
      final first = await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        startedAt: DateTime(2026, 1, 1),
        seconds: 600,
      );
      final secondId = await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        startedAt: DateTime(2026, 1, 5),
        seconds: 600,
      );
      final db = _open(s.file);
      await db.deleteEntry(secondId); // soft-deleted → excluded
      await db.close();
      final third = await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        startedAt: DateTime(2026, 1, 3),
        seconds: 600,
      );

      final db2 = _open(s.file);
      addTearDown(db2.close);
      final items = await queryEntries(db2);
      expect(items.map((e) => e.id), [third, first]); // most-recent-first
    });

    test('--project filters to that project only', () async {
      final s = await _seed(tmp);
      await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        startedAt: DateTime(2026, 1, 1),
        seconds: 600,
      );
      await _addEntry(
        s.file,
        projectId: s.projectB,
        taskId: s.taskBuild,
        startedAt: DateTime(2026, 1, 2),
        seconds: 600,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      final items = await queryEntries(db, projectId: s.projectA);
      expect(items, hasLength(1));
      expect(items.single.projectId, s.projectA);
    });

    test('--task filters to that task only', () async {
      final s = await _seed(tmp);
      await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        startedAt: DateTime(2026, 1, 1),
        seconds: 600,
      );
      await _addEntry(
        s.file,
        projectId: s.projectB,
        taskId: s.taskBuild,
        startedAt: DateTime(2026, 1, 2),
        seconds: 600,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      final items = await queryEntries(db, taskId: s.taskBuild);
      expect(items, hasLength(1));
      expect(items.single.taskId, s.taskBuild);
    });

    test('--since/--until date window is inclusive', () async {
      final s = await _seed(tmp);
      await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        startedAt: DateTime(2026, 1, 1),
        seconds: 600,
      );
      final inWindow = await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        startedAt: DateTime(2026, 1, 5),
        seconds: 600,
      );
      await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        startedAt: DateTime(2026, 1, 10),
        seconds: 600,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      final items = await queryEntries(
        db,
        since: DateTime(2026, 1, 5), // exact boundary → included
        until: DateTime(2026, 1, 9),
      );
      expect(items.map((e) => e.id), [inWindow]);
    });

    test('dispatcher returns success', () async {
      final s = await _seed(tmp);
      await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        startedAt: DateTime(2026, 1, 1),
        seconds: 600,
      );
      expect(
        await runTimedartCli([
          'list', 'entries', '--json', '--db', s.file.path,
        ]),
        CliExit.success,
      );
    });
  });

  group('entry edit', () {
    test('only the passed fields change (description)', () async {
      final s = await _seed(tmp);
      final id = await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        description: 'original',
        startedAt: DateTime(2026, 1, 1, 9),
        seconds: 600,
      );
      expect(
        await runTimedartCli([
          'entry', 'edit', id, '--description', 'updated', //
          '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      final e = (await (db.select(db.timeEntries)
            ..where((t) => t.id.equals(id)))
          .get()).single;
      expect(e.description, 'updated');
      expect(e.seconds, 600); // untouched
      expect(e.startedAt, DateTime(2026, 1, 1, 9)); // untouched
      expect(e.taskId, s.taskDesign); // untouched
      expect(e.projectId, s.projectA); // untouched
    });

    test('--duration recomputes seconds and shifts endedAt, keeps startedAt',
        () async {
      final s = await _seed(tmp);
      final started = DateTime(2026, 1, 1, 9);
      final id = await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        startedAt: started,
        seconds: 600,
      );
      expect(
        await runTimedartCli([
          'entry', 'edit', id, '--duration', '30m', '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      final e = (await (db.select(db.timeEntries)
            ..where((t) => t.id.equals(id)))
          .get()).single;
      expect(e.seconds, 1800);
      expect(e.startedAt, started); // untouched
      expect(e.endedAt, started.add(const Duration(minutes: 30)));
    });

    test('--at/--end change the window and recompute seconds from it',
        () async {
      final s = await _seed(tmp);
      final id = await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        startedAt: DateTime(2026, 1, 1, 9),
        seconds: 600,
      );
      expect(
        await runTimedartCli([
          'entry', 'edit', id, //
          '--at', '2026-01-01T10:00:00', '--end', '2026-01-01T11:30:00', //
          '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      final e = (await (db.select(db.timeEntries)
            ..where((t) => t.id.equals(id)))
          .get()).single;
      expect(e.startedAt, DateTime(2026, 1, 1, 10));
      expect(e.endedAt, DateTime(2026, 1, 1, 11, 30));
      expect(e.seconds, 90 * 60); // 1h30m recomputed from the new window
    });

    test('--task rebind keeps projectId consistent with the new task\'s '
        'project', () async {
      final s = await _seed(tmp);
      final id = await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        startedAt: DateTime(2026, 1, 1, 9),
        seconds: 600,
      );
      expect(
        await runTimedartCli([
          'entry', 'edit', id, '--task', 'Build', '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      final e = (await (db.select(db.timeEntries)
            ..where((t) => t.id.equals(id)))
          .get()).single;
      expect(e.taskId, s.taskBuild);
      expect(e.projectId, s.projectB); // followed the task, not left stale
    });

    test('unknown entry id → unknownEntity (5)', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'entry', 'edit', 'not-a-real-id', '--duration', '10m', //
          '--db', s.file.path,
        ]),
        CliExit.unknownEntity,
      );
    });
  });

  group('entry delete', () {
    test('without --force refuses (10) and changes nothing', () async {
      final s = await _seed(tmp);
      final id = await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        startedAt: DateTime(2026, 1, 1, 9),
        seconds: 600,
      );
      expect(
        await runTimedartCli(['entry', 'delete', id, '--db', s.file.path]),
        CliExit.confirmationRequired,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      final e = (await (db.select(db.timeEntries)
            ..where((t) => t.id.equals(id)))
          .get()).single;
      expect(e.deletedAt, isNull);
    });

    test('--force soft-deletes it', () async {
      final s = await _seed(tmp);
      final id = await _addEntry(
        s.file,
        projectId: s.projectA,
        taskId: s.taskDesign,
        startedAt: DateTime(2026, 1, 1, 9),
        seconds: 600,
      );
      expect(
        await runTimedartCli([
          'entry', 'delete', id, '--force', '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      final e = (await (db.select(db.timeEntries)
            ..where((t) => t.id.equals(id)))
          .get()).single;
      expect(e.deletedAt, isNotNull);
    });

    test('unknown entry id → unknownEntity (5), structured JSON error',
        () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'entry', 'delete', 'not-a-real-id', '--force', '--db', s.file.path,
        ]),
        CliExit.unknownEntity,
      );
    });
  });
}
