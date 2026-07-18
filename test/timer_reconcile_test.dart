import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/tracker/timer_store.dart';
import 'package:timedart/features/tracker/timer_view.dart';

// Live-refresh of the running timer (#274 gap fix): TimerStore.reconcile maps a
// watchActiveTimer emission onto the in-memory session for every external
// transition, and TimerController drives its ticker/description from that.

void main() {
  late AppDatabase db;
  late String projectId;
  late String taskId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final clientId = await db.addClient(name: 'Co', defaultRate: 100);
    projectId = await db.addProject(clientId: clientId, code: 'P1', title: 'Work');
    taskId = await db.addTask(projectId: projectId, title: 'Build');
  });
  tearDown(() => db.close());

  final t0 = DateTime(2026, 7, 12, 9);

  // Write (or update) the single active-timer row as an external writer would,
  // then read it back the way watchActiveTimer would deliver it.
  Future<ActiveTimer> writeRow({
    required bool running,
    int accumulated = 0,
    DateTime? runningSince,
    String? description,
    String id = 'ext-row',
  }) async {
    await db.saveActiveTimer(
      ActiveTimersCompanion(
        id: Value(id),
        projectId: Value(projectId),
        taskId: Value(taskId),
        description: Value(description),
        startedAt: Value(t0),
        accumulatedSeconds: Value(accumulated),
        runningSince: Value(running ? (runningSince ?? t0) : null),
      ),
    );
    return (await db.activeTimer())!;
  }

  group('TimerStore.reconcile transitions', () {
    test('external start → adopts a running session with derived elapsed', () async {
      final store = TimerStore(db);
      final row = await writeRow(
        running: true,
        runningSince: t0,
        description: 'from cli',
      );
      final outcome = store.reconcile(
        row,
        now: t0.add(const Duration(seconds: 30)),
      );
      expect(outcome, TimerReconcile.adopted);
      expect(store.session.isRunning, isTrue);
      expect(store.session.boundProjectId, projectId);
      expect(store.session.boundTaskId, taskId);
      expect(store.session.elapsed, 30); // accumulated(0) + gap(30)
      expect(store.recoveredDescription, 'from cli');
    });

    test('external stop (null row) → clears the session', () async {
      final store = TimerStore(db);
      store.reconcile(await writeRow(running: true), now: t0);
      expect(store.session.hasSession, isTrue);

      final outcome = store.reconcile(null, now: t0);
      expect(outcome, TimerReconcile.cleared);
      expect(store.session.hasSession, isFalse);
      expect(store.session.isRunning, isFalse);
    });

    test('external pause then resume tracks the run flag + elapsed', () async {
      final store = TimerStore(db);
      store.reconcile(await writeRow(running: true, runningSince: t0), now: t0);

      // Pause at +50s: accumulated frozen to 50, runningSince null.
      final paused = await writeRow(running: false, accumulated: 50);
      final o1 = store.reconcile(paused, now: t0.add(const Duration(minutes: 5)));
      expect(o1, TimerReconcile.updated);
      expect(store.session.isRunning, isFalse);
      expect(store.session.elapsed, 50); // frozen; no gap while paused

      // Resume: runningSince set again, accumulated stays 50.
      final resumedSince = t0.add(const Duration(minutes: 10));
      final resumed = await writeRow(
        running: true,
        accumulated: 50,
        runningSince: resumedSince,
      );
      final o2 = store.reconcile(
        resumed,
        now: resumedSince.add(const Duration(seconds: 10)),
      );
      expect(o2, TimerReconcile.updated);
      expect(store.session.isRunning, isTrue);
      expect(store.session.elapsed, 60); // 50 accumulated + 10 gap
    });

    test('an emission matching the current session is a no-op (no-clobber)', () async {
      final store = TimerStore(db);
      final row = await writeRow(running: true, runningSince: t0);
      store.reconcile(row, now: t0.add(const Duration(seconds: 5)));
      final before = store.session.elapsed;

      // The SAME row emits again (e.g. the app's own write echoing back).
      final outcome = store.reconcile(
        row,
        now: t0.add(const Duration(seconds: 99)),
      );
      expect(outcome, TimerReconcile.unchanged);
      expect(store.session.elapsed, before, reason: 'no jitter on own write');
      expect(store.session.isRunning, isTrue);
    });

    test('null row with no session is unchanged', () {
      final store = TimerStore(db);
      expect(store.reconcile(null, now: t0), TimerReconcile.unchanged);
    });

    test('startup recover still restores a running timer', () async {
      await writeRow(running: true, runningSince: t0, description: 'note');
      final store = TimerStore(db);
      await store.recover(now: t0.add(const Duration(seconds: 20)));
      expect(store.session.isRunning, isTrue);
      expect(store.session.elapsed, 20);
      expect(store.recoveredDescription, 'note');
    });
  });

  group('TimerController via watchActiveTimer', () {
    test('external start makes the controller report running; stop clears it', () async {
      final controller = TimerController(db);
      addTearDown(controller.dispose);
      await pumpEventQueue(); // initial (empty) emission

      expect(controller.hasSession, isFalse);

      // External writer (as the CLI would) starts a timer.
      await writeRow(running: true, description: 'cli work');
      await pumpEventQueue();
      expect(controller.isRunning, isTrue);
      expect(controller.boundProjectId, projectId);
      expect(controller.description.text, 'cli work');

      // External stop tombstones the row.
      await db.tombstoneActiveTimer('ext-row');
      await pumpEventQueue();
      expect(controller.hasSession, isFalse);
      expect(controller.isRunning, isFalse);
    });

    test('the controller\'s own start is not reset by the echoed emission', () async {
      final controller = TimerController(db);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      await controller.startOrResume(projectId, taskId);
      await pumpEventQueue(); // its own write echoes back on the stream
      expect(controller.isRunning, isTrue);
      expect(controller.boundProjectId, projectId);
    });
  });
}
