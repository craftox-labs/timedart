import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/cli/crud_result.dart';
import 'package:timedart/cli/exit_codes.dart';
import 'package:timedart/cli/list_result.dart';
import 'package:timedart/cli/log_result.dart';
import 'package:timedart/cli/output_formatter.dart';
import 'package:timedart/cli/report_result.dart';
import 'package:timedart/cli/timer_status_result.dart';
import 'package:timedart/cli/timer_stop_result.dart';
import 'package:timedart/cli/version.dart';

// Pins the CLI's public JSON contract so docs/cli/agent-guide.md cannot silently
// drift from the formatter. If a shape must change, update the guide too.

Map<String, Object?> _obj(String json) =>
    jsonDecode(json) as Map<String, Object?>;
List<Object?> _arr(String json) => jsonDecode(json) as List<Object?>;

void main() {
  test('timer status JSON keys', () {
    final keys = _obj(formatTimerStatusJson(TimerStatusResult.idle)).keys.toSet();
    expect(keys, {
      'status',
      'running',
      'elapsedSeconds',
      'project',
      'task',
      'description',
      'startedAt',
    });
  });

  test('timer stop JSON keys (recorded)', () {
    const r = TimerStopResult(
      recorded: true,
      seconds: 60,
      projectId: 'p',
      taskId: 't',
    );
    final top = _obj(formatTimerStopJson(r));
    expect(top.keys.toSet(), {'stopped', 'recorded', 'entry'});
    expect((top['entry'] as Map).keys.toSet(), {
      'seconds',
      'project',
      'task',
      'description',
      'startedAt',
      'endedAt',
    });
  });

  test('list projects JSON keys', () {
    const item = ProjectListItem(
      id: 'p',
      code: 'C',
      title: 'T',
      clientId: 'c',
    );
    final row = _arr(formatProjects([item], json: true)).single as Map;
    expect(row.keys.toSet(), {
      'id',
      'code',
      'title',
      'clientId',
      'clientName',
      'rate',
      'archived',
    });
  });

  test('list tasks JSON keys', () {
    const item = TaskListItem(id: 't', title: 'T', projectId: 'p');
    final row = _arr(formatTasks([item], json: true)).single as Map;
    expect(row.keys.toSet(), {
      'id',
      'title',
      'projectId',
      'projectCode',
      'projectTitle',
      'rate',
    });
  });

  test('list clients JSON keys', () {
    const item = ClientListItem(id: 'c', name: 'N', defaultRate: 100);
    final row = _arr(formatClients([item], json: true)).single as Map;
    expect(row.keys.toSet(), {
      'id',
      'name',
      'defaultRate',
      'contactName',
      'email',
      'phone',
      'address',
      'abn',
      'archived',
    });
  });

  test('client create/edit result JSON shape', () {
    const item = ClientListItem(id: 'c', name: 'N', defaultRate: 100);
    final top = _obj(formatClient(item, action: 'Created', json: true));
    expect(top.keys.toSet(), {'action', 'client'});
    expect(top['action'], 'created');
    expect((top['client'] as Map)['id'], 'c');
  });

  test('project create/edit result JSON shape', () {
    const item = ProjectListItem(id: 'p', code: 'C', title: 'T', clientId: 'c');
    final top = _obj(formatProject(item, action: 'Updated', json: true));
    expect(top.keys.toSet(), {'action', 'project'});
    expect(top['action'], 'updated');
  });

  test('task create/edit result JSON shape', () {
    const item = TaskListItem(id: 't', title: 'T', projectId: 'p');
    final top = _obj(formatTask(item, action: 'Created', json: true));
    expect(top.keys.toSet(), {'action', 'task'});
  });

  test('list entries JSON keys', () {
    final item = EntryListItem(
      id: 'e',
      projectId: 'p',
      seconds: 60,
      startedAt: DateTime.utc(2026),
      endedAt: DateTime.utc(2026),
    );
    final row = _arr(formatEntries([item], json: true)).single as Map;
    expect(row.keys.toSet(), {
      'id',
      'projectId',
      'projectCode',
      'projectTitle',
      'taskId',
      'taskTitle',
      'description',
      'seconds',
      'startedAt',
      'endedAt',
    });
  });

  test('entry edit result JSON shape', () {
    final item = EntryListItem(
      id: 'e',
      projectId: 'p',
      seconds: 60,
      startedAt: DateTime.utc(2026),
      endedAt: DateTime.utc(2026),
    );
    final top = _obj(formatEntry(item, action: 'Updated', json: true));
    expect(top.keys.toSet(), {'action', 'entry'});
    expect(top['action'], 'updated');
    expect((top['entry'] as Map).keys.toSet(), {
      'id',
      'projectId',
      'projectCode',
      'projectTitle',
      'taskId',
      'taskTitle',
      'description',
      'seconds',
      'startedAt',
      'endedAt',
    });
  });

  test('entry delete result JSON shape (shares the delete shape)', () {
    const outcome = DeleteOutcome(
      kind: 'entry',
      id: 'e',
      label: '10m on ACME / Design',
      impact: DeleteImpact(),
      deleted: false,
    );
    final top = _obj(formatDelete(outcome, json: true));
    expect(top.keys.toSet(), {'deleted', 'kind', 'id', 'label', 'impact'});
    expect(top['kind'], 'entry');
    expect((top['impact'] as Map)['total'], 0);
  });

  test('delete result JSON shape (refused + confirmed share it)', () {
    const outcome = DeleteOutcome(
      kind: 'project',
      id: 'p',
      label: 'C T',
      impact: DeleteImpact(tasks: 2, entries: 5),
      deleted: false,
    );
    final top = _obj(formatDelete(outcome, json: true));
    expect(top.keys.toSet(), {'deleted', 'kind', 'id', 'label', 'impact'});
    expect((top['impact'] as Map).keys.toSet(), {
      'projects',
      'tasks',
      'entries',
      'total',
    });
    expect((top['impact'] as Map)['total'], 7);
  });

  test('log JSON keys', () {
    final r = LogResult(
      seconds: 60,
      projectId: 'p',
      taskId: 't',
      startedAt: DateTime.utc(2026),
      endedAt: DateTime.utc(2026),
    );
    final top = _obj(formatLog(r, json: true));
    expect(top.keys.toSet(), {'logged', 'entry'});
    expect((top['entry'] as Map).keys.toSet(), {
      'seconds',
      'project',
      'task',
      'description',
      'startedAt',
      'endedAt',
    });
  });

  test('report JSON keys', () {
    const row = ReportRow(
      group: 'ACME Acme Website',
      groupId: 'p1',
      seconds: 3600,
      entries: 2,
      amount: 100.0,
    );
    final arr = _arr(formatReport([row], json: true));
    final rowJson = arr.single as Map;
    expect(rowJson.keys.toSet(), {
      'group',
      'groupId',
      'seconds',
      'entries',
      'amount',
    });
    expect(rowJson['group'], 'ACME Acme Website');
    expect(rowJson['groupId'], 'p1');
    expect(rowJson['seconds'], 3600);
    expect(rowJson['entries'], 2);
    expect(rowJson['amount'], 100.0);
  });

  test('report JSON: amount/groupId are null when they don\'t apply', () {
    const row = ReportRow(group: '2026-07-13', seconds: 60, entries: 1);
    final rowJson = _arr(formatReport([row], json: true)).single as Map;
    expect(rowJson['groupId'], isNull);
    expect(rowJson['amount'], isNull);
  });

  test('version line states CLI version, schema version and sync-awareness', () {
    final v = versionLine();
    expect(v, contains(kCliVersion));
    expect(v, contains('schema v20'));
    expect(v, contains('sync:'));
  });

  // ── Dispatcher error envelope (issue #286) ───────────────────────────────

  test('error JSON shape for an unknown-entity failure (code 5)', () {
    final text = formatCliError(
      code: CliExit.unknownEntity,
      message: 'No live project matches "Ghost".',
      json: true,
    );
    final top = _obj(text);
    expect(top.keys.toSet(), {'error'});
    final error = top['error'] as Map;
    expect(error, {
      'code': 5,
      'name': 'unknownEntity',
      'message': 'No live project matches "Ghost".',
    });
  });

  test('error JSON shape for a usage failure (code 2)', () {
    final text = formatCliError(
      code: CliExit.usage,
      message: 'Could not find a command named "bogus".',
      json: true,
    );
    final error = _obj(text)['error'] as Map;
    expect(error, {
      'code': 2,
      'name': 'usage',
      'message': 'Could not find a command named "bogus".',
    });
  });

  test('non-JSON error mode is unchanged plain text', () {
    final text = formatCliError(
      code: CliExit.unknownEntity,
      message: 'No live project matches "Ghost".',
      json: false,
    );
    expect(text, 'error: No live project matches "Ghost".');
  });

  test('CliExit.nameFor covers every defined code', () {
    expect(CliExit.nameFor(CliExit.success), 'success');
    expect(CliExit.nameFor(CliExit.failure), 'failure');
    expect(CliExit.nameFor(CliExit.usage), 'usage');
    expect(CliExit.nameFor(CliExit.schemaMismatch), 'schemaMismatch');
    expect(CliExit.nameFor(CliExit.dbNotFound), 'dbNotFound');
    expect(CliExit.nameFor(CliExit.unknownEntity), 'unknownEntity');
    expect(CliExit.nameFor(CliExit.ambiguousEntity), 'ambiguousEntity');
    expect(CliExit.nameFor(CliExit.noTimerRunning), 'noTimerRunning');
    expect(CliExit.nameFor(CliExit.timerAlreadyRunning), 'timerAlreadyRunning');
    expect(CliExit.nameFor(CliExit.timerAlreadyPaused), 'timerAlreadyPaused');
    expect(
      CliExit.nameFor(CliExit.confirmationRequired),
      'confirmationRequired',
    );
    expect(
      CliExit.nameFor(CliExit.constraintViolation),
      'constraintViolation',
    );
    expect(CliExit.nameFor(999), 'unknown');
  });
}
