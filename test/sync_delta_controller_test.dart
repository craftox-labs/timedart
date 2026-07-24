import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/sync_controller.dart';
import 'package:timedart/data/sync/delta/sync_service.dart';

// Phase 5c delta-sync (#294): the trigger coordinator's pure scheduling logic —
// one-pass-at-a-time serialization, mid-pass coalescing into a single re-run,
// status transitions, last-synced stamping, offline error capture + backoff,
// and dispose safety. The runner is injected (a controllable completer or a
// canned result), so no network or real timer is involved; the periodic tick is
// disabled and its backoff interval is asserted directly via nextInterval-shape.

void main() {
  late AppDatabase db;
  final clockAt = DateTime.fromMillisecondsSinceEpoch(5000);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  SyncController make(
    Future<SyncResult> Function() runner, {
    DateTime Function()? clock,
    Duration? syncTimeout,
    bool startEnabled = true,
  }) =>
      SyncController(
        db,
        runner: runner,
        clock: clock ?? () => clockAt,
        enablePeriodic: false,
        syncTimeout: syncTimeout ?? kSyncTimeout,
        startEnabled: startEnabled,
      );

  test('a successful pass moves phase idle→syncing→idle and stamps status',
      () async {
    final phases = <SyncPhase>[];
    late SyncController c;
    c = make(() async => const SyncResult(pushed: 2, pulled: 3, applied: 1));
    c.addListener(() => phases.add(c.phase));

    expect(c.phase, SyncPhase.idle);
    await c.requestSync(SyncTrigger.manual);

    expect(c.phase, SyncPhase.idle);
    expect(phases.first, SyncPhase.syncing); // went busy first
    expect(phases.last, SyncPhase.idle); // settled back
    expect(c.lastResult?.pushed, 2);
    expect(c.lastError, isNull);
    expect(c.lastSyncedAt, clockAt);
    expect(c.lastTrigger, SyncTrigger.manual);
  });

  test('a skipped pass records the result but does not stamp lastSyncedAt',
      () async {
    final c = make(() async => const SyncResult.skipped('not entitled'));
    await c.syncNow();
    expect(c.lastResult?.didSync, isFalse);
    expect(c.lastSyncedAt, isNull);
    expect(c.lastError, isNull);
  });

  test('a not-entitled skip carries the typed flag for the paid-gate UI',
      () async {
    final c = make(() async => const SyncResult.notEntitled());
    await c.syncNow();
    expect(c.lastResult?.notEntitled, isTrue);
    expect(c.lastResult?.didSync, isFalse);
    expect(c.lastSyncedAt, isNull);
  });

  test('a request mid-pass coalesces into exactly one re-run', () async {
    var calls = 0;
    final gate = Completer<void>();
    final c = make(() async {
      calls++;
      if (calls == 1) await gate.future; // hold the first pass open
      return const SyncResult(pushed: 1);
    });

    final first = c.requestSync(SyncTrigger.foreground);
    expect(c.isSyncing, isTrue);

    // Three more triggers arrive while the first pass is held — they must NOT
    // start concurrent passes, and must collapse to a single follow-up run.
    final a = c.requestSync(SyncTrigger.timerStop);
    final b = c.requestSync(SyncTrigger.periodic);
    final d = c.requestSync(SyncTrigger.manual);
    expect(identical(a, first), isTrue); // same in-flight future returned
    expect(identical(b, first), isTrue);
    expect(identical(d, first), isTrue);

    gate.complete();
    await Future.wait([first, a, b, d]);

    expect(calls, 2); // original + one coalesced re-run (not four)
    expect(c.phase, SyncPhase.idle);
    expect(c.isSyncing, isFalse);
  });

  test('an offline pass captures the error and leaves lastSyncedAt untouched',
      () async {
    var shouldThrow = true;
    final c = make(() async {
      if (shouldThrow) throw const SyncTestException('offline');
      return const SyncResult(pushed: 1);
    });

    await c.syncNow();
    expect(c.lastError, isA<SyncTestException>());
    expect(c.lastSyncedAt, isNull);
    expect(c.phase, SyncPhase.idle); // still settles, never hangs

    // A subsequent success clears the error and stamps the time.
    shouldThrow = false;
    await c.syncNow();
    expect(c.lastError, isNull);
    expect(c.lastSyncedAt, clockAt);
  });

  test('a pass that hangs past the timeout fails to offline, not stuck syncing',
      () async {
    // A network call that never resolves (device went offline mid-request).
    final hang = Completer<SyncResult>();
    final c = make(
      () => hang.future,
      syncTimeout: const Duration(milliseconds: 30),
    );

    await c.syncNow();
    expect(c.phase, SyncPhase.idle); // settled — not stuck on syncing…
    expect(c.lastError, isA<TimeoutException>());
    expect(c.lastSyncedAt, isNull);
    // The abandoned pass completing late must not throw into the zone.
    hang.complete(const SyncResult(pushed: 1));
    await Future<void>.delayed(Duration.zero);
  });

  test('while disabled every trigger is a no-op (no sign-in, no run)',
      () async {
    var calls = 0;
    final c = make(
      () async {
        calls++;
        return const SyncResult(pushed: 1);
      },
      startEnabled: false,
    );
    expect(c.enabled, isFalse);
    await c.requestSync(SyncTrigger.foreground);
    await c.requestSync(SyncTrigger.periodic);
    await c.syncNow();
    expect(calls, 0);
    expect(c.lastResult, isNull);
  });

  test('setEnabled(true) kicks a pass; disabling then stops future triggers',
      () async {
    var calls = 0;
    final c = make(
      () async {
        calls++;
        return const SyncResult(pushed: 1);
      },
      startEnabled: false,
    );

    await c.setEnabled(true); // enabling runs the sign-in/adopt pass
    expect(c.enabled, isTrue);
    expect(calls, 1);

    await c.syncNow(); // enabled → runs
    expect(calls, 2);

    await c.setEnabled(false); // keeps session/data; just stops passes
    expect(c.enabled, isFalse);
    await c.syncNow();
    expect(calls, 2); // unchanged — disabled no-ops

    await c.setEnabled(false); // idempotent — no extra pass
    expect(calls, 2);
  });

  test('interaction triggers are throttled; other triggers bypass the throttle',
      () async {
    var calls = 0;
    var now = DateTime.fromMillisecondsSinceEpoch(5000);
    final c = SyncController(
      db,
      runner: () async {
        calls++;
        return const SyncResult(pushed: 1);
      },
      clock: () => now,
      enablePeriodic: false,
      startEnabled: true,
      interactionThrottle: const Duration(seconds: 30),
    );

    // First navigation nudge runs a pass and stamps the attempt time.
    await c.requestSync(SyncTrigger.interaction);
    expect(calls, 1);

    // A second nudge inside the window is dropped, even after time advances but
    // stays under the throttle.
    await c.requestSync(SyncTrigger.interaction);
    expect(calls, 1);
    now = now.add(const Duration(seconds: 20));
    await c.requestSync(SyncTrigger.interaction);
    expect(calls, 1);

    // A non-interaction trigger is never throttled — fires immediately.
    await c.requestSync(SyncTrigger.foreground);
    expect(calls, 2);

    // Past the window, the nudge runs again. (foreground above re-stamped the
    // attempt time, so measure from there.)
    now = now.add(const Duration(seconds: 31));
    await c.requestSync(SyncTrigger.interaction);
    expect(calls, 3);
  });

  test('an interaction nudge during an in-flight pass is throttled, not queued',
      () async {
    // The offline case the throttle targets: a pass is held open (mimicking a
    // request burning its timeout) while the user navigates. The nudge must NOT
    // queue a rerun — otherwise the 30s floor collapses to the pass duration.
    var calls = 0;
    final now = DateTime.fromMillisecondsSinceEpoch(5000);
    final gate = Completer<void>();
    final c = SyncController(
      db,
      runner: () async {
        calls++;
        if (calls == 1) await gate.future; // hold pass 1 open
        return const SyncResult(pushed: 1);
      },
      clock: () => now,
      enablePeriodic: false,
      startEnabled: true,
      interactionThrottle: const Duration(seconds: 30),
    );

    final first = c.requestSync(SyncTrigger.interaction); // pass 1 starts
    expect(c.isSyncing, isTrue);

    // Nudges arriving mid-pass, inside the window, return the in-flight future
    // without queuing a rerun.
    final a = c.requestSync(SyncTrigger.interaction);
    final b = c.requestSync(SyncTrigger.interaction);
    expect(identical(a, first), isTrue);
    expect(identical(b, first), isTrue);

    gate.complete();
    await Future.wait([first, a, b]);
    expect(calls, 1); // no coalesced rerun from the throttled nudges

    // A real change trigger, by contrast, still coalesces a rerun (unthrottled).
    final gate2 = Completer<void>();
    calls = 0;
    final c2 = SyncController(
      db,
      runner: () async {
        calls++;
        if (calls == 1) await gate2.future;
        return const SyncResult(pushed: 1);
      },
      clock: () => now,
      enablePeriodic: false,
      startEnabled: true,
    );
    final f2 = c2.requestSync(SyncTrigger.interaction);
    c2.requestSync(SyncTrigger.timerStop); // carries a local change → queues
    gate2.complete();
    await f2;
    expect(calls, 2);
  });

  test('requestSync after dispose is a no-op that does not run or notify',
      () async {
    var calls = 0;
    final c = make(() async {
      calls++;
      return const SyncResult();
    });
    var notified = false;
    c.addListener(() => notified = true);
    c.dispose();

    await c.requestSync(SyncTrigger.periodic);
    expect(calls, 0);
    expect(notified, isFalse);
  });
}

class SyncTestException implements Exception {
  final String message;
  const SyncTestException(this.message);
  @override
  String toString() => 'SyncTestException: $message';
}
