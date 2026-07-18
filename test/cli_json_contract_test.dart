import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/cli/crud_result.dart';
import 'package:timedart/cli/list_result.dart';
import 'package:timedart/cli/log_result.dart';
import 'package:timedart/cli/output_formatter.dart';
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

  test('version line states CLI version, schema version and sync-awareness', () {
    final v = versionLine();
    expect(v, contains(kCliVersion));
    expect(v, contains('schema v16'));
    expect(v, contains('sync:'));
  });
}
