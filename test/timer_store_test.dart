import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/tracker/timer_store.dart';

// TimerStore bridges the pure TimerSession to the DB-backed active-timer row
// (PRD #189, Phase 3). These tests drive the transitions with a controlled
// `now` and simulate the UI's per-second ticks with `tick()`, then assert both
// the persisted row and — the point of the whole slice — that a fresh store
// RECOVERS a running/paused timer from that row across a "restart".

void main() {
  late AppDatabase db;
  late String projectId;
  late String taskId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final clientId = await db.addClient(name: 'Co', defaultRate: 100);
    projectId = await db.addProject(
      clientId: clientId,
      code: 'P1',
      title: 'Work',
    );
    taskId = await db.addTask(projectId: projectId, title: 'Build');
  });

  tearDown(() => db.close());

  final t0 = DateTime(2026, 7, 12, 9);

  test('start persists a running active-timer row bound to the work', () async {
    final store = TimerStore(db);
    await store.start(projectId, taskId, now: t0);

    final row = await db.activeTimer();
    expect(row, isNotNull);
    expect(row!.projectId, projectId);
    expect(row.taskId, taskId);
    expect(row.startedAt, t0);
    expect(row.runningSince, t0, reason: 'running → runningSince set');
    expect(row.accumulatedSeconds, 0);
    expect(store.session.isRunning, isTrue);
  });

  test('pause freezes accumulated seconds and clears runningSince', () async {
    final store = TimerStore(db);
    await store.start(projectId, taskId, now: t0);
    for (var i = 0; i < 5; i++) {
      store.tick(); // the UI clock; 5 seconds elapse
    }
    await store.pause(now: t0.add(const Duration(seconds: 5)));

    final row = await db.activeTimer();
    expect(row!.accumulatedSeconds, 5, reason: 'frozen at pause');
    expect(row.runningSince, isNull, reason: 'paused');
    expect(store.session.isRunning, isFalse);
  });

  test('resume re-arms runningSince, keeping accumulated', () async {
    final store = TimerStore(db);
    await store.start(projectId, taskId, now: t0);
    for (var i = 0; i < 5; i++) {
      store.tick();
    }
    await store.pause(now: t0.add(const Duration(seconds: 5)));
    await store.start(projectId, taskId, now: t0.add(const Duration(seconds: 10)));

    final row = await db.activeTimer();
    expect(row!.accumulatedSeconds, 5, reason: 'carried across the pause');
    expect(row.runningSince, t0.add(const Duration(seconds: 10)));
  });

  test('recover rebuilds a RUNNING timer, deriving elapsed from the clock', () async {
    // First store starts + persists, then "the app dies".
    final first = TimerStore(db);
    await first.start(projectId, taskId, now: t0);

    // A fresh store recovers 30s later — elapsed is derived from runningSince,
    // not from any counted ticks (which a crash would have lost).
    final recovered = TimerStore(db);
    await recovered.recover(now: t0.add(const Duration(seconds: 30)));

    expect(recovered.session.isRunning, isTrue);
    expect(recovered.session.elapsed, 30);
    expect(recovered.session.boundProjectId, projectId);
    expect(recovered.session.boundTaskId, taskId);
  });

  test('recover rebuilds a PAUSED timer at its frozen elapsed', () async {
    final first = TimerStore(db);
    await first.start(projectId, taskId, now: t0);
    for (var i = 0; i < 8; i++) {
      first.tick();
    }
    await first.pause(now: t0.add(const Duration(seconds: 8)));

    final recovered = TimerStore(db);
    // Even hours later, a paused timer recovers to its frozen elapsed (no gap
    // is added while runningSince is null).
    await recovered.recover(now: t0.add(const Duration(hours: 3)));

    expect(recovered.session.isRunning, isFalse);
    expect(recovered.session.elapsed, 8);
  });

  test('finish writes the TimeEntry and tombstones the active-timer row', () async {
    final store = TimerStore(db);
    await store.start(projectId, taskId, now: t0);
    for (var i = 0; i < 12; i++) {
      store.tick();
    }
    final finished = await store.finish(
      now: t0.add(const Duration(seconds: 12)),
      description: 'session note',
    );

    expect(finished, isNotNull);
    expect(finished!.seconds, 12);

    // The entry landed…
    final entries = await db.select(db.timeEntries).get();
    expect(entries, hasLength(1));
    expect(entries.single.seconds, 12);
    expect(entries.single.description, 'session note');
    expect(entries.single.taskId, taskId);

    // …and the active-timer row is gone (tombstoned), session reset.
    expect(await db.activeTimer(), isNull);
    expect(store.session.hasSession, isFalse);
  });

  test('description persists on the row and is recovered across a restart', () async {
    final first = TimerStore(db);
    await first.start(projectId, taskId, now: t0, description: 'wire up auth');

    // The note is on the row…
    expect((await db.activeTimer())!.description, 'wire up auth');

    // …and a fresh store recovers it (the UI seeds its field from this).
    final recovered = TimerStore(db);
    await recovered.recover(now: t0.add(const Duration(seconds: 10)));
    expect(recovered.recoveredDescription, 'wire up auth');

    // Finishing the recovered timer writes the note onto the entry.
    final finished = await recovered.finish(
      now: t0.add(const Duration(seconds: 10)),
      description: recovered.recoveredDescription,
    );
    expect(finished, isNotNull);
    expect((await db.select(db.timeEntries).get()).single.description, 'wire up auth');
  });

  test('finish with nothing recorded still clears the row', () async {
    final store = TimerStore(db);
    await store.start(projectId, taskId, now: t0);
    // No ticks → 0 seconds → nothing worth an entry.
    final finished = await store.finish(now: t0);

    expect(finished, isNull);
    expect(await db.select(db.timeEntries).get(), isEmpty);
    expect(await db.activeTimer(), isNull, reason: 'row still tombstoned');
  });
}
