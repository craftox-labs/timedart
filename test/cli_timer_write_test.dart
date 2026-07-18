import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/cli/cli.dart';
import 'package:timedart/cli/entity_resolver.dart';
import 'package:timedart/cli/exit_codes.dart';
import 'package:timedart/cli/timer_status.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/tracker/timer_store.dart';

// CLI slice 2 (issue #272): timer write verbs. Round-trip + name resolution +
// error-class exit codes, driving real lib/data against a temp-file DB.

class _Seed {
  final File file;
  final String projectId;
  final String taskId;
  _Seed(this.file, this.projectId, this.taskId);
}

/// Create a temp DB with one client/project/task. Returns the ids.
Future<_Seed> _seed(Directory tmp) async {
  final file = File('${tmp.path}/timedart.sqlite');
  final db = AppDatabase(NativeDatabase(file));
  final clientId = await db.addClient(name: 'Acme', defaultRate: 100);
  final projectId = await db.addProject(
    clientId: clientId,
    code: 'ACME',
    title: 'Acme Website',
  );
  final taskId = await db.addTask(projectId: projectId, title: 'Design');
  await db.close();
  return _Seed(file, projectId, taskId);
}

/// Open a plain (non-CLI) AppDatabase over the file to inspect state.
AppDatabase _inspect(File file) => AppDatabase(NativeDatabase(file));

/// Backdate the live active-timer's run start so elapsed accrues without
/// waiting on the wall clock (equivalent to time passing).
Future<void> _backdate(File file, Duration by) async {
  final db = _inspect(file);
  final row = (await db.activeTimer())!;
  await db.saveActiveTimer(
    row.toCompanion(true).copyWith(
      runningSince: Value(row.runningSince!.subtract(by)),
    ),
  );
  await db.close();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('timedart_cli_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('start → status → stop round trip', () {
    test('start writes active_timer; stop records a TimeEntry and clears',
        () async {
      final s = await _seed(tmp);

      // start
      expect(
        await runTimedartCli([
          'timer', 'start', //
          '--project', 'ACME', '--task', 'Design', //
          '--description', 'hero', '--db', s.file.path,
        ]),
        CliExit.success,
      );

      var db = _inspect(s.file);
      final active = await db.activeTimer();
      expect(active, isNotNull);
      expect(active!.projectId, s.projectId);
      expect(active.taskId, s.taskId);
      expect(active.runningSince, isNotNull); // running
      await db.close();

      // simulate two minutes of tracking, then stop
      await _backdate(s.file, const Duration(minutes: 2));
      expect(
        await runTimedartCli(['timer', 'stop', '--db', s.file.path]),
        CliExit.success,
      );

      db = _inspect(s.file);
      expect(await db.activeTimer(), isNull, reason: 'timer cleared');
      final entries = await (db.select(
        db.timeEntries,
      )..where((t) => t.deletedAt.isNull())).get();
      expect(entries, hasLength(1));
      expect(entries.single.projectId, s.projectId);
      expect(entries.single.taskId, s.taskId);
      expect(entries.single.seconds, greaterThanOrEqualTo(120));
      expect(entries.single.description, 'hero');
      await db.close();
    });
  });

  group('name resolution', () {
    test('resolves by exact UUID, code, and title; scoped task', () async {
      final s = await _seed(tmp);
      final db = _inspect(s.file);
      addTearDown(db.close);

      expect((await resolveProject(db, s.projectId)).id, s.projectId);
      expect((await resolveProject(db, 'ACME')).id, s.projectId); // code
      expect((await resolveProject(db, 'Acme Website')).id, s.projectId);
      expect((await resolveTask(db, s.projectId, 'Design')).id, s.taskId);
      expect((await resolveTask(db, s.projectId, s.taskId)).id, s.taskId);
    });

    test('unknown name throws unknownEntity', () async {
      final s = await _seed(tmp);
      final db = _inspect(s.file);
      addTearDown(db.close);
      expect(
        () => resolveProject(db, 'Nope'),
        throwsA(
          isA<CliException>().having((e) => e.exitCode, 'exit', CliExit.unknownEntity),
        ),
      );
    });

    test('ambiguous title throws ambiguousEntity', () async {
      final file = File('${tmp.path}/timedart.sqlite');
      final db = AppDatabase(NativeDatabase(file));
      final c = await db.addClient(name: 'Acme', defaultRate: 100);
      await db.addProject(clientId: c, code: 'A1', title: 'Website');
      await db.addProject(clientId: c, code: 'A2', title: 'Website');
      addTearDown(db.close);
      expect(
        () => resolveProject(db, 'Website'),
        throwsA(
          isA<CliException>().having(
            (e) => e.exitCode,
            'exit',
            CliExit.ambiguousEntity,
          ),
        ),
      );
    });

    test('start surfaces unknown project as unknownEntity exit', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'timer', 'start', '--project', 'Ghost', '--task', 'Design', //
          '--db', s.file.path,
        ]),
        CliExit.unknownEntity,
      );
    });
  });

  group('error-class exit codes', () {
    test('start while a timer is active → timerAlreadyRunning', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'timer', 'start', '--project', 'ACME', '--task', 'Design', //
          '--db', s.file.path,
        ]),
        CliExit.success,
      );
      expect(
        await runTimedartCli([
          'timer', 'start', '--project', 'ACME', '--task', 'Design', //
          '--db', s.file.path,
        ]),
        CliExit.timerAlreadyRunning,
      );
    });

    test('stop while none running → noTimerRunning', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli(['timer', 'stop', '--db', s.file.path]),
        CliExit.noTimerRunning,
      );
    });

    test('start with no --project → usage', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli(['timer', 'start', '--db', s.file.path]),
        CliExit.usage,
      );
    });

    test('start with no --task → usage', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'timer', 'start', '--project', 'ACME', '--db', s.file.path,
        ]),
        CliExit.usage,
      );
    });

    test('start --project P --task T → running with task bound', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'timer', 'start', '--project', 'ACME', '--task', 'Design', //
          '--db', s.file.path,
        ]),
        CliExit.success,
      );
      final db = _inspect(s.file);
      addTearDown(db.close);
      final active = await db.activeTimer();
      expect(active, isNotNull);
      expect(active!.taskId, s.taskId);
      expect(active.runningSince, isNotNull);
    });
  });

  group('pause / resume', () {
    Future<void> startPast(_Seed s) async {
      // Start via TimerStore in the past so a real elapsed accrues.
      final db = _inspect(s.file);
      await TimerStore(db).start(
        s.projectId,
        s.taskId,
        now: DateTime.now().subtract(const Duration(minutes: 1)),
        description: 'work',
      );
      await db.close();
    }

    test('pause freezes then resume continues', () async {
      final s = await _seed(tmp);
      await startPast(s);

      expect(
        await runTimedartCli(['timer', 'pause', '--db', s.file.path]),
        CliExit.success,
      );
      var db = _inspect(s.file);
      var row = (await db.activeTimer())!;
      expect(row.runningSince, isNull, reason: 'paused');
      expect(row.accumulatedSeconds, greaterThanOrEqualTo(60));
      await db.close();

      expect(
        await runTimedartCli(['timer', 'resume', '--db', s.file.path]),
        CliExit.success,
      );
      db = _inspect(s.file);
      row = (await db.activeTimer())!;
      expect(row.runningSince, isNotNull, reason: 'running again');
      await db.close();
    });

    test('pause while already paused → timerAlreadyPaused', () async {
      final s = await _seed(tmp);
      await startPast(s);
      await runTimedartCli(['timer', 'pause', '--db', s.file.path]);
      expect(
        await runTimedartCli(['timer', 'pause', '--db', s.file.path]),
        CliExit.timerAlreadyPaused,
      );
    });

    test('resume while running → timerAlreadyRunning', () async {
      final s = await _seed(tmp);
      await startPast(s);
      expect(
        await runTimedartCli(['timer', 'resume', '--db', s.file.path]),
        CliExit.timerAlreadyRunning,
      );
    });

    test('resume with no timer → noTimerRunning', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli(['timer', 'resume', '--db', s.file.path]),
        CliExit.noTimerRunning,
      );
    });
  });

  group('discard', () {
    test('discard with none running → noTimerRunning', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli(['timer', 'discard', '--db', s.file.path]),
        CliExit.noTimerRunning,
      );
    });

    test('discard clears the timer and records NO entry', () async {
      final s = await _seed(tmp);
      // Start in the past so a real elapsed span exists that stop WOULD record.
      final db0 = _inspect(s.file);
      await TimerStore(db0).start(
        s.projectId,
        s.taskId,
        now: DateTime.now().subtract(const Duration(minutes: 3)),
        description: 'mistake',
      );
      await db0.close();

      expect(
        await runTimedartCli(['timer', 'discard', '--db', s.file.path]),
        CliExit.success,
      );

      final db = _inspect(s.file);
      addTearDown(db.close);
      expect(await db.activeTimer(), isNull, reason: 'timer cleared');
      final entries = await (db.select(
        db.timeEntries,
      )..where((t) => t.deletedAt.isNull())).get();
      expect(entries, isEmpty, reason: 'discard records nothing');
    });

    test('discard also abandons a paused timer', () async {
      final s = await _seed(tmp);
      final db0 = _inspect(s.file);
      await TimerStore(db0).start(
        s.projectId,
        s.taskId,
        now: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      await db0.close();
      await runTimedartCli(['timer', 'pause', '--db', s.file.path]);

      expect(
        await runTimedartCli(['timer', 'discard', '--db', s.file.path]),
        CliExit.success,
      );
      final db = _inspect(s.file);
      addTearDown(db.close);
      expect(await db.activeTimer(), isNull);
      expect(
        await (db.select(db.timeEntries)
              ..where((t) => t.deletedAt.isNull()))
            .get(),
        isEmpty,
      );
    });
  });

  group('edit running timer', () {
    Future<void> startPast(_Seed s, {String? description}) async {
      final db = _inspect(s.file);
      await TimerStore(db).start(
        s.projectId,
        s.taskId,
        now: DateTime.now().subtract(const Duration(minutes: 2)),
        description: description,
      );
      await db.close();
    }

    test('edit description with none running → noTimerRunning', () async {
      final s = await _seed(tmp);
      expect(
        await runTimedartCli([
          'timer', 'edit', '-d', 'x', '--db', s.file.path,
        ]),
        CliExit.noTimerRunning,
      );
    });

    test('edit with nothing to change → usage', () async {
      final s = await _seed(tmp);
      await startPast(s);
      expect(
        await runTimedartCli(['timer', 'edit', '--db', s.file.path]),
        CliExit.usage,
      );
    });

    test('changed description is visible to a later status; no entry', () async {
      final s = await _seed(tmp);
      await startPast(s, description: 'first');

      expect(
        await runTimedartCli([
          'timer', 'edit', '-d', 'second take', '--db', s.file.path,
        ]),
        CliExit.success,
      );

      final db = _inspect(s.file);
      addTearDown(db.close);
      final status = await queryTimerStatus(db, now: DateTime.now());
      expect(status.description, 'second take');
      expect(status.running, isTrue, reason: 'still running');
      expect(status.elapsedSeconds, greaterThanOrEqualTo(120),
          reason: 'elapsed not reset by the edit');
      expect(
        await (db.select(db.timeEntries)
              ..where((t) => t.deletedAt.isNull()))
            .get(),
        isEmpty,
        reason: 'editing records nothing',
      );
    });

    test('empty -d clears the note', () async {
      final s = await _seed(tmp);
      await startPast(s, description: 'note');
      expect(
        await runTimedartCli(['timer', 'edit', '-d', '', '--db', s.file.path]),
        CliExit.success,
      );
      final db = _inspect(s.file);
      addTearDown(db.close);
      expect((await queryTimerStatus(db, now: DateTime.now())).description,
          isNull);
    });

    test('rebind to another task moves project+task, keeps elapsed', () async {
      final s = await _seed(tmp);
      // A second project/task to rebind onto.
      final setup = _inspect(s.file);
      final clientId = await setup.addClient(name: 'Beta', defaultRate: 100);
      final proj2 = await setup.addProject(
        clientId: clientId,
        code: 'BETA',
        title: 'Beta Site',
      );
      final task2 = await setup.addTask(projectId: proj2, title: 'Research');
      await setup.close();

      await startPast(s, description: 'keep me');

      expect(
        await runTimedartCli([
          'timer', 'edit', '-t', 'Research', '-p', 'BETA', //
          '--db', s.file.path,
        ]),
        CliExit.success,
      );

      final db = _inspect(s.file);
      addTearDown(db.close);
      final status = await queryTimerStatus(db, now: DateTime.now());
      expect(status.projectId, proj2);
      expect(status.taskId, task2);
      expect(status.description, 'keep me', reason: 'note untouched by rebind');
      expect(status.running, isTrue);
      expect(status.elapsedSeconds, greaterThanOrEqualTo(120),
          reason: 'rebind preserves tracked time');
      expect(
        await (db.select(db.timeEntries)
              ..where((t) => t.deletedAt.isNull()))
            .get(),
        isEmpty,
      );
    });

    test('--project without --task → usage', () async {
      final s = await _seed(tmp);
      await startPast(s);
      expect(
        await runTimedartCli([
          'timer', 'edit', '-p', 'ACME', '--db', s.file.path,
        ]),
        CliExit.usage,
      );
    });
  });
}
