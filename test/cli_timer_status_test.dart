import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/cli/cli.dart';
import 'package:timedart/cli/db_open.dart';
import 'package:timedart/cli/exit_codes.dart';
import 'package:timedart/cli/output_formatter.dart';
import 'package:timedart/cli/timer_status.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/tracker/timer_store.dart';

// CLI smoke for `timer status` (issue #271): drive real lib/data against a temp
// DB opened through the seam, assert the rendered output for an active timer
// and for none, and check the dispatcher's exit-code contract.

/// Seed a temp DB (at schema v16) with a client/project/task and, optionally, a
/// running timer started at [startedAt]. Returns the file.
Future<File> _seedDb(
  Directory tmp, {
  DateTime? startedAt,
  String description = 'writing docs',
}) async {
  final file = File('${tmp.path}/timedart.sqlite');
  final db = AppDatabase(NativeDatabase(file));
  final clientId = await db.addClient(name: 'Acme', defaultRate: 100);
  final projectId = await db.addProject(
    clientId: clientId,
    code: 'ACME',
    title: 'Acme Website',
  );
  final taskId = await db.addTask(projectId: projectId, title: 'Design');
  if (startedAt != null) {
    await TimerStore(
      db,
    ).start(projectId, taskId, now: startedAt, description: description);
  }
  await db.close();
  return file;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('timedart_cli_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('active timer: status reports project/task/elapsed', () async {
    final start = DateTime.now().subtract(const Duration(seconds: 65));
    final file = await _seedDb(tmp, startedAt: start);

    final db = openTimedartDb(file.path);
    addTearDown(db.close);
    final result = await queryTimerStatus(
      db,
      now: start.add(const Duration(seconds: 65)),
    );

    expect(result.hasTimer, isTrue);
    expect(result.running, isTrue);
    expect(result.elapsedSeconds, 65);
    expect(result.projectCode, 'ACME');
    expect(result.projectTitle, 'Acme Website');
    expect(result.taskTitle, 'Design');
    expect(result.description, 'writing docs');

    // The rendered JSON the CLI would print is well-formed and correct.
    final json =
        jsonDecode(formatTimerStatusJson(result)) as Map<String, Object?>;
    expect(json['status'], 'running');
    expect(json['elapsedSeconds'], 65);
    expect((json['project'] as Map)['code'], 'ACME');

    // Human output too.
    final human = formatTimerStatusHuman(result);
    expect(human, contains('ACME Acme Website'));
    expect(human, contains('Elapsed: 1m 5s'));
  });

  test('no timer: status reports idle', () async {
    final file = await _seedDb(tmp); // no running timer

    final db = openTimedartDb(file.path);
    addTearDown(db.close);
    final result = await queryTimerStatus(db, now: DateTime.now());

    expect(result.hasTimer, isFalse);
    expect(formatTimerStatusHuman(result), 'No timer running.');
    expect(
      jsonDecode(formatTimerStatusJson(result)),
      containsPair('status', 'idle'),
    );
  });

  group('dispatcher exit codes (runTimedartCli)', () {
    test('success returns 0 for an active timer via --db', () async {
      final file = await _seedDb(
        tmp,
        startedAt: DateTime.now().subtract(const Duration(seconds: 5)),
      );
      final code = await runTimedartCli([
        'timer',
        'status',
        '--json',
        '--db',
        file.path,
      ]);
      expect(code, CliExit.success);
    });

    test('missing DB returns dbNotFound', () async {
      final code = await runTimedartCli([
        'timer',
        'status',
        '--db',
        '${tmp.path}/nope.sqlite',
      ]);
      expect(code, CliExit.dbNotFound);
    });

    test('schema mismatch returns schemaMismatch', () async {
      final file = File('${tmp.path}/old.sqlite');
      final db = AppDatabase(NativeDatabase(file));
      await db.customStatement('SELECT 1');
      await db.customStatement('PRAGMA user_version = 15');
      await db.close();

      final code = await runTimedartCli([
        'timer',
        'status',
        '--db',
        file.path,
      ]);
      expect(code, CliExit.schemaMismatch);
    });

    test('unknown verb returns usage', () async {
      final code = await runTimedartCli(['bogus']);
      expect(code, CliExit.usage);
    });
  });
}
