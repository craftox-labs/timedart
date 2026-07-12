import 'package:drift/drift.dart' show Value;

import 'package:timedart/data/database.dart';
import 'package:timedart/data/id.dart';

import 'timer_session.dart';

/// Owns persistence of the single active-timer row (PRD #189, Phase 3),
/// bridging the pure [TimerSession] state machine to the DB so a running timer
/// survives a restart and syncs across devices. Transitions mirror
/// TimerSession's (start / pause / finish) and additionally write the durable
/// row; [recover] rebuilds the in-memory session from a persisted row on
/// startup.
///
/// The row is written only on transitions, never per tick — `accumulatedSeconds`
/// freezes tracked time at each transition and `runningSince` marks the current
/// run's start, so elapsed is *derived* (see [ActiveTimers]) and a crash mid-run
/// recovers the true elapsed from the wall clock, not from counted ticks.
///
/// Deliberately Flutter-free (like [TimerSession]) so the future companion CLI
/// can reuse it; the UI drives [tick] from its own clock and renders [session].
class TimerStore {
  TimerStore(this._db);

  final AppDatabase _db;
  final TimerSession _session = TimerSession();
  String? _rowId; // the persisted active-timer row, once created
  String? _recoveredDescription; // session note read back on recover()

  TimerSession get session => _session;

  /// The session note restored from the persisted row on [recover] (null if
  /// none / no row). The UI seeds its description field from this.
  String? get recoveredDescription => _recoveredDescription;

  /// Rebuild the in-memory session from the persisted live row, if any. Elapsed
  /// is derived: frozen accumulated seconds plus the gap since the run resumed.
  Future<void> recover({required DateTime now}) async {
    final row = await _db.activeTimer();
    if (row == null) return;
    _rowId = row.id;
    _recoveredDescription = row.description;
    final runningSince = row.runningSince;
    final gap = runningSince == null
        ? 0
        : now.difference(runningSince).inSeconds;
    _session.restore(
      elapsed: row.accumulatedSeconds + (gap < 0 ? 0 : gap),
      startedAt: row.startedAt,
      projectId: row.projectId,
      taskId: row.taskId,
      running: runningSince != null,
    );
  }

  /// Start or resume; binds project/task at first start (a no-op while running).
  /// [description] is the current session note, persisted so it survives a
  /// restart (finalised on [finish], which reads the live field).
  Future<void> start(
    String? projectId,
    String? taskId, {
    required DateTime now,
    String? description,
  }) async {
    if (_session.isRunning) return;
    _session.start(projectId, taskId, now: now);
    await _persist(now: now, running: true, description: description);
  }

  Future<void> pause({required DateTime now, String? description}) async {
    if (!_session.isRunning) return;
    _session.pause();
    await _persist(now: now, running: false, description: description);
  }

  /// Advance the in-memory display clock one second (durable state is unchanged
  /// — it's derived from timestamps, not ticked).
  void tick() => _session.tick();

  /// Stop: persist the finished span as a [TimeEntry], tombstone the
  /// active-timer row, and reset the session. Returns what was saved, or null
  /// when there's nothing to record (empty session or no bound project/task).
  Future<FinishedSession?> finish({
    required DateTime now,
    String? description,
  }) async {
    final finished = _session.finish(now: now);
    if (finished != null) {
      await _db.addEntry(
        projectId: finished.projectId,
        taskId: finished.taskId,
        description: description,
        startedAt: finished.startedAt,
        endedAt: finished.endedAt,
        seconds: finished.seconds,
      );
    }
    final rowId = _rowId;
    if (rowId != null) {
      await _db.tombstoneActiveTimer(rowId);
      _rowId = null;
    }
    _session.reset();
    return finished;
  }

  Future<void> _persist({
    required DateTime now,
    required bool running,
    String? description,
  }) async {
    final id = _rowId ??= idGen.newId();
    await _db.saveActiveTimer(
      ActiveTimersCompanion(
        id: Value(id),
        projectId: Value(_session.boundProjectId),
        taskId: Value(_session.boundTaskId),
        description: Value(description),
        startedAt: Value(_session.startedAt),
        // Frozen at each transition: at start it's the pre-run base, at pause the
        // full tracked total (recovery adds the running gap on top).
        accumulatedSeconds: Value(_session.elapsed),
        runningSince: Value(running ? now : null),
      ),
    );
  }
}
