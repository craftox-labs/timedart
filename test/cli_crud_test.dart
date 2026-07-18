import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/cli/cli.dart';
import 'package:timedart/cli/exit_codes.dart';
import 'package:timedart/cli/list_query.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/tracker/timer_store.dart';

// CLI slice for issue #280: entity CRUD (clients/projects/tasks) — create,
// edit, archive/unarchive, and cascade delete with the --force guard. Follows
// the prior slices' pattern: drive `runTimedartCli` and assert on the exit code
// + the resulting DB state (JSON *shapes* are pinned in cli_json_contract_test).

class _Seed {
  final File file;
  final String clientId;
  final String projectA; // ACME / Acme Website
  final String taskDesign; // under A
  _Seed(this.file, this.clientId, this.projectA, this.taskDesign);
}

Future<_Seed> _seed(Directory tmp) async {
  final file = File('${tmp.path}/timedart.sqlite');
  final db = AppDatabase(NativeDatabase(file));
  final c = await db.addClient(name: 'Acme Co', defaultRate: 100);
  final a = await db.addProject(clientId: c, code: 'ACME', title: 'Acme Website');
  final design = await db.addTask(projectId: a, title: 'Design');
  await db.close();
  return _Seed(file, c, a, design);
}

AppDatabase _open(File file) => AppDatabase(NativeDatabase(file));

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('timedart_cli_crud_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('list clients', () {
    test('queryClients returns live rows with rate, name-ordered', () async {
      final s = await _seed(tmp);
      final db = _open(s.file);
      await db.addClient(name: 'Beta Co', defaultRate: 50);
      final items = await queryClients(db);
      await db.close();
      expect(items.map((c) => c.name), ['Acme Co', 'Beta Co']); // name order
      expect(items.first.id, s.clientId);
      expect(items.first.defaultRate, 100);
    });

    test('dispatcher returns success', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli(['list', 'clients', '--json', '--db', s.file.path]),
        CliExit.success,
      );
    });

    test('soft-deleted client excluded', () async {
      final s = await _seed(tmp);
      final db = _open(s.file);
      await db.deleteClientCascade(s.clientId);
      final items = await queryClients(db);
      await db.close();
      expect(items, isEmpty);
    });
  });

  group('client add / edit / archive', () {
    test('add creates a live client with the given fields', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'client', 'add', '--name', 'Globex', '--rate', '150', //
          '--email', 'ops@globex.test', '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      final rows = await (db.select(db.clients)
            ..where((c) => c.name.equals('Globex')))
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.defaultRate, 150);
      expect(rows.single.email, 'ops@globex.test');
      expect(rows.single.deletedAt, isNull);
    });

    test('add without --rate → usage', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'client', 'add', '--name', 'NoRate', '--db', s.file.path,
        ]),
        CliExit.usage,
      );
    });

    test('add with a non-numeric --rate → usage', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'client', 'add', '--name', 'Bad', '--rate', 'lots', //
          '--db', s.file.path,
        ]),
        CliExit.usage,
      );
    });

    test('edit changes only the passed fields', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'client', 'edit', 'Acme Co', '--name', 'Acme Inc', //
          '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      final c = await db.getClient(s.clientId);
      expect(c.name, 'Acme Inc');
      expect(c.defaultRate, 100); // untouched
    });

    test('edit clears an optional field with an empty value', () async {
      final s = await _seed(tmp);
      await runTimedartCli([
        'client', 'edit', 'Acme Co', '--phone', '12345', '--db', s.file.path,
      ]);
      expect(
        await runTimedartCli([
          'client', 'edit', 'Acme Co', '--phone', '', '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      expect((await db.getClient(s.clientId)).phone, isNull);
    });

    test('archive then unarchive toggles archivedAt, never deletes', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli(['client', 'archive', 'Acme Co', '--db', s.file.path]),
        CliExit.success,
      );
      var db = _open(s.file);
      expect((await db.getClient(s.clientId)).archivedAt, isNotNull);
      await db.close();

      expect(
        await runTimedartCli(['client', 'unarchive', 'Acme Co', '--db', s.file.path]),
        CliExit.success,
      );
      db = _open(s.file);
      addTearDown(db.close);
      final c = await db.getClient(s.clientId);
      expect(c.archivedAt, isNull);
      expect(c.deletedAt, isNull);
    });

    test('unknown client selector → unknownEntity', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'client', 'edit', 'Ghost', '--name', 'X', '--db', s.file.path,
        ]),
        CliExit.unknownEntity,
      );
    });

    test('edit with no selector → usage', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'client', 'edit', '--name', 'X', '--db', s.file.path,
        ]),
        CliExit.usage,
      );
    });
  });

  group('project add / edit', () {
    test('add under a client, rate omitted = inherit (null)', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'project', 'add', '--client', 'Acme Co', '--code', 'GLOB', //
          '--title', 'Globe', '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      final p = (await (db.select(db.projects)
            ..where((p) => p.code.equals('GLOB')))
          .get()).single;
      expect(p.clientId, s.clientId);
      expect(p.rate, isNull);
    });

    test('add with an explicit rate sets it', () async {
      final s = await _seed(tmp);
      await runTimedartCli([
        'project', 'add', '--client', 'Acme Co', '--code', 'RATE', //
        '--title', 'Rated', '--rate', '175', '--db', s.file.path,
      ]);
      final db = _open(s.file);
      addTearDown(db.close);
      final p = (await (db.select(db.projects)
            ..where((p) => p.code.equals('RATE')))
          .get()).single;
      expect(p.rate, 175);
    });

    test('duplicate code → constraintViolation', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'project', 'add', '--client', 'Acme Co', '--code', 'ACME', //
          '--title', 'Dup', '--db', s.file.path,
        ]),
        CliExit.constraintViolation,
      );
    });

    // `runTimedartCli` only returns the exit code (the message goes to
    // stderr), so this drives the real duplicate-code failure straight through
    // the DB layer and pins the clean message (#288): no raw SqliteException,
    // no SQL, no bound parameters.
    test(
      'duplicate code → clean message naming the code, no raw SQL',
      () async {
        final s = await _seed(tmp);
        final db = _open(s.file);
        addTearDown(db.close);
        Object? caught;
        try {
          await db.addProject(clientId: s.clientId, code: 'ACME', title: 'Dup');
        } catch (e) {
          caught = e;
        }
        expect(caught, isNotNull);
        expect(caught.toString(), contains('UNIQUE'));
        final message = constraintViolationMessage(
          caught!,
          projectCode: 'ACME',
        );
        expect(
          message,
          'A project with code "ACME" already exists. Choose a different '
          'code.',
        );
        expect(message, isNot(contains('SqliteException')));
        expect(message, isNot(contains('INSERT INTO')));
      },
    );

    test('edit --rate inherit clears the project rate', () async {
      final s = await _seed(tmp);
      final db = _open(s.file);
      await db.updateProject(
        id: s.projectA,
        clientId: s.clientId,
        code: 'ACME',
        title: 'Acme Website',
        rate: 200,
      );
      await db.close();
      expect(
        await runTimedartCli([
          'project', 'edit', 'ACME', '--rate', 'inherit', '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db2 = _open(s.file);
      addTearDown(db2.close);
      expect((await db2.getProject(s.projectA)).rate, isNull);
    });

    test('edit can reassign the client', () async {
      final s = await _seed(tmp);
      final db = _open(s.file);
      final other = await db.addClient(name: 'Other Co', defaultRate: 80);
      await db.close();
      expect(
        await runTimedartCli([
          'project', 'edit', 'ACME', '--client', 'Other Co', //
          '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db2 = _open(s.file);
      addTearDown(db2.close);
      expect((await db2.getProject(s.projectA)).clientId, other);
    });
  });

  group('task add / edit', () {
    test('add under a project', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'task', 'add', '--project', 'ACME', '--title', 'QA', //
          '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      final titles = (await db.tasksForProject(s.projectA)).map((t) => t.title);
      expect(titles, containsAll(['Design', 'QA']));
    });

    test('edit renames a task resolved by unique name', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'task', 'edit', 'Design', '--title', 'UX Design', '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      expect((await db.tasksForProject(s.projectA)).single.title, 'UX Design');
    });
  });

  group('delete + cascade + --force guard', () {
    Future<void> addEntry(File file, String projectId, String taskId) async {
      final db = _open(file);
      await db.addEntry(
        projectId: projectId,
        taskId: taskId,
        startedAt: DateTime(2026),
        endedAt: DateTime(2026).add(const Duration(minutes: 10)),
        seconds: 600,
      );
      await db.close();
    }

    test('project delete without --force refuses (10) and changes nothing',
        () async {
      final s = await _seed(tmp);
      await addEntry(s.file, s.projectA, s.taskDesign);
      expect(
        await runTimedartCli([
          'project', 'delete', 'ACME', '--db', s.file.path,
        ]),
        CliExit.confirmationRequired,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      expect((await db.getProject(s.projectA)).deletedAt, isNull);
    });

    test('project delete --force cascades tasks + entries', () async {
      final s = await _seed(tmp);
      await addEntry(s.file, s.projectA, s.taskDesign);
      expect(
        await runTimedartCli([
          'project', 'delete', 'ACME', '--force', '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      final live = <int>[
        (await (db.select(db.projects)..where((p) => p.deletedAt.isNull())).get()).length,
        (await (db.select(db.tasks)..where((t) => t.deletedAt.isNull())).get()).length,
        (await (db.select(db.timeEntries)..where((e) => e.deletedAt.isNull())).get()).length,
      ];
      expect(live, [0, 0, 0]);
    });

    test('client delete --force cascades everything', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'client', 'delete', 'Acme Co', '--force', '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      expect(
        await (db.select(db.clients)..where((c) => c.deletedAt.isNull())).get(),
        isEmpty,
      );
    });

    test('task delete --force removes it and its entries', () async {
      final s = await _seed(tmp);
      await addEntry(s.file, s.projectA, s.taskDesign);
      expect(
        await runTimedartCli([
          'task', 'delete', 'Design', '--force', '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _open(s.file);
      addTearDown(db.close);
      expect(await db.tasksForProject(s.projectA), isEmpty);
    });

    test('delete refuses (8) when a timer is bound to the target', () async {
      final s = await _seed(tmp);
      final db = _open(s.file);
      await TimerStore(db).start(s.projectA, s.taskDesign, now: DateTime.now());
      await db.close();
      expect(
        await runTimedartCli([
          'task', 'delete', 'Design', '--force', '--db', s.file.path,
        ]),
        CliExit.timerAlreadyRunning,
      );
    });
  });
}
