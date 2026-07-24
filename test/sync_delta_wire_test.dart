import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/active_timer_wire.dart';
import 'package:timedart/data/sync/delta/merge.dart';
import 'package:timedart/data/sync/delta/project_wire.dart';
import 'package:timedart/data/sync/delta/task_wire.dart';
import 'package:timedart/data/sync/delta/time_entry_wire.dart';

// Phase 5b delta-sync (#294): the Postgres wire codecs for the three tables 5b
// adds (projects/tasks/time_entries) + their per-table LWW convenience — pure,
// no database, no network. Mirrors the client codec tests in
// sync_delta_merge_test.dart.

void main() {
  final t0 = DateTime.fromMillisecondsSinceEpoch(1000);
  final t1 = DateTime.fromMillisecondsSinceEpoch(2000);

  group('project wire codec', () {
    final project = Project(
      id: 'p1',
      orgId: 'org1',
      clientId: 'c1',
      code: 'P1',
      title: 'Proj',
      rate: 90.0,
      status: 'active',
      archivedAt: null,
      createdAt: t0,
      updatedAt: t1,
      deletedAt: null,
    );

    test('projectToWire → snake_case keys, epoch-ms, plain rate, no server_seq',
        () {
      expect(projectToWire(project), {
        'id': 'p1',
        'org_id': 'org1',
        'client_id': 'c1',
        'code': 'P1',
        'title': 'Proj',
        'rate': 90.0,
        'status': 'active',
        'archived_at': null,
        'created_at': 1000,
        'updated_at': 2000,
        'deleted_at': null,
      });
      expect(projectToWire(project).containsKey('server_seq'), isFalse);
    });

    test('fromWire round-trips, toCompanion keeps remote updatedAt verbatim',
        () {
      final r =
          RemoteProject.fromWire({...projectToWire(project), 'server_seq': 7});
      expect(r.id, 'p1');
      expect(r.clientId, 'c1');
      expect(r.rate, 90.0);
      expect(r.status, 'active');
      expect(r.createdAt, t0);
      expect(r.serverSeq, 7);
      expect(r.toCompanion().updatedAt.value, t1);
    });

    test('a tombstone wire row decodes with deletedAt set', () {
      final r = RemoteProject.fromWire({
        ...projectToWire(project),
        'deleted_at': 3000,
        'updated_at': 3000,
        'server_seq': 1,
      });
      expect(r.deletedAt, DateTime.fromMillisecondsSinceEpoch(3000));
    });
  });

  group('task wire codec (no archived_at column)', () {
    final task = Task(
      id: 't1',
      orgId: 'org1',
      projectId: 'p1',
      title: 'Task',
      rate: null,
      status: 'active',
      createdAt: t0,
      updatedAt: t1,
      deletedAt: null,
    );

    test('taskToWire → expected shape, no archived_at, no server_seq', () {
      final wire = taskToWire(task);
      expect(wire, {
        'id': 't1',
        'org_id': 'org1',
        'project_id': 'p1',
        'title': 'Task',
        'rate': null,
        'status': 'active',
        'created_at': 1000,
        'updated_at': 2000,
        'deleted_at': null,
      });
      expect(wire.containsKey('archived_at'), isFalse);
      expect(wire.containsKey('server_seq'), isFalse);
    });

    test('fromWire round-trips + toCompanion verbatim updatedAt', () {
      final r = RemoteTask.fromWire({...taskToWire(task), 'server_seq': 3});
      expect(r.projectId, 'p1');
      expect(r.rate, isNull);
      expect(r.createdAt, t0);
      expect(r.serverSeq, 3);
      expect(r.toCompanion().updatedAt.value, t1);
    });
  });

  group('time entry wire codec', () {
    final entry = TimeEntry(
      id: 'e1',
      orgId: 'org1',
      projectId: 'p1',
      taskId: 't1',
      description: 'note',
      startedAt: t0,
      endedAt: t1,
      seconds: 90,
      createdAt: t0,
      updatedAt: t1,
      deletedAt: null,
    );

    test('timeEntryToWire → epoch-ms times, plain seconds, no server_seq', () {
      expect(timeEntryToWire(entry), {
        'id': 'e1',
        'org_id': 'org1',
        'project_id': 'p1',
        'task_id': 't1',
        'description': 'note',
        'started_at': 1000,
        'ended_at': 2000,
        'seconds': 90,
        'created_at': 1000,
        'updated_at': 2000,
        'deleted_at': null,
      });
      expect(timeEntryToWire(entry).containsKey('server_seq'), isFalse);
    });

    test('fromWire round-trips (nullable taskId, non-null times/seconds)', () {
      final r = RemoteTimeEntry.fromWire({
        ...timeEntryToWire(entry),
        'task_id': null,
        'server_seq': 9,
      });
      expect(r.taskId, isNull);
      expect(r.startedAt, t0);
      expect(r.endedAt, t1);
      expect(r.seconds, 90);
      expect(r.serverSeq, 9);
      expect(r.toCompanion().updatedAt.value, t1);
    });
  });

  group('active timer wire codec (#300)', () {
    final timer = ActiveTimer(
      id: 'a1',
      orgId: 'org1',
      projectId: 'p1',
      taskId: 't1',
      description: 'note',
      startedAt: t0,
      accumulatedSeconds: 42,
      runningSince: t1,
      createdAt: t0,
      updatedAt: t1,
      deletedAt: null,
    );

    test('activeTimerToWire → snake_case, epoch-ms, no server_seq', () {
      expect(activeTimerToWire(timer), {
        'id': 'a1',
        'org_id': 'org1',
        'project_id': 'p1',
        'task_id': 't1',
        'description': 'note',
        'started_at': 1000,
        'accumulated_seconds': 42,
        'running_since': 2000,
        'created_at': 1000,
        'updated_at': 2000,
        'deleted_at': null,
      });
      expect(activeTimerToWire(timer).containsKey('server_seq'), isFalse);
    });

    test('fromWire round-trips; paused (running_since null) + unbound decode', () {
      final r = RemoteActiveTimer.fromWire({
        ...activeTimerToWire(timer),
        'project_id': null,
        'task_id': null,
        'running_since': null,
        'server_seq': 5,
      });
      expect(r.projectId, isNull); // unbound timer syncs fine
      expect(r.taskId, isNull);
      expect(r.runningSince, isNull); // paused
      expect(r.accumulatedSeconds, 42);
      expect(r.startedAt, t0);
      expect(r.serverSeq, 5);
      expect(r.toCompanion().updatedAt.value, t1); // remote clock verbatim
    });

    test('a tombstone (finished/discarded timer) decodes with deletedAt', () {
      final r = RemoteActiveTimer.fromWire({
        ...activeTimerToWire(timer),
        'deleted_at': 3000,
        'updated_at': 3000,
        'server_seq': 1,
      });
      expect(r.deletedAt, DateTime.fromMillisecondsSinceEpoch(3000));
    });

    test('accumulated_seconds missing/null defaults to 0', () {
      final r = RemoteActiveTimer.fromWire({
        ...activeTimerToWire(timer),
        'accumulated_seconds': null,
        'server_seq': 1,
      });
      expect(r.accumulatedSeconds, 0);
    });

    test('decideActiveTimerMergeFor: newer remote applies, older skips', () {
      ActiveTimer local(DateTime u) => ActiveTimer(
            id: 'a1',
            orgId: 'org1',
            projectId: 'p1',
            taskId: 't1',
            description: 'note',
            startedAt: t0,
            accumulatedSeconds: 42,
            runningSince: t1,
            createdAt: t0,
            updatedAt: u,
            deletedAt: null,
          );
      RemoteActiveTimer rt(DateTime u) => RemoteActiveTimer(
            id: 'a1',
            orgId: 'org1',
            projectId: 'p1',
            taskId: 't1',
            description: 'note',
            startedAt: t0,
            accumulatedSeconds: 42,
            runningSince: t1,
            createdAt: t0,
            updatedAt: u,
            deletedAt: null,
            serverSeq: 1,
          );
      expect(decideActiveTimerMergeFor(local(t0), rt(t1)), MergeAction.apply);
      expect(decideActiveTimerMergeFor(local(t1), rt(t0)), MergeAction.skip);
      // Two devices, DIFFERENT work → different ids → no local match → apply
      // (the row coexists rather than clobbering the other's timer).
      expect(decideActiveTimerMergeFor(null, rt(t0)), MergeAction.apply);
    });
  });

  group('per-table LWW conveniences delegate to the one rule', () {
    test('decideProjectMergeFor: newer remote applies, older skips', () {
      Project local(DateTime u) => Project(
            id: 'p1',
            clientId: 'c1',
            code: 'P1',
            title: 'P',
            status: 'active',
            createdAt: t0,
            updatedAt: u,
          );
      RemoteProject rp(DateTime u) => RemoteProject(
            id: 'p1',
            orgId: 'o',
            clientId: 'c1',
            code: 'P1',
            title: 'P',
            rate: null,
            status: 'active',
            archivedAt: null,
            createdAt: t0,
            updatedAt: u,
            deletedAt: null,
            serverSeq: 1,
          );
      expect(decideProjectMergeFor(local(t0), rp(t1)), MergeAction.apply);
      expect(decideProjectMergeFor(local(t1), rp(t0)), MergeAction.skip);
      expect(decideProjectMergeFor(null, rp(t0)), MergeAction.apply);
    });
  });
}
